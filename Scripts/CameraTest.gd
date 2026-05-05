extends Node

func _ready():
	print("--- TESTE DE CÂMERA EM GDSCRIPT ---")
	await get_tree().create_timer(2.0).timeout
	var count = CameraServer.get_feed_count()
	print("Câmeras detectadas (GDScript): ", count)
	for i in range(count):
		var feed = CameraServer.get_feed(i)
		print("- Feed ", i, ": ", feed.get_name())
