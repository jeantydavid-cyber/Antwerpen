extends Node


func _ready():
	print("MAIN_BOOT_OK story_autoload=", Story)
	Story.start_story()
	print("story beat after start=", Story.get_beat())
	get_tree().quit()
