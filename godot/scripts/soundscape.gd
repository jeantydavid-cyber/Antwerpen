extends Node

# Procedural audio for the room scene -- no audio files, everything is
# synthesized sample-by-sample into AudioStreamGenerator buffers. This is a
# Godot 3.5 port of the browser prototype at src/audio/soundscape.ts; the
# synthesis approach differs (Web Audio node graph -> hand-rolled DSP loop)
# but the layering, thresholds and envelope shapes are kept close to that
# reference so the two versions read the same emotionally.
#
# Attach to a plain Node anywhere in the scene tree (this script adds its own
# Spatial anchors and AudioStreamPlayer(3D) children in init()). Call init()
# once before any other method. _process() is ENGINE-DRIVEN: once this node
# is inside the tree, Godot calls _process() automatically every frame and
# that drives both buffer pushing and all time-based envelopes/scheduling.
# (It is also safe to call _process(delta) directly yourself -- e.g. for
# headless testing -- since it does not depend on any engine-only state.)
#
# All sound is atmospheric/mechanical texture (drone, hiss, taps, footsteps,
# a knock, a muffling filter sweep) -- never anything resembling a gunshot,
# scream or impact, per the scene's content guidelines.

# --- Anchor positions (matches WINDOW_ANCHOR_POS / DOOR_ANCHOR_POS in the
# browser reference). Anchors are added as direct children of this node, so
# these are effectively global offsets when this node sits at the room's
# origin. ---
const WINDOW_ANCHOR_POS := Vector3(0.9, 1.5, -3.2)
const DOOR_ANCHOR_POS := Vector3(-1.5, 1.2, 3.2)

const MIX_RATE := 44100.0
const SAMPLE_DT := 1.0 / MIX_RATE
const BUFFER_LENGTH := 0.12

const TWO_PI := PI * 2.0

# A cutoff this high is effectively "no filtering" for a one-pole lowpass at
# our mix rate -- used as the shock filter's resting/open state.
const SHOCK_FILTER_OPEN_HZ := 20000.0

const WIND_HISS_BASE_GAIN := 0.035
const CANDLE_HISS_GAIN := 0.018

const TICK_INTERVAL := 1.0
const TICK_JITTER := 0.07
const TICK_PEAK_GAIN := 0.05

const THREAT_SMOOTH_TIME := 0.7 # seconds, exponential smoothing constant
const BREATHING_SMOOTH_TIME := 0.9

const ENGINE_SWELL_THRESHOLD := 0.3
const DOG_BARK_THRESHOLD := 0.55
const BOOTS_BURST_THRESHOLD := 0.8
const PULSE_LOOP_THRESHOLD := 0.4
const THRESHOLD_REARM_MARGIN := 0.12

const COUGH_MIN_INTERVAL := 4.5
const COUGH_MAX_INTERVAL := 11.0

# --- Nodes built in init() ---
var window_anchor: Spatial
var door_anchor: Spatial
var ambient_player: AudioStreamPlayer
var window_player: AudioStreamPlayer3D
var door_player: AudioStreamPlayer3D
var ambient_playback: AudioStreamGeneratorPlayback
var window_playback: AudioStreamGeneratorPlayback
var door_playback: AudioStreamGeneratorPlayback

var initialized := false

# Running "audio clock" in seconds, advanced by SAMPLE_DT per generated
# sample. All scheduling (one-shot cue start times, fade/filter ramps) is
# expressed against this clock, mirroring how the browser reference schedules
# against AudioContext.currentTime.
var clock_time := 0.0

# --- Continuous bed state: persistent oscillator phases / filter memory ---
var wind_lp_y := 0.0
var wind_gust_phase := 0.0

var candle_fast_y := 0.0
var candle_slow_y := 0.0

var breathing_lp_y := 0.0
var breathing_gain_current := 0.0
var breathing_gain_target := 0.0

