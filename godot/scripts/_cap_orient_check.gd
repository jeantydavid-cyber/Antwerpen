extends Node

func _ready():
	var mi = MeshInstance.new()
	var cap = CapsuleMesh.new()
	cap.radius = 0.2
	cap.mid_height = 1.0
	mi.mesh = cap
	add_child(mi)

	var cam = Camera.new()
	cam.translation = Vector3(0, 0, 4)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	cam.current = true
	add_child(cam)

	var light = DirectionalLight.new()
	light.rotation_degrees = Vector3(-45, -45, 0)
	add_child(light)

	for i in range(4):
		yield(get_tree(), "idle_frame")

	var img = get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png("/tmp/claude-0/-home-user-Antwerpen/bd053375-f271-57ba-9eda-6d0845382d7c/scratchpad/cap_check.png")
	print("OK")
	get_tree().quit()
