extends Node

var ranking_list = []

const SAVE_PATH = "user://ranking.cfg"
var save_data = ConfigFile.new()

# Platform Resources
var platform_resources = [
	preload("res://Resources/Platforms/road.tscn")
]

# Air Platform Resources
var air_platforms_resources = [
	preload("res://Resources/Platforms/air_platform.tscn")
]
var air_platform_spawn_chance = 0.3

# Obstacle Resources
var obstacle_resources = [
	preload("res://Resources/Obstacles/crate.tscn"),
	preload("res://Resources/Obstacles/tree_stump.tscn"),
	preload("res://Resources/Obstacles/construction_barrier.tscn"),
	preload("res://Resources/Obstacles/construction_cone.tscn"),
	preload("res://Resources/Obstacles/construction_light.tscn"),
	preload("res://Resources/Obstacles/car_hatchback.tscn"),
	preload("res://Resources/Obstacles/car_police.tscn"),
	preload("res://Resources/Obstacles/car_sedan.tscn"),
	preload("res://Resources/Obstacles/car_stationwagon.tscn"),
	preload("res://Resources/Obstacles/car_taxi.tscn"),
	preload("res://Resources/Obstacles/trafficlight_a.tscn"),
	preload("res://Resources/Obstacles/firehydrant.tscn")
]
var obstacle_scene = preload("res://Scenes/Obstacles.tscn")
var obstacle_spawn_chance = 0.25

# Environmental Resources
var environment_resources = {
	"clouds": [
		preload("res://Resources/Environmentals/cloud_1.tscn"),
		preload("res://Resources/Environmentals/cloud_2.tscn"),
		preload("res://Resources/Environmentals/cloud_3.tscn")
	],
	"ground": [
		preload("res://Resources/Environmentals/streetlight.tscn")
	],
	"sidewalk": [
		preload("res://Resources/Environmentals/road_side.tscn")
	],
	"house": [
		preload("res://Resources/Environmentals/Houses/building_a.tscn"),
		preload("res://Resources/Environmentals/Houses/building_b.tscn"),
		preload("res://Resources/Environmentals/Houses/building_c.tscn"),
		preload("res://Resources/Environmentals/Houses/building_d.tscn"),
		preload("res://Resources/Environmentals/Houses/building_f.tscn"),
		preload("res://Resources/Environmentals/Houses/building_g.tscn"),
		preload("res://Resources/Environmentals/Houses/building_h.tscn")
	]
}

# Collectible resources
var collectibles_resources = {
	"coin": {
		"scene": preload("res://Resources/Collectibles/coin.tscn"),
		"effect": "increase_score",
		"spawn_chance": 0.07
	},
	"gem": {
		"scene": preload("res://Resources/Collectibles/gem.tscn"),
		"effect": "boost_jump",
		"spawn_chance": 0.04
	},
	"flag": {
		"scene": preload("res://Resources/Collectibles/flag.tscn"),
		"effect": "decrease_time",
		"spawn_chance": 0.02
	}
}
var collectible_scene = preload("res://Scenes/Collectibles.tscn")

# Advanced Obstacles
var advanced_obstacle_resources = [
	preload("res://Resources/AdvancedObstacles/bee.tscn"),
	preload("res://Resources/AdvancedObstacles/rotating_log.tscn"),
	preload("res://Resources/Obstacles/renzo.tscn")
]
var advanced_obstacle_spawn_chance = 0

# Game variables
var high_score = 0
var score = 0
var level_time = 20
var jump_boost_count = 0
var lives = 3
var level = 1
var game_started = false

# Signals
signal score_updated
signal level_time_updated
signal jump_boost_updated
signal lives_updated
signal level_updated
signal update_results

# Progression Variables
var obstacle_spawn_increase_per_level = 0.03
var score_requirement = 0 
var min_score_requirement = 10
var max_score_requirement = 50 
var final_score_requirement = 0
var score_requirement_reached = false
var time_reduction_bonus = 10
var default_level_time = 20
var speed_multiplier = 1.0

func _ready():
	load_ranking()

# =========================
# NEW GAME (nova run)
# =========================
func new_game():
	level = 1
	score = 0
	lives = 3
	jump_boost_count = 0
	obstacle_spawn_chance = 0.25
	advanced_obstacle_spawn_chance = 0
	score_requirement_reached = false
	speed_multiplier = 1.0
	
	setup_level_state()

	score_updated.emit()
	lives_updated.emit()
	jump_boost_updated.emit()
	level_updated.emit()

# =========================
# NEXT LEVEL (mantém score)
# =========================
func level_up():
	level += 1
	obstacle_spawn_chance = min(obstacle_spawn_chance + obstacle_spawn_increase_per_level, 0.6)
	advanced_obstacle_spawn_chance = min(advanced_obstacle_spawn_chance + 0.02, 0.3)
	speed_multiplier = min(speed_multiplier + 0.05, 2.0) # Aumenta 5%, limite máximo de 2.0x

	if score >= score_requirement:
		score_requirement_reached = true

	setup_level_state()
	level_updated.emit()

# =========================
# RESET RUN após derrota
# =========================
func retry_level():
	new_game()

# =========================
# CONFIGURA ESTADO DA FASE
# =========================
func setup_level_state():
	if score_requirement_reached:
		level_time = default_level_time + (level - 1) * 10 - time_reduction_bonus
		score_requirement_reached = false
	else:
		level_time = default_level_time + (level - 1) * 10

	score_requirement = randi_range(min_score_requirement, max_score_requirement)
	jump_boost_count = 0

	level_time_updated.emit()
	jump_boost_updated.emit()

# =========================
# RANKING
# =========================
func add_to_ranking(player_name: String, player_score: int):
	var new_entry = {"name": player_name, "score": player_score}
	ranking_list.append(new_entry)

	ranking_list.sort_custom(func(a, b): return a["score"] > b["score"])

	if ranking_list.size() > 5:
		ranking_list.resize(5)

	save_ranking()

func save_ranking():
	save_data.clear()
	save_data.set_value("ranking", "list", ranking_list)

	var error = save_data.save(SAVE_PATH)
	if error == OK:
		print("Ranking salvo com sucesso.")
	else:
		print("Erro ao salvar ranking: ", error)

func load_ranking():
	var error = save_data.load(SAVE_PATH)
	if error == OK:
		ranking_list = save_data.get_value("ranking", "list", [])
	else:
		ranking_list = []