var engine_phase_a := 0.0
var engine_phase_b := 0.0
var engine_lp_y := 0.0
var engine_filter_cutoff_current := 130.0
var engine_filter_cutoff_target := 130.0
var engine_door_gain_current := 0.0
var engine_door_gain_target := 0.0
var engine_window_gain_current := 0.0
var engine_window_gain_target := 0.0

var tension_lp_y := 0.0
var tension_filter_cutoff_current := 260.0
var tension_filter_cutoff_target := 260.0
var tension_gain_current := 0.0
var tension_gain_target := 0.0

# Per-bus one-pole "shock" filter memory (the muffling sweep in resolve_costly).
var ambient_shock_y := 0.0
var window_shock_y := 0.0
var door_shock_y := 0.0
var shock_segments := [] # Array of {t0,t1,v0,v1} ramp dictionaries, in order.

# Threat-bed fade multipliers, applied to the door/window threat layers only
# (never the baseline hiss/tick/candle). Each is a single {t0,t1,v0,v1} ramp.
var door_bus_fade := {"t0": 0.0, "t1": 0.0, "v0": 1.0, "v1": 1.0}
var window_bus_fade := {"t0": 0.0, "t1": 0.0, "v0": 1.0, "v1": 1.0}

# Master mute ramp.
var master_mute_ramp := {"t0": 0.0, "t1": 0.0, "v0": 1.0, "v1": 1.0}

# Threshold-armed one-shot cues (re-arm once level drops back below
# threshold - margin, same hysteresis as the browser reference).
var current_threat_level := 0.0
var engine_swell_armed := true
var dog_bark_armed := true
var boots_burst_armed := true

var pulse_loop_active := false
var next_pulse_time := 0.0
var next_tick_time := 0.0

var cough_intensity := 0.0
var cough_loop_active := false
var next_cough_time := 0.0

# Active one-shot events: Array of Dictionaries, see _push_event().
var active_events := []


func init() -> void:
	if initialized:
		return
	randomize()
	_build_nodes()
	_reset_state()
	ambient_player.play()
	window_player.play()
	door_player.play()
	ambient_playback = ambient_player.get_stream_playback()
	window_playback = window_player.get_stream_playback()
	door_playback = door_player.get_stream_playback()
	initialized = true


func _build_nodes() -> void:
	window_anchor = Spatial.new()
	window_anchor.name = "WindowAnchor"
	window_anchor.translation = WINDOW_ANCHOR_POS
	add_child(window_anchor)

	door_anchor = Spatial.new()
	door_anchor.name = "DoorAnchor"
	door_anchor.translation = DOOR_ANCHOR_POS
	add_child(door_anchor)

	ambient_player = AudioStreamPlayer.new()
	ambient_player.name = "AmbientPlayer"
	ambient_player.stream = _make_generator()
	add_child(ambient_player)

	window_player = AudioStreamPlayer3D.new()
	window_player.name = "WindowPlayer"
	window_player.stream = _make_generator()
	window_player.unit_db = 0.0
	window_player.max_distance = 24.0
	window_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	window_anchor.add_child(window_player)

	door_player = AudioStreamPlayer3D.new()
	door_player.name = "DoorPlayer"
	door_player.stream = _make_generator()
	door_player.unit_db = 0.0
	door_player.max_distance = 24.0
	door_player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	door_anchor.add_child(door_player)


func _make_generator() -> AudioStreamGenerator:
	var g := AudioStreamGenerator.new()
	g.mix_rate = MIX_RATE
	g.buffer_length = BUFFER_LENGTH
	return g


