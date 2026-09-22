### Obstacles.gd

extends Area3D

# Move Speed para obstáculos dinâmicos (carros, abelhas, etc.)
var move_speed: float = 0.0

# Node Refs
@onready var damage_sfx = $Sounds/DamageSFX

func _ready():
	set_process(false)
	spawn_obstacle()
	# Pré-aquecimento do áudio de dano (carrega o MP3/Stream na RAM no spawn inicial)
	if damage_sfx:
		damage_sfx.volume_db = -80.0
		damage_sfx.play()
		damage_sfx.stop()
		damage_sfx.volume_db = 10.0
	
func reset_obstacle():
	move_speed = 0.0
	set_process(false)
	for child in get_children():
		if child is Node3D and child.name != "Sounds" and child.name != "CollisionShape3D":
			child.queue_free()
	
	$CollisionShape3D.set_deferred("disabled", false)
	# Recria o modelo visual do obstáculo para a nova utilização do nó reutilizado do pool
	spawn_obstacle()
	
# Spawn obstacle	
func spawn_obstacle():
	var obstacle_resource = null
	if randf() < Global.advanced_obstacle_spawn_chance:
		obstacle_resource = Global.advanced_obstacle_resources[randi() % Global.advanced_obstacle_resources.size()]
	else:
		obstacle_resource = Global.obstacle_resources[randi() % Global.obstacle_resources.size()]
		
	var obstacle_instance = obstacle_resource.instantiate()
	
	var res_path = obstacle_resource.resource_path
	var is_car = res_path.find("car_") != -1
	var is_advanced = obstacle_resource in Global.advanced_obstacle_resources
	
	if is_car or is_advanced:
		if is_advanced:
			var height_above_platform = 1.2
			obstacle_instance.transform.origin.y += height_above_platform
		
		# Move o nó Area3D inteiro (malha + hitbox de colisão juntos!)
		move_speed = -12 if is_car else -3
		set_process(true)
	else:
		move_speed = 0.0
		set_process(false)
		
	add_child(obstacle_instance)
	
	# Desativa as hitboxes sólidas para evitar travamento físico no modelo 3D
	disable_solid_physics(obstacle_instance)

	# Expandimos levemente o Sensor primário para garantir hit perfeito nos carros compridos
	if $CollisionShape3D and $CollisionShape3D.shape:
		$CollisionShape3D.shape.radius = 0.8

func disable_solid_physics(node):
	if node is StaticBody3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children():
		disable_solid_physics(child)
	
# Player and Obstacle collision
func _on_body_entered(body):
	if body.is_in_group("Player"):
		var obstacle_name = "Objeto Desconhecido"
		for child in get_children():
			if child is Node3D and child.name != "Sounds" and child.name != "CollisionShape3D":
				obstacle_name = child.name
				child.visible = false
				
		print("[COLISÃO DANO] Jogador atingiu: ", obstacle_name, " | Nó: ", name, " | Pos: ", global_position)

		$CollisionShape3D.set_deferred("disabled", true) # previne hits duplos seguidos
		
		if Global.lives > 0:
			Global.lives -= 1
			Global.lives_updated.emit()
			damage_sfx.play()
			if body.has_method("play_damage_feedback"):
				body.play_damage_feedback()
			if Global.lives == 0 and body.has_method("game_over"):
				body.game_over()
		else:
			print("Game over")
		
func _process(delta):
	if Global.game_started and move_speed != 0.0:
		transform.origin += Vector3(0, 0, move_speed * delta)
	
