extends Node3D

@onready var player = get_node("../Player") # Caminho se ele estiver na Main

@export var distance_from_player: float = 80.0
@export var ground_level: float = 1.5

func _process(_delta):
	if player:
		global_position.z = player.global_position.z + distance_from_player 
		global_position.y = ground_level
		scale = Vector3.ONE * 11