func _reset_state() -> void:
	clock_time = 0.0
	shock_segments = [{"t0": 0.0, "t1": 999999.0, "v0": SHOCK_FILTER_OPEN_HZ, "v1": SHOCK_FILTER_OPEN_HZ}]
	door_bus_fade = {"t0": 0.0, "t1": 0.0, "v0": 1.0, "v1": 1.0}
	window_bus_fade = {"t0": 0.0, "t1": 0.0, "v0": 1.0, "v1": 1.0}
	master_mute_ramp = {"t0": 0.0, "t1": 0.0, "v0": 1.0, "v1": 1.0}
	next_tick_time = 0.0
	next_pulse_time = 0.0
	next_cough_time = 0.0
	active_events = []


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func set_threat_proximity(level_in: float) -> void:
	var level: float = clamp(level_in, 0.0, 1.0)
	current_threat_level = level
	if not initialized:
		return

	engine_door_gain_target = lerp(0.015, 0.24, level)
	engine_window_gain_target = lerp(0.008, 0.05, level)
	engine_filter_cutoff_target = lerp(130.0, 900.0, level)
	tension_gain_target = lerp(0.0, 0.15, level)
	tension_filter_cutoff_target = lerp(260.0, 1500.0, level)

	if level >= ENGINE_SWELL_THRESHOLD and engine_swell_armed:
		engine_swell_armed = false
		_fire_engine_swell()
	elif level < ENGINE_SWELL_THRESHOLD - THRESHOLD_REARM_MARGIN:
		engine_swell_armed = true

	if level >= DOG_BARK_THRESHOLD and dog_bark_armed:
		dog_bark_armed = false
		_fire_dog_bark()
	elif level < DOG_BARK_THRESHOLD - THRESHOLD_REARM_MARGIN:
		dog_bark_armed = true

	if level >= BOOTS_BURST_THRESHOLD and boots_burst_armed:
		boots_burst_armed = false
		_fire_boots_burst()
	elif level < BOOTS_BURST_THRESHOLD - THRESHOLD_REARM_MARGIN:
		boots_burst_armed = true

	if level >= PULSE_LOOP_THRESHOLD:
		_start_pulse_loop()
	elif level < PULSE_LOOP_THRESHOLD - THRESHOLD_REARM_MARGIN:
		_stop_pulse_loop()


func play_beat_cue(beat: String) -> void:
	if not initialized:
		return
	if beat == "warning":
		_fire_warning_taps()
	elif beat == "knock":
		_fire_knock()
	# All other beat values: no-op.


func set_daniel_cough(intensity_in: float) -> void:
	if not initialized:
		return
	var intensity: float = clamp(intensity_in, 0.0, 1.0)
	cough_intensity = intensity
	breathing_gain_target = 0.0
	if intensity > 0.0:
		breathing_gain_target = lerp(0.006, 0.026, intensity)

	if intensity > 0.0 and not cough_loop_active:
		cough_loop_active = true
		next_cough_time = clock_time + lerp(COUGH_MAX_INTERVAL, COUGH_MIN_INTERVAL, intensity) + randf() * 2.0
	elif intensity <= 0.0 and cough_loop_active:
		cough_loop_active = false


func resolve_calm() -> void:
	if not initialized:
		return
	_stop_pulse_loop()
	var now := clock_time
	var cur_door: float = _ramp_value(door_bus_fade, now)
	var cur_win: float = _ramp_value(window_bus_fade, now)
	door_bus_fade = {"t0": now, "t1": now + 3.4, "v0": cur_door, "v1": 0.0}
	window_bus_fade = {"t0": now, "t1": now + 3.4, "v0": cur_win, "v1": 0.0}


func resolve_near_miss() -> void:
	if not initialized:
		return
	_fire_clatter()
	_fire_murmur()
	_stop_pulse_loop()
	var now := clock_time
	var hold := 0.55
	var cur_door: float = _ramp_value(door_bus_fade, now)
	var cur_win: float = _ramp_value(window_bus_fade, now)
	door_bus_fade = {"t0": now + hold, "t1": now + hold + 2.4, "v0": cur_door, "v1": 0.0}
	window_bus_fade = {"t0": now + hold, "t1": now + hold + 2.4, "v0": cur_win, "v1": 0.0}


