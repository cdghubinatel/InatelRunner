### World.gd

extends StaticBody3D

# Node reference
@onready var platforms = $Platforms
@onready var obstacles = $Obstacles
@onready var environment = $Environment
@onready var collectibles = $Collectibles

# --- OBJECT POOL SYSTEM ---
var object_pool = {}

func get_instance(resource: PackedScene) -> Node3D:
	var res_path = resource.resource_path
	if object_pool.has(res_path) and object_pool[res_path].size() > 0:
		var instance = object_pool[res_path].pop_back()
		instance.visible = true
		instance.process_mode = Node.PROCESS_MODE_INHERIT # Reativa a física e scripts
		if instance.has_method("reset_obstacle"):
			instance.reset_obstacle()
		return instance
	else:
		var instance = resource.instantiate()
		instance.set_meta("pool_path", res_path)
		return instance

func return_to_pool(instance: Node3D):
	if instance.has_meta("pool_path"):
		var res_path = instance.get_meta("pool_path")
		if not object_pool.has(res_path):
			object_pool[res_path] = []
		instance.visible = false
		instance.process_mode = Node.PROCESS_MODE_DISABLED # Desativa física e CPU por completo!
		instance.transform.origin = Vector3(0, -100, 0) 
		object_pool[res_path].append(instance)
	else:
		instance.queue_free()
# -------------------------

# Platform vars
var max_spawn_distance = 60.0
var last_platform_position = Vector3()
var last_air_platform_position = Vector3()
var platform_length = 4
var initial_platform_count = 8
var cleanup_object_count = 30.0
var platforms_without_obstacles = 0
var player

# Environmental variables
const min_platform_distance = 10.0
const max_platform_distance = 30.0
const left_side = -1
const right_side = 1
const ground_position = -0.5

func _ready():
	initialize_game_elements()
	
# Initial game state when level loads
func initialize_game_elements():
	player = get_node_or_null("/root/Main/Player") 
	player.position = Vector3(0, 0, 0)
	last_air_platform_position = Vector3(0, 0, 5)
	# Spawn the initial objects
	for i in range(initial_platform_count):
		spawn_platform_segment()
		spawn_air_platform_segments()
		spawn_obstacle()   
		spawn_environmental_segment(last_platform_position.z)
		spawn_sidewalk(i * platform_length, ground_position)
	
# Spawn and cleanup objects
func _on_timer_timeout():
	if not player: return
	
	var player_z = player.global_transform.origin.z
	while last_platform_position.z < player_z + max_spawn_distance:
		spawn_platform_segment()
		spawn_air_platform_segments()
		spawn_obstacle()   
		spawn_environmental_segment(last_platform_position.z)
		spawn_sidewalk(last_platform_position.z, ground_position)
	
	cleanup_old_objects()
	
# Spawn platforms
func spawn_platform_segment():
	# Randomly select a platform resource
	var platform_resource = Global.platform_resources[randi() % Global.platform_resources.size()]
	var new_platform = get_instance(platform_resource)
	new_platform.transform.origin = last_platform_position
	new_platform.scale.x = 3
	if not new_platform.get_parent(): platforms.add_child(new_platform)
	# Update the position for the next path segment
	last_platform_position += Vector3(0, 0, platform_length)
	# Spawn collectible on platform
	if new_platform:
		call_deferred("spawn_collectible", new_platform)
	
# Spawn air platforms
func spawn_air_platform_segments():
	# Decide randomly whether to spawn an in-air platform or a series of platforms
	if randf() < Global.air_platform_spawn_chance:
		# Decide the number of platforms to form a path in the air
		var number_of_in_air_platforms = randi_range(3, 5)  
		var y_position = 1.5 # Height above the ground platforms
		# Choose a random X position for the entire sequence
		
		var lane = randi_range(-1, 1)
		var x_position = lane * 2
		for i in range(number_of_in_air_platforms):
			var platform_resource = Global.air_platforms_resources[randi() % Global.air_platforms_resources.size()]
			var new_platform = get_instance(platform_resource)
			var z_position = last_air_platform_position.z + i
			new_platform.transform.origin = Vector3(x_position, y_position, z_position)
			if not new_platform.get_parent(): platforms.add_child(new_platform)
			if new_platform:
				call_deferred("spawn_collectible", new_platform)
		# Update the position to be after the last spawned in-air platform
		last_air_platform_position.z += platform_length * number_of_in_air_platforms
	
# Spawn Obstacles
func spawn_obstacle():
	# Decide how many obstacles to spawn in a row (e.g., 1 to 3)
	var possible_x_positions = [-2.5, 0, 2.5]
	possible_x_positions.shuffle()
	var obstacles_in_row = randi_range(1, 2)
	var spacing = 1  # obstacle spacing in between
	# Spawn random obstacles
	# Spawn random obstacles ou força spawn se demorou demais
	if randf() < Global.obstacle_spawn_chance or platforms_without_obstacles >= 3:
		platforms_without_obstacles = 0
		for i in range(obstacles_in_row):
			var obstacle_instance = get_instance(Global.obstacle_scene)
			var x_position_index = i % possible_x_positions.size()
			var x_position = possible_x_positions[x_position_index]
			obstacle_instance.transform.origin = last_platform_position + Vector3(x_position * spacing, 0, platform_length)
			if not obstacle_instance.get_parent(): obstacles.add_child(obstacle_instance)
	else:
		platforms_without_obstacles += 1
	

