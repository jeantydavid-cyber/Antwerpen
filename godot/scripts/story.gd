extends Node

signal beat_changed(new_beat, prev_beat)
signal ending_reached(ending)

const QUIET_EXPLORE_TARGET = 2
const QUIET_FALLBACK_SECONDS = 25.0
const WARNING_HOLD_SECONDS = 5.0
const COUGH_FALLBACK_SECONDS = 20.0
const EVIDENCE_GRACE_SECONDS = 14.0
const RESOLUTION_HOLD_SECONDS = 7.0

const HIDING_SPOT_DELTAS = {
	"hidingWardrobe": {"exposure": 0.12, "distress": -0.10},
	"hidingFloorboards": {"exposure": 0.02, "distress": 0.08},
	"hidingCellarHatch": {"exposure": -0.10, "distress": 0.15},
}

const COUGH_DELTAS = {
	"giveHoney": {"exposure": 0.0, "distress": -0.20},
	"coverMouth": {"exposure": -0.08, "distress": 0.18},
	"wrapDeeper": {"exposure": -0.03, "distress": 0.06},
}

const EVIDENCE_HIDE_EXPOSURE = -0.05

const DOOR_TONE_DELTAS = {
	"warm": -0.15,
	"silent": 0.03,
	"indignant": 0.15,
}

const CALM_THRESHOLD = -0.12
const COSTLY_THRESHOLD = 0.22

var room_ref = null

var beat = "quiet"
var elapsed_in_beat = 0.0
var started = false
var ending = null

var exposure = 0.0
var child_distress = 0.0
var hiding_spot = null
var cough_action = null
var hidden_evidence = []
var door_tone = null

var explored_ids = {}


func reset():
	room_ref = null
	beat = "quiet"
	elapsed_in_beat = 0.0
	started = false
	ending = null
	exposure = 0.0
	child_distress = 0.0
	hiding_spot = null
	cough_action = null
	hidden_evidence = []
	door_tone = null
	explored_ids = {}


func get_beat():
	return beat


func get_exposure_state():
	return {
		"exposure": exposure,
		"childDistress": child_distress,
		"hidingSpot": hiding_spot,
		"coughAction": cough_action,
		"hiddenEvidence": hidden_evidence,
		"doorTone": door_tone,
	}


func start_story():
	if started:
		return
	started = true
	_go_to("quiet")


func _process(delta):
	if not started:
		return
	elapsed_in_beat += delta

	match beat:
		"quiet":
			if explored_ids.size() >= QUIET_EXPLORE_TARGET or elapsed_in_beat >= QUIET_FALLBACK_SECONDS:
				_go_to("warning")
		"warning":
			if elapsed_in_beat >= WARNING_HOLD_SECONDS:
				_go_to("hideChild")
		"cough":
			if elapsed_in_beat >= COUGH_FALLBACK_SECONDS:
				_resolve_cough_action("wrapDeeper")
		"roomEvidence":
			if elapsed_in_beat >= EVIDENCE_GRACE_SECONDS:
				_go_to("knock")
		"resolution":
			if elapsed_in_beat >= RESOLUTION_HOLD_SECONDS:
				_go_to("epilogue")


func _go_to(next_beat):
	var prev = beat
	beat = next_beat
	elapsed_in_beat = 0.0
	emit_signal("beat_changed", next_beat, prev)


func handle_interact(id):
	if not started:
		return
	match beat:
		"quiet":
			_handle_quiet_interact(id)
		"hideChild":
			_handle_hide_child_interact(id)
		"cough":
			_handle_cough_interact(id)
		"roomEvidence":
			_handle_room_evidence_interact(id)
		_:
			pass


func _handle_quiet_interact(id):
	if id == "candle" or id == "honeyJar" or id == "daniel":
		explored_ids[id] = true


func _handle_hide_child_interact(id):
	if not HIDING_SPOT_DELTAS.has(id):
		return
	var delta = HIDING_SPOT_DELTAS[id]
	hiding_spot = id
	exposure += delta["exposure"]
	child_distress = max(0.0, child_distress + delta["distress"])
	if room_ref != null:
		room_ref.set_daniel_visible(true, id)
	_go_to("cough")


func _handle_cough_interact(id):
	var action = null
	if id == "honeyJar":
		action = "giveHoney"
	elif id == "daniel":
		action = "coverMouth"
	elif hiding_spot != null and id == hiding_spot:
		action = "wrapDeeper"
	if action == null:
		return
	_resolve_cough_action(action)


func _resolve_cough_action(action):
	var delta = COUGH_DELTAS[action]
	cough_action = action
	exposure += delta["exposure"]
	child_distress = clamp(child_distress + delta["distress"], 0.0, 1.0)
	_go_to("roomEvidence")


func _handle_room_evidence_interact(id):
	if id != "tableBowl" and id != "wallDrawing" and id != "doorframeMezuzah":
		return
	var already_hidden = hidden_evidence.has(id)
	if already_hidden:
		hidden_evidence.erase(id)
		exposure -= EVIDENCE_HIDE_EXPOSURE
		if room_ref != null:
			room_ref.set_evidence_hidden(id, false)
	else:
		hidden_evidence.append(id)
		exposure += EVIDENCE_HIDE_EXPOSURE
		if room_ref != null:
			room_ref.set_evidence_hidden(id, true)


func choose_door_tone(tone):
	if beat != "knock" or door_tone != null:
		return
	door_tone = tone
	exposure += DOOR_TONE_DELTAS[tone]
	_go_to("resolution")
	_resolve_ending()


func _resolve_ending():
	var effective = exposure + child_distress * 0.15
	if effective <= CALM_THRESHOLD:
		ending = "calm"
	elif effective <= COSTLY_THRESHOLD:
		ending = "nearMiss"
	else:
		ending = "costly"
	emit_signal("ending_reached", ending)
