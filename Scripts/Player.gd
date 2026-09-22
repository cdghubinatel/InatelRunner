extends CharacterBody3D

@onready var game_over_screen = $HUD/GameOverScreen
@onready var levelup_screen = $HUD/LevelUpScreen
@onready var name_input_container = $HUD/GameOverScreen/Container/Results/NameInputContainer
@onready var name_edit = $HUD/GameOverScreen/Container/Results/NameInputContainer/LineEdit
@onready var ranking_display = $HUD/GameOverScreen/Container/Results/RankingDisplay
@onready var save_button = $HUD/GameOverScreen/Container/Results/NameInputContainer/SaveButton
@onready var game_timer = $GameTimer
@onready var game_results_label = $HUD/GameOverScreen/Container/Results/Label
@onready var progress_button = $HUD/GameOverScreen/Container/Results/ProgressButton
@onready var world = get_node("/root/Main/World") 
@onready var main = get_node("/root/Main/") 
@onready var start_screen = $HUD/StartScreen
@onready var level_pass_music = $Sounds/LevelPassMusic
@onready var level_fail_music = $Sounds/LevelFailMusic
@onready var jump_sfx = $Sounds/JumpSFX

# --- VARIÁVEIS DE ESTADO ---
var is_jumping = false
var game_starts = false
var game_won = false

# --- VARIÁVEIS DE MOVIMENTO ---
var speed = 6.0
var jump_velocity = 10.0 
const jump_speed = 6.0 
const gravity = 20

#Variáveis para o sistema de faixas
var target_lane = 1          # 0: Esquerda, 1: Centro, 2: Direita
var lane_distance = 2.5      # Distância horizontal entre as faixas
var lane_transition_speed = 15.0 # Velocidade da transição entre faixas



# --- INTEGRAÇÃO HEAD TRACKER ---
var head_tracker_node = null
var use_head_tracking = true
var sensitivity = 3.0 

# Game State
enum game_state {CONTINUE, RETRY}
var current_state

# --- EFEITOS DE DANO ---
var is_taking_damage: bool = false
var overlay_tween: Tween
var shake_tween: Tween
var default_cam_h: float = 0.0
var default_cam_v: float = 0.0

func _ready():
	setup_damage_overlay()
	start_screen.visible = true
	
	if main.has_node("HeadTracker"):
		head_tracker_node = main.get_node("HeadTracker")
		print("HeadTracker encontrado e conectado!")
	else:
		print("HeadTracker não encontrado. A usar apenas teclado.")

func setup_damage_overlay():
	var damage_overlay = $HUD.get_node_or_null("DamageOverlay")
	if not damage_overlay:
		damage_overlay = ColorRect.new()
		damage_overlay.name = "DamageOverlay"
		damage_overlay.color = Color(1.0, 0.0, 0.0, 0.0)
		damage_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		damage_overlay.visible = false
		$HUD.add_child(damage_overlay)

func _physics_process(delta):
	handle_movement(delta)

func handle_movement(delta):
	if game_starts and not game_won:
		
		# --- 1. LÓGICA DE MOVIMENTO LATERAL ---
		
		# Entrada via Teclado (Mantém para debug)
		if Input.is_action_just_pressed("ui_left"):
			target_lane = max(0, target_lane - 1)
		if Input.is_action_just_pressed("ui_right"):
			target_lane = min(2, target_lane + 1)
		
		# Entrada via Visão Computacional (Braços)
		if head_tracker_node and use_head_tracking:
			# Lemos a nova variável de posição dos braços do C#
			var arm_pos = head_tracker_node.get("ArmCenterPositionX")
			if arm_pos != null:
				# Dividimos a tela em 3 zonas para as faixas
				if arm_pos > 0.6:
					target_lane = 0 # Esquerda
				elif arm_pos < 0.4:
					target_lane = 2 # Direita
				else:
					target_lane = 1 # Centro

		# Cálculo da posição X alvo (Interpolação suave)
		var target_x = (target_lane - 1) * lane_distance
		global_transform.origin.x = move_toward(global_transform.origin.x, target_x, delta * lane_transition_speed * Global.speed_multiplier)

		# --- 2. LÓGICA DE PULO (TECLADO + IA) ---
		
		if is_on_floor():
			# Verificamos o teclado OU a variável ShouldJump do C#
			var ai_jump = head_tracker_node.get("ShouldJump") if head_tracker_node else false
			
			if Input.is_action_just_pressed("ui_jump") or ai_jump:
				perform_jump()
			else:
				is_jumping = false
		else:
			# Aplicar gravidade enquanto estiver no ar
			velocity.y -= gravity * delta

		# Movimento frontal com multiplicador de velocidade (Dificuldade Progressiva)
		velocity.z = (jump_speed if is_jumping else speed) * Global.speed_multiplier
		velocity.x = 0 
		
		move_and_slide()
		
		if velocity.z == 0:
			check_for_platform_collisions()
			
func perform_jump():
	if Global.jump_boost_count > 0:
		jump_velocity = 13
		Global.jump_boost_count -= 1
		Global.jump_boost_updated.emit()
	else: 
		jump_velocity = 10
	velocity.y = jump_velocity
	is_jumping = true
	jump_sfx.play()

