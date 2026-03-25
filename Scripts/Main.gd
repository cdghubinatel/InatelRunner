extends Node3D

@onready var level_music = $Sounds/LevelMusic
@onready var player = $Player

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_HIDDEN)
	level_music.play()
	player.reset_game_state()
func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