func resolve_costly() -> void:
	if not initialized:
		return
	_stop_pulse_loop()
	var now := clock_time
	_fire_tense_swell()

	var shock_start := now + 0.95
	var close_dur := 0.55
	var hold_dur := 3.6
	var recover_dur := 2.8
	var cur_cutoff: float = _eval_segments(shock_segments, now)

	shock_segments = [
		{"t0": now, "t1": shock_start, "v0": cur_cutoff, "v1": cur_cutoff},
		{"t0": shock_start, "t1": shock_start + close_dur, "v0": cur_cutoff, "v1": 420.0},
		{"t0": shock_start + close_dur, "t1": shock_start + close_dur + hold_dur, "v0": 420.0, "v1": 420.0},
		{"t0": shock_start + close_dur + hold_dur, "t1": shock_start + close_dur + hold_dur + recover_dur, "v0": 420.0, "v1": SHOCK_FILTER_OPEN_HZ},
	]

	# A faint tinnitus-like ring that sits "through" the muffling -- it
	# deliberately bypasses the shock filter (see ambient mix below) since it
	# represents the ear ringing, not the room.
	var ring_start := shock_start + close_dur * 0.4
	var ring_dur := close_dur + hold_dur + recover_dur * 0.4
	_fire_ring_tone(ring_start, ring_dur)

	var cur_door: float = _ramp_value(door_bus_fade, now)
	var cur_win: float = _ramp_value(window_bus_fade, now)
	door_bus_fade = {"t0": shock_start + close_dur, "t1": shock_start + close_dur + 1.6, "v0": cur_door, "v1": 0.0}
	window_bus_fade = {"t0": shock_start + close_dur, "t1": shock_start + close_dur + 1.6, "v0": cur_win, "v1": 0.0}


func set_muted(muted: bool) -> void:
	if not initialized:
		return
	var target := 1.0
	if muted:
		target = 0.0
	var now := clock_time
	var cur: float = _ramp_value(master_mute_ramp, now)
	master_mute_ramp = {"t0": now, "t1": now + 0.15, "v0": cur, "v1": target}


func _process(delta: float) -> void:
	if not initialized:
		return
	_update_smoothed_targets(delta)

	var avail_a: int = ambient_playback.get_frames_available()
	var avail_w: int = window_playback.get_frames_available()
	var avail_d: int = door_playback.get_frames_available()
	var n: int = min(avail_a, min(avail_w, avail_d))

	var out := [0.0, 0.0, 0.0]
	for i in range(n):
		_generate_all_samples(out)
		ambient_playback.push_frame(Vector2(out[0], out[0]))
		window_playback.push_frame(Vector2(out[1], out[1]))
		door_playback.push_frame(Vector2(out[2], out[2]))
		clock_time += SAMPLE_DT

	_prune_finished_events()


# ---------------------------------------------------------------------------
# Continuous smoothing
# ---------------------------------------------------------------------------

func _update_smoothed_targets(delta: float) -> void:
	var k: float = 1.0 - exp(-delta / THREAT_SMOOTH_TIME)
	engine_door_gain_current += (engine_door_gain_target - engine_door_gain_current) * k
	engine_window_gain_current += (engine_window_gain_target - engine_window_gain_current) * k
	engine_filter_cutoff_current += (engine_filter_cutoff_target - engine_filter_cutoff_current) * k
	tension_gain_current += (tension_gain_target - tension_gain_current) * k
	tension_filter_cutoff_current += (tension_filter_cutoff_target - tension_filter_cutoff_current) * k

	var kb: float = 1.0 - exp(-delta / BREATHING_SMOOTH_TIME)
	breathing_gain_current += (breathing_gain_target - breathing_gain_current) * kb


# ---------------------------------------------------------------------------
# Per-sample synthesis
# ---------------------------------------------------------------------------

func _one_pole_lp(x: float, y_prev: float, cutoff: float) -> float:
	var w: float = TWO_PI * max(cutoff, 1.0) / MIX_RATE
	var alpha: float = clamp(w / (w + 1.0), 0.0, 1.0)
	return y_prev + alpha * (x - y_prev)


func _saw(phase: float) -> float:
	return 2.0 * phase - 1.0


func _env_ad(lt: float, attack: float, decay_tau: float, peak: float) -> float:
	if lt < attack:
		return peak * (lt / max(attack, 0.0001))
	return peak * exp(-(lt - attack) / max(decay_tau, 0.0001))


