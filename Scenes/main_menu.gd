extends Control

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _on_button_pressed():
	# Verifique se o caminho da cena está correto (pode ser Main.tscn ou World.tscn)
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
func _input(event):
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