# Spawn Environmentals	
func spawn_sidewalk(along_z: float, y_level: float):
	# Certifique-se que no Global.gd o "sidewalk" aponta para um asset de calçada/chão
	var sidewalk_res = Global.environment_resources["sidewalk"][0] 
	var distance_from_center = 7 # Ajuste para ficar entre a rua e as casas

	# Calçada Esquerda
	var side_l = get_instance(sidewalk_res)
	side_l.transform.origin = Vector3(-distance_from_center, y_level, along_z)
	side_l.scale = Vector3.ONE * 10
	if not side_l.get_parent(): environment.add_child(side_l)

	# Calçada Direita
	var side_r = get_instance(sidewalk_res)
	side_r.transform.origin = Vector3(distance_from_center, y_level, along_z)
	side_r.scale = Vector3.ONE * 10
	if not side_r.get_parent(): environment.add_child(side_r)
	
func spawn_houses(along_z: float):
	# Pegamos o asset de casa do seu Global.gd
	var house_list = Global.environment_resources["house"]
	var random_house_res = house_list.pick_random()
	var distance_from_street = 10.0 # Distância do centro da rua até a calçada das casas
	if along_z - player.global_position.z > 150: # Não spawna casas perto demais do prédio
		return

	# --- LADO ESQUERDO ---
	var house_left = random_house_res.instantiate()
	house_left.transform.origin = Vector3(-distance_from_street, ground_position, along_z)
	# Rotaciona 90 graus para a direita (ajuste o valor se a frente da sua casa for diferente)
	house_left.rotation_degrees.y = 90
	house_left.scale = Vector3.ONE * 2
	house_left.position.y = 0.5
	environment.add_child(house_left)

	# --- LADO DIREITO ---
	var house_right = random_house_res.instantiate()
	house_right.transform.origin = Vector3(distance_from_street, ground_position, along_z)
	# Rotaciona -90 graus para a esquerda
	house_right.rotation_degrees.y = -90 
	house_right.scale = Vector3.ONE * 2.5
	house_right.position.y = 0.5
	environment.add_child(house_right)

func spawn_ground_and_clouds(asset_category, along_z, y_pos):
	var random_index = randi() % asset_category.size()
	var instance = get_instance(asset_category[random_index])
	var side = left_side if randi() % 2 == 0 else right_side
	var distance_from_platform = randf_range(7.0,9.0)
	
	# Set the position
	instance.transform.origin = Vector3(
		side * distance_from_platform,  # X position next to platform
		y_pos,                     # Y position
		along_z                    # Z position along the path
	)
	# Add instance to the environment node
	if not instance.get_parent(): environment.add_child(instance)
	
func spawn_environmental_segment(along_z: float):
	# Spawn ground instances
	spawn_ground_and_clouds(
		Global.environment_resources["ground"],
		along_z,
		0.5
	)
	# Spawn houses on both sides of the path
	spawn_houses(along_z) 
	
# Spawn Collectibles
func get_random_collectible_type():
	var cumulative_chance = 0
	var chance_roll = randf()
	for key in Global.collectibles_resources.keys():
		cumulative_chance += Global.collectibles_resources[key]["spawn_chance"]
		if chance_roll <= cumulative_chance:
			return key
	return "coin" 

func spawn_collectible(platform_instance):
	var collectible_type = get_random_collectible_type()
	if collectible_type != "":
		var collectible_instance = Global.collectible_scene.instantiate()
		collectible_instance.set_collectible_type(collectible_type)
		# Starting spawn position above the platform
		if platform_instance == null or not is_instance_valid(platform_instance):
			return
		var spawn_position = platform_instance.global_transform.origin + Vector3(0, 2, 0)
		# Se for plataforma de chão, randomiza a faixa (Lane -2.5, 0 ou 2.5)
		if spawn_position.y < 3.0:
			var possible_x = [-2.5, 0, 2.5]
			spawn_position.x = possible_x[randi() % possible_x.size()]
			
		var min_distance = 3
		# Adjust the Y position if it's too close to an obstacle
		for obstacle in obstacles.get_children():
			var distance = spawn_position.distance_to(obstacle.global_transform.origin)
			if distance < min_distance:
				# If too close, move the collectible above the obstacle
				spawn_position.y = obstacle.global_transform.origin.y + min_distance
		collectible_instance.transform.origin = spawn_position
		collectibles.add_child(collectible_instance)
			
# Cleans up platforms & objects behind player
func cleanup_old_objects():
	# Remove platforms
	for platform in platforms.get_children():
		if platform.global_transform.origin.z < player.global_transform.origin.z - cleanup_object_count:
			return_to_pool(platform) # Remove the platform from the scene

	# Remove obstacles
	for obstacle in obstacles.get_children():
		if obstacle.global_transform.origin.z < player.global_transform.origin.z - cleanup_object_count:
			return_to_pool(obstacle) # Remove the obstacle from the scene

	# Remove environmentals
	for element in environment.get_children():
		if element.global_transform.origin.z < player.global_transform.origin.z - cleanup_object_count:
			return_to_pool(element)
			
	# Remove collectibles
	for collectible in collectibles.get_children():
		if collectible.global_transform.origin.z < player.global_transform.origin.z - cleanup_object_count:
			collectible.queue_free()

# Reset World State
func reset_world():
	reset_objects()
	initialize_game_elements()

func reset_objects():
	# Reset platform positions
	last_platform_position = Vector3.ZERO  
	last_air_platform_position = Vector3.ZERO 
	
	# Remove all platforms
	for platform in platforms.get_children():
		return_to_pool(platform)

	# Remove all obstacles
	for obstacle in obstacles.get_children():
		return_to_pool(obstacle)

	# Remove all environment objects
	for object in environment.get_children():
		return_to_pool(object)

	# Remove all collectibles
	for collectible in collectibles.get_children():
		collectible.queue_free()
