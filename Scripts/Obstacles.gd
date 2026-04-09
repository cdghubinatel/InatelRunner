### Obstacles.gd

extends Area3D

# Advanced obstacles
var advanced_obstacles = []

# Node Refs
@onready var damage_sfx = $Sounds/DamageSFX

func _ready():
	spawn_obstacle()
	
# Spawn obstacle	
func spawn_obstacle():
	var obstacle_resource = null
	if randf() < Global.advanced_obstacle_spawn_chance:
		obstacle_resource = Global.advanced_obstacle_resources[randi() % Global.advanced_obstacle_resources.size()]
	else:
		obstacle_resource = Global.obstacle_resources[randi() % Global.obstacle_resources.size()]
		
	var obstacle_instance = obstacle_resource.instantiate()
	
	# If it's an advanced obstacle, move it
	if obstacle_resource in Global.advanced_obstacle_resources:
		var height_above_platform = 1.2
		obstacle_instance.transform.origin.y += height_above_platform
		move_obstacle(obstacle_instance)
		
	add_child(obstacle_instance)
	
	# Otimização FPS E Correção de Dano GHOST: 
	# Desativa as hitboxes sólidas de tijolo (parede) para que o Jogador
	# adentre a Area3D e tome dano fluido sem agarrar fisicamente o modelo 3D.
	disable_solid_physics(obstacle_instance)

	# Expandimos levemente o Sensor primário para garantir hit perfeito nos carros compridos
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
		$CollisionShape3D.set_deferred("disabled", true) # previne hits duplos seguidos
		
		# Oculta instantaneamente a malha do Carro/Objeto, mantendo os sons.
		for child in get_children():
			if child is Node3D and child.name != "Sounds" and child.name != "CollisionShape3D":
				child.visible = false
				
		if Global.lives > 0:
			Global.lives -= 1
			Global.lives_updated.emit()
			damage_sfx.play()
			print("Deducting Lives")
		else:
			print("Game over")
		
# Move Advanced Obstacles
func move_obstacle(obstacle_instance):
	var speed = -3
	# Store the obstacle instance and its speed in a dictionary
	var obstacle_data = {"instance": obstacle_instance, "speed": speed}
	# Add the obstacle data to an array to keep track of all moving obstacles
	advanced_obstacles.append(obstacle_data)
	
func _process(delta):
	if Global.game_started:
		# Update the position of all moving obstacles
		for obstacle_data in advanced_obstacles:
			var obstacle = obstacle_data["instance"]
			var speed = obstacle_data["speed"]
			obstacle.transform.origin += Vector3(0, 0, speed * delta)
	