func check_for_platform_collisions():
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		if collider and collider.is_in_group("Air_Platform"):
			if collision.get_normal().dot(Vector3(0, 0, -1)) > 0.5: 
				print("[COLISÃO MORTE] Bateu de frente na plataforma aérea: ", collider.name)
				Global.lives = 0
				Global.lives_updated.emit()
				game_over()
				break 

func _input(event):
	if event.is_action_pressed("ui_accept"):
		start_screen.visible = false
		game_starts = true
		Global.game_started = true
		game_timer.start()
		Global.score_requirement = randi_range(Global.min_score_requirement, Global.max_score_requirement)

func _on_game_timer_timeout():
	Global.level_time -= 1
	Global.level_time_updated.emit()
	if Global.level_time <= 0 or Global.lives == 0:
		game_over()

func apply_effect(effect_name):
	match effect_name:
		"increase_score":
			Global.score += 1
			Global.score_updated.emit()
		"boost_jump":
			Global.jump_boost_count += 1
			Global.jump_boost_updated.emit()
		"decrease_time":
			if Global.level_time >= 10:
				Global.level_time -= 10
				Global.level_time_updated.emit()

func play_damage_feedback():
	# Impede novo feedback de dano se a animação anterior ainda estiver em execução
	if is_taking_damage:
		return
	is_taking_damage = true

	# 1. Flash Vermelho + Shake 2D no HUD (Super Leve - Zero recálculo de frustum/matrizes 3D)
	var damage_overlay = $HUD.get_node_or_null("DamageOverlay")
	if not damage_overlay:
		setup_damage_overlay()
		damage_overlay = $HUD.get_node_or_null("DamageOverlay")
	
	if damage_overlay:
		damage_overlay.visible = true
		damage_overlay.color.a = 0.45
		
		if overlay_tween and overlay_tween.is_running():
			overlay_tween.kill()
		overlay_tween = create_tween()
		overlay_tween.set_parallel(true)
		
		# Fade out do filtro vermelho
		overlay_tween.tween_property(damage_overlay, "color:a", 0.0, 0.25)
		
		# Tremor leve na interface 2D no lugar de mover a câmera 3D (0 impacto na CPU/renderizador 3D)
		for i in range(4):
			overlay_tween.tween_property($HUD, "offset", Vector2(randf_range(-10, 10), randf_range(-10, 10)), 0.03)
			overlay_tween.chain()
		overlay_tween.tween_property($HUD, "offset", Vector2.ZERO, 0.03)
		
		overlay_tween.tween_callback(func(): damage_overlay.visible = false)

	# 2. Pisca o modelo 3D do jogador via Tween determinístico (Zero corotinas/create_timer)
	var mesh_node = get_node_or_null("Root Scene")
	if mesh_node:
		var blink_tween = create_tween()
		for i in range(3):
			blink_tween.tween_callback(func(): if is_instance_valid(mesh_node): mesh_node.visible = false)
			blink_tween.tween_interval(0.05)
			blink_tween.tween_callback(func(): if is_instance_valid(mesh_node): mesh_node.visible = true)
			blink_tween.tween_interval(0.05)
		blink_tween.tween_callback(func(): is_taking_damage = false)
	else:
		is_taking_damage = false

func game_over():
	game_timer.stop()
	game_starts = false
	Global.game_started = false
	main.level_music.stop()

	if Global.lives <= 0:
		game_won = false
		game_over_screen.visible = true
		levelup_screen.visible = false
		game_results_label.text = "GAME OVER"
		progress_button.text = "RESTART"
		current_state = game_state.RETRY
		level_fail_music.play()

		check_high_score()
		update_ranking_ui()

	elif Global.level_time <= 0:
		game_won = true
		game_over_screen.visible = false
		levelup_screen.visible = true
		current_state = game_state.CONTINUE
		level_pass_music.play()

	Global.update_results.emit()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
func check_high_score():
	var is_top_score = false
	if Global.ranking_list.size() < 5:
		is_top_score = true
	elif Global.score > Global.ranking_list.back()["score"]:
		is_top_score = true
	
	if is_top_score:
		name_input_container.visible = true
	else:
		name_input_container.visible = false

func _on_save_button_pressed():
	var player_name = name_edit.text.strip_edges()

	if player_name == "":
		player_name = "Player"

	Global.add_to_ranking(player_name, Global.score)
	name_input_container.visible = false
	update_ranking_ui()

func update_ranking_ui():
	for child in ranking_display.get_children():
		child.queue_free()

	if Global.ranking_list.is_empty():
		var empty_label = Label.new()
		empty_label.text = "Nenhum placar salvo ainda."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ranking_display.add_child(empty_label)
		return

	for i in range(Global.ranking_list.size()):
		var entry = Global.ranking_list[i]
		var label = Label.new()
		label.text = "%dº  %s : %d" % [i + 1, entry["name"], entry["score"]]
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 32)
		ranking_display.add_child(label)
		
func reset_game_state():
	is_taking_damage = false
	is_jumping = false
	game_starts = false
	Global.game_started = false
	game_won = false
	game_over_screen.visible = false
	levelup_screen.visible = false
	name_edit.text = ""
	name_input_container.visible = false
	world.reset_world()
	get_tree().paused = false
	start_screen.visible = true
	main.level_music.play()
	
func _on_progress_button_pressed():
	if current_state == game_state.CONTINUE:
		reset_game_state()
		Global.level_up()
	elif current_state == game_state.RETRY:
		reset_game_state()
		Global.retry_level()
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
