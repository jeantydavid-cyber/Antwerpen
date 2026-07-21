extends Area

const Defs = preload("res://scripts/interactable_defs.gd")

var interactable_id = ""


func get_prompt_label(beat, state):
	return Defs.get_prompt_label(interactable_id, beat, state)


func is_available(beat, state):
	return Defs.is_available(interactable_id, beat, state)