func _ramp_value(r: Dictionary, t: float) -> float:
	var t0: float = r["t0"]
	var t1: float = r["t1"]
	var v0: float = r["v0"]
	var v1: float = r["v1"]
	if t <= t0:
		return v0
	if t >= t1:
		return v1
	var frac: float = (t - t0) / max(t1 - t0, 0.0001)
	return lerp(v0, v1, frac)


func _eval_segments(segs: Array, t: float) -> float:
	if segs.empty():
		return SHOCK_FILTER_OPEN_HZ
	if t <= segs[0]["t0"]:
		return segs[0]["v0"]
	for seg in segs:
		if t <= seg["t1"]:
			return _ramp_value(seg, t)
	return segs[segs.size() - 1]["v1"]


func _generate_all_samples(out: Array) -> void:
	var t := clock_time

	# --- Baseline: wind/snow hiss at the window (gently gusting cutoff) ---
	wind_gust_phase = fmod(wind_gust_phase + 0.045 * SAMPLE_DT, 1.0)
	var wind_cutoff: float = 1100.0 + 260.0 * sin(wind_gust_phase * TWO_PI)
	var wind_noise: float = randf() * 2.0 - 1.0
	wind_lp_y = _one_pole_lp(wind_noise, wind_lp_y, wind_cutoff)
	var wind_sample: float = wind_lp_y * WIND_HISS_BASE_GAIN

	# --- Baseline: candle hiss (band-ish noise via difference of two LPs) ---
	var candle_noise: float = randf() * 2.0 - 1.0
	candle_fast_y = _one_pole_lp(candle_noise, candle_fast_y, 4500.0)
	candle_slow_y = _one_pole_lp(candle_noise, candle_slow_y, 2000.0)
	var candle_sample: float = (candle_fast_y - candle_slow_y) * CANDLE_HISS_GAIN * 3.0

	# --- Daniel's cough/breathing bed ---
	var breathing_noise: float = randf() * 2.0 - 1.0
	breathing_lp_y = _one_pole_lp(breathing_noise, breathing_lp_y, 420.0)
	var breathing_sample: float = breathing_lp_y * breathing_gain_current

	# --- Distant engine drone (shared oscillator, tapped by both buses) ---
	engine_phase_a = fmod(engine_phase_a + 52.0 * SAMPLE_DT, 1.0)
	engine_phase_b = fmod(engine_phase_b + 57.0 * SAMPLE_DT, 1.0)
	var engine_raw: float = (_saw(engine_phase_a) + _saw(engine_phase_b)) * 0.5
	engine_lp_y = _one_pole_lp(engine_raw, engine_lp_y, engine_filter_cutoff_current)
	var engine_sample: float = engine_lp_y

	# --- Tension texture noise (door only) ---
	var tension_noise: float = randf() * 2.0 - 1.0
	tension_lp_y = _one_pole_lp(tension_noise, tension_lp_y, tension_filter_cutoff_current)
	var tension_sample: float = tension_lp_y * tension_gain_current

	# --- One-shot / scheduled events ---
	var ambient_events_sum := 0.0
	var door_events_sum := 0.0
	var ring_sum := 0.0
	for ev in active_events:
		var contrib: float = _sample_event(ev, t)
		var bus: String = ev["bus"]
		if bus == "ambient":
			ambient_events_sum += contrib
		elif bus == "door":
			door_events_sum += contrib
		elif bus == "ring":
			ring_sum += contrib

	_maybe_schedule_tick(t)
	_maybe_schedule_pulse(t)
	_maybe_schedule_cough(t)

	var door_fade_now: float = _ramp_value(door_bus_fade, t)
	var window_fade_now: float = _ramp_value(window_bus_fade, t)
	var master_now: float = _ramp_value(master_mute_ramp, t)
	var shock_cutoff_now: float = _eval_segments(shock_segments, t)

	var ambient_raw: float = candle_sample + breathing_sample + ambient_events_sum
	ambient_shock_y = _one_pole_lp(ambient_raw, ambient_shock_y, shock_cutoff_now)
	var ambient_out: float = clamp((ambient_shock_y + ring_sum) * master_now, -1.0, 1.0)

	var window_raw: float = wind_sample + engine_sample * engine_window_gain_current * window_fade_now
	window_shock_y = _one_pole_lp(window_raw, window_shock_y, shock_cutoff_now)
	var window_out: float = clamp(window_shock_y * master_now, -1.0, 1.0)

	var door_raw: float = (engine_sample * engine_door_gain_current + tension_sample + door_events_sum) * door_fade_now
	door_shock_y = _one_pole_lp(door_raw, door_shock_y, shock_cutoff_now)
	var door_out: float = clamp(door_shock_y * master_now, -1.0, 1.0)

	out[0] = ambient_out
	out[1] = window_out
	out[2] = door_out


