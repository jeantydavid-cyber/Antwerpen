extends Node

const RoomBuilderScript = preload("res://scripts/room_builder.gd")
const LightingScript = preload("res://scripts/lighting.gd")
const PlayerControllerScript = preload("res://scripts/player_controller.gd")
const SoundscapeScript = preload("res://scripts/soundscape.gd")
const UIControllerScript = preload("res://scripts/ui_controller.gd")

const THREAT_BY_BEAT = {
	"quiet": 0.0,
	"warning": 0.15,
	"hideChild": 0.3,
	"cough": 0.45,
	"roomEvidence": 0.65,
	"knock": 0.9,
	"resolution": 0.9,
	"epilogue": 0.0,
}

const TENSION_BY_BEAT = {
	"quiet": 0.05,
	"warning": 0.3,
	"hideChild": 0.45,
	"cough": 0.55,
	"roomEvidence": 0.7,
	"knock": 0.95,
	"resolution": 0.95,
	"epilogue": 0.1,
}

const WARNING_LINE = "Three taps through the floor. Mevrouw De Vos's voice, barely there: \"Sara. They're on the street. Hide him.\""

var room
var lighting
var player
var soundscape
var ui

var started = false
var latest_ending = null
var cough_t = 0.0
var choice_active = false


func _ready():
	room = Spatial.new()
	room.name = "Room"
	room.set_script(RoomBuilderScript)
	add_child(room)

	lighting = Spatial.new()
	lighting.name = "Lighting"
	lighting.set_script(LightingScript)
	add_child(lighting)
	lighting.attach_to_candle(room.get_candle_anchor())

	player = KinematicBody.new()
	player.name = "Player"
	player.set_script(PlayerControllerScript)
	add_child(player)
	player.translation = room.player_spawn_position
	player.rotation_degrees = Vector3(0, room.player_spawn_yaw_degrees, 0)

	soundscape = Node.new()
	soundscape.name = "Soundscape"
	soundscape.set_script(SoundscapeScript)
	add_child(soundscape)

	ui = CanvasLayer.new()
	ui.name = "UI"
	ui.set_script(UIControllerScript)
	add_child(ui)

	Story.room_ref = room

	ui.connect("start_pressed", self, "_on_start_pressed")
	ui.connect("reduced_motion_toggled", self, "_on_reduced_motion_toggled")
	ui.connect("door_tone_chosen", self, "_on_door_tone_chosen")
	ui.connect("restart_pressed", self, "_on_restart_pressed")
	player.connect("interact_pressed", self, "_on_interact_pressed")
	Story.connect("beat_changed", self, "_on_beat_changed")
	Story.connect("ending_reached", self, "_on_ending_reached")


func _on_start_pressed():
	if started:
		player.lock()
		return
	started = true
	player.lock()
	ui.hide_start_overlay()
	ui.show_hud()
	soundscape.init()
	Story.start_story()


func _on_reduced_motion_toggled(enabled):
	player.set_reduced_motion(enabled)


func _on_door_tone_chosen(tone):
	Story.choose_door_tone(tone)
	choice_active = false
	player.lock()


func _on_restart_pressed():
	Story.reset()
	get_tree().reload_current_scene()


func _on_interact_pressed():
	if not started:
		return
	var beat = Story.get_beat()
	if beat == "warning" or beat == "resolution" or beat == "epilogue":
		return

	var target = player.get_interaction_target(room.get_interactables())
	if target == null:
		return
	var state = Story.get_exposure_state()
	if not target.is_available(beat, state):
		return

	if target.interactable_id == "door" and beat == "knock" and state["doorTone"] == null:
		choice_active = true
		player.unlock()
		ui.show_door_tone_choice()
		return

	Story.handle_interact(target.interactable_id)


func _on_beat_changed(new_beat, _prev_beat):
	soundscape.set_threat_proximity(THREAT_BY_BEAT[new_beat])
	soundscape.play_beat_cue(new_beat)
	lighting.set_tension_level(TENSION_BY_BEAT[new_beat])

	if new_beat == "warning":
		ui.show_subtitle(WARNING_LINE)
	elif new_beat == "epilogue" and latest_ending != null:
		ui.show_epilogue(latest_ending)
		player.unlock()


func _on_ending_reached(ending):
	latest_ending = ending
	if ending == "calm":
		lighting.resolve_steady()
		soundscape.resolve_calm()
	elif ending == "nearMiss":
		lighting.resolve_steady()
		soundscape.resolve_near_miss()
	else:
		lighting.resolve_gutter_and_recover()
		soundscape.resolve_costly()


func _process(delta):
	if not started:
		return

	var beat = Story.get_beat()

	if beat == "cough":
		cough_t = min(1.0, cough_t + delta / 2.0)
	elif cough_t > 0.0:
		cough_t = max(0.0, cough_t - delta * 2.0)
	soundscape.set_daniel_cough(cough_t)

	var terminal_beat = beat == "warning" or beat == "resolution" or beat == "epilogue"
	if player.is_locked() and not terminal_beat:
		var target = player.get_interaction_target(room.get_interactables())
		var state = Story.get_exposure_state()
		if target != null and target.is_available(beat, state):
			ui.show_interact_prompt(target.get_prompt_label(beat, state))
		else:
			ui.hide_interact_prompt()
	else:
		ui.hide_interact_prompt()