func _sample_event(ev: Dictionary, t: float) -> float:
	if t < ev["start"]:
		return 0.0
	var lt: float = t - ev["start"]
	if lt > ev["dur"]:
		ev["finished"] = true
		return 0.0

	var state: Dictionary = ev["state"]
	var kind: String = ev["kind"]

	match kind:
		"tick":
			var env: float = _env_ad(lt, 0.002, 0.05 / 6.0, ev["peak"])
			state["phase"] = fmod(state["phase"] + 1700.0 * SAMPLE_DT, 1.0)
			return sin(state["phase"] * TWO_PI) * env

		"footstep":
			var env: float = _env_ad(lt, 0.012, 0.138 / 6.0, ev["peak"])
			var noise: float = randf() * 2.0 - 1.0
			state["y"] = _one_pole_lp(noise, state["y"], 190.0)
			return state["y"] * env

		"warning_tap":
			var env: float = _env_ad(lt, 0.008, 0.092 / 6.0, ev["peak"])
			var noise: float = randf() * 2.0 - 1.0
			state["y"] = _one_pole_lp(noise, state["y"], 260.0)
			return state["y"] * env

		"cough_burst":
			var env: float = _env_ad(lt, 0.035, 0.225 / 6.0, ev["peak"])
			var noise: float = randf() * 2.0 - 1.0
			state["y_fast"] = _one_pole_lp(noise, state["y_fast"], 900.0)
			state["y_slow"] = _one_pole_lp(noise, state["y_slow"], 280.0)
			return (state["y_fast"] - state["y_slow"]) * 2.0 * env

		"dog_bark":
			var env: float = _env_ad(lt, 0.02, 0.22 / 6.0, ev["peak"])
			var freq: float
			if lt < 0.13:
				freq = 620.0 * pow(340.0 / 620.0, lt / 0.13)
			else:
				freq = 340.0
			state["phase"] = fmod(state["phase"] + freq * SAMPLE_DT, 1.0)
			return _saw(state["phase"]) * env

		"engine_swell":
			var dur: float = ev["dur"]
			var half: float = dur * 0.5
			var freq: float
			if lt < half:
				freq = lerp(48.0, 64.0, lt / half)
			else:
				freq = lerp(64.0, 44.0, (lt - half) / max(dur - half, 0.0001))
			state["phase"] = fmod(state["phase"] + freq * SAMPLE_DT, 1.0)
			var raw: float = _saw(state["phase"])
			var seg1: float = dur * 0.55
			var cutoff: float
			if lt < seg1:
				cutoff = lerp(180.0, 620.0, lt / seg1)
			else:
				cutoff = lerp(620.0, 150.0, (lt - seg1) / max(dur - seg1, 0.0001))
			state["y"] = _one_pole_lp(raw, state["y"], cutoff)
			var env: float
			if lt < half:
				env = lerp(0.0, 0.22, lt / half)
			else:
				var tau: float = (dur * 0.5) / 6.0
				env = 0.22 * exp(-(lt - half) / tau)
			return state["y"] * env

		"knock_rap":
			var body_env: float = _env_ad(lt, 0.006, 0.174 / 6.0, 0.34)
			state["phase"] = fmod(state["phase"] + 130.0 * SAMPLE_DT, 1.0)
			var body: float = sin(state["phase"] * TWO_PI) * body_env
			var noise_env: float = _env_ad(lt, 0.003, 0.047 / 6.0, 0.18)
			var noise: float = randf() * 2.0 - 1.0
			state["y_fast"] = _one_pole_lp(noise, state["y_fast"], 2200.0)
			state["y_slow"] = _one_pole_lp(noise, state["y_slow"], 700.0)
			var noise_out: float = (state["y_fast"] - state["y_slow"]) * 2.0 * noise_env
			return body + noise_out

		"clatter_hit":
			var env: float = _env_ad(lt, ev["attack"], ev["decay_tau"], ev["peak"])
			var noise: float = randf() * 2.0 - 1.0
			var freq: float = ev["freq"]
			state["y_fast"] = _one_pole_lp(noise, state["y_fast"], freq * 1.6)
			state["y_slow"] = _one_pole_lp(noise, state["y_slow"], freq * 0.6)
			return (state["y_fast"] - state["y_slow"]) * 2.0 * env

		"murmur":
			var dur: float = ev["dur"]
			var tremolo: float = 1.0 + 0.4 * sin(t * TWO_PI * 5.5)
			var env: float
			if lt < 0.15:
				env = lerp(0.0, 0.05, lt / 0.15)
			else:
				env = lerp(0.05, 0.0, (lt - 0.15) / max(dur - 0.15, 0.0001))
			env = max(env, 0.0) * tremolo
			state["pa"] = fmod(state["pa"] + 130.0 * SAMPLE_DT, 1.0)
			state["pb"] = fmod(state["pb"] + 155.0 * SAMPLE_DT, 1.0)
			var raw: float = (_saw(state["pa"]) + _saw(state["pb"])) * 0.5
			state["y_fast"] = _one_pole_lp(raw, state["y_fast"], 550.0)
			state["y_slow"] = _one_pole_lp(raw, state["y_slow"], 230.0)
			return (state["y_fast"] - state["y_slow"]) * 2.0 * env

		"tense_swell":
			var dur: float = ev["dur"]
			var attack: float = dur * 0.85
			var env: float
			if lt < attack:
				env = lerp(0.0, 0.26, lt / attack)
			else:
				env = lerp(0.26, 0.0, (lt - attack) / max(dur - attack, 0.0001))
			var frac: float = clamp(lt / dur, 0.0, 1.0)
			var fast_cut: float = lerp(500.0, 2200.0, frac)
			var slow_cut: float = lerp(150.0, 800.0, frac)
			var noise: float = randf() * 2.0 - 1.0
			state["y_fast"] = _one_pole_lp(noise, state["y_fast"], fast_cut)
			state["y_slow"] = _one_pole_lp(noise, state["y_slow"], slow_cut)
			return (state["y_fast"] - state["y_slow"]) * 2.0 * env

		"ring_tone":
			var dur: float = ev["dur"]
			var attack := 0.5
			var release_start: float = dur - 1.1
			var env: float
			if lt < attack:
				env = lerp(0.0, 0.022, lt / attack)
			elif lt < release_start:
				env = 0.022
			else:
				env = lerp(0.022, 0.0, (lt - release_start) / max(dur - release_start, 0.0001))
			state["pa"] = fmod(state["pa"] + 2650.0 * SAMPLE_DT, 1.0)
			state["pb"] = fmod(state["pb"] + 2668.0 * SAMPLE_DT, 1.0)
			return (sin(state["pa"] * TWO_PI) + sin(state["pb"] * TWO_PI)) * env * 0.5

		_:
			return 0.0


func _prune_finished_events() -> void:
	var kept := []
	for ev in active_events:
		if not bool(ev["finished"]) and clock_time <= float(ev["start"]) + float(ev["dur"]) + 0.02:
			kept.append(ev)
	active_events = kept


# ---------------------------------------------------------------------------
# Event scheduling / firing helpers
# ---------------------------------------------------------------------------

func _push_event(kind: String, bus: String, start: float, dur: float, peak: float = 0.0, extra: Dictionary = {}) -> void:
	var ev := {
		"kind": kind,
		"bus": bus,
		"start": start,
		"dur": dur,
		"peak": peak,
		"state": {"phase": 0.0, "y": 0.0, "y_fast": 0.0, "y_slow": 0.0, "pa": 0.0, "pb": 0.0},
		"finished": false,
	}
	for k in extra.keys():
		ev[k] = extra[k]
	active_events.append(ev)


func _maybe_schedule_tick(t: float) -> void:
	if t < next_tick_time:
		return
	_push_event("tick", "ambient", t, 0.06, TICK_PEAK_GAIN)
	var jitter: float = (randf() * 2.0 - 1.0) * TICK_JITTER
	next_tick_time = t + TICK_INTERVAL + jitter


func _maybe_schedule_pulse(t: float) -> void:
	if not pulse_loop_active or t < next_pulse_time:
		return
	var urgency: float = smoothstep(PULSE_LOOP_THRESHOLD, 1.0, current_threat_level)
	_push_footstep(t, lerp(0.06, 0.15, urgency))
	var interval: float = lerp(1.05, 0.48, urgency)
	next_pulse_time = t + interval


func _maybe_schedule_cough(t: float) -> void:
	if not cough_loop_active or t < next_cough_time:
		return
	_fire_cough_burst(t)
	var wait: float = lerp(COUGH_MAX_INTERVAL, COUGH_MIN_INTERVAL, cough_intensity) + randf() * 2.0
	next_cough_time = t + wait


func _push_footstep(start: float, peak: float) -> void:
	_push_event("footstep", "door", start, 0.17, peak)


func _start_pulse_loop() -> void:
	if pulse_loop_active:
		return
	pulse_loop_active = true
	next_pulse_time = clock_time


func _stop_pulse_loop() -> void:
	pulse_loop_active = false


func _fire_engine_swell() -> void:
	_push_event("engine_swell", "door", clock_time, 1.95)


func _fire_dog_bark() -> void:
	_push_event("dog_bark", "door", clock_time, 0.24, 0.16)


func _fire_boots_burst() -> void:
	for i in range(5):
		_push_footstep(clock_time + i * 0.4, lerp(0.09, 0.18, float(i) / 4.0))


func _fire_knock() -> void:
	_stop_pulse_loop()
	_push_footstep(clock_time, 0.2)
	var knock_start: float = clock_time + 0.35
	for i in range(3):
		_push_event("knock_rap", "door", knock_start + i * 0.46, 0.2)


func _fire_warning_taps() -> void:
	for i in range(3):
		var jitter: float = randf() * 0.03
		_push_event("warning_tap", "ambient", clock_time + i * 0.32 + jitter, 0.12, 0.075)


func _fire_clatter() -> void:
	var hits := [[0.0, 620.0, 0.24], [0.08, 480.0, 0.16], [0.15, 720.0, 0.1], [0.24, 390.0, 0.06]]
	for h in hits:
		var extra := {"freq": h[1], "attack": 0.004, "decay_tau": (0.09 - 0.004) / 6.0}
		_push_event("clatter_hit", "door", clock_time + h[0], 0.1, h[2], extra)


func _fire_murmur() -> void:
	_push_event("murmur", "door", clock_time + 0.3, 1.1)


func _fire_tense_swell() -> void:
	_push_event("tense_swell", "door", clock_time, 0.95)


func _fire_ring_tone(start: float, dur: float) -> void:
	_push_event("ring_tone", "ring", start, dur)


func _fire_cough_burst(t: float) -> void:
	var peak: float = lerp(0.05, 0.12, cough_intensity)
	_push_event("cough_burst", "ambient", t, 0.28, peak)
	if cough_intensity > 0.4:
		_push_event("cough_burst", "ambient", t + 0.24, 0.28, peak * 0.4)
