extends Spatial

# The candle is the light and the tension meter.
# Attach to a Spatial node in the room scene. A separate integration script
# drives tension via set_tension_level() and the two resolve_* envelopes at
# the end of the scene.

# --- Palette (coal-smoke chiaroscuro) ---
const CANDLE_AMBER = Color(0.914, 0.659, 0.298)   # #E9A84C
const CANDLE_HIGHLIGHT = Color(0.957, 0.784, 0.471) # #F4C878
const COAL_BLUE_GREY = Color(0.180, 0.227, 0.271)  # #2E3A45
const SLATE = Color(0.333, 0.388, 0.431)           # #55636E
const DIRTY_SNOW = Color(0.769, 0.788, 0.800)      # #C4C9CC
const COAL_BLACK = Color(0.078, 0.090, 0.102)      # #14171A

# --- Candle base tuning ---
const CANDLE_BASE_ENERGY = 1.6
const CANDLE_MIN_ENERGY = 0.06 # hard floor: the flame never fully dies
const CANDLE_RANGE = 10.0
const CANDLE_ATTENUATION = 1.6

# --- Flicker tuning (scales with tension 0..1) ---
const FLICKER_AMP_MIN = 0.05      # calm amplitude at tension 0
const FLICKER_AMP_MAX = 0.55      # violent amplitude at tension 1
const FLICKER_SPEED_MIN = 0.6     # slow drift at tension 0
const FLICKER_SPEED_MAX = 3.2     # fast agitation at tension 1
const JITTER_POS_MAX = 0.035      # meters, small position jitter at tension 1

# --- Moonlight fill tuning ---
const MOON_ENERGY = 0.35
const MOON_RANGE = 7.0
const MOON_POSITION = Vector3(0.9, 2.2, -3.3)
const MOON_AIM_TARGET = Vector3(0.0, 1.0, 0.0)

# --- Resolve envelope durations ---
const STEADY_SETTLE_SECONDS = 2.5
const GUTTER_DIP_SECONDS = 1.25
const GUTTER_RECOVER_SECONDS = 3.5
const STEADY_TENSION = 0.05 # the calm tension level both endings settle toward

var candle_light: OmniLight
var moon_light: OmniLight
var world_environment: WorldEnvironment
var environment: Environment

var candle_anchor: Spatial = null
var candle_base_position := Vector3.ZERO

var tension := 0.0

var noise_a := OpenSimplexNoise.new()
var noise_b := OpenSimplexNoise.new()
var noise_c := OpenSimplexNoise.new()
var time_accum := 0.0

# Resolution state machine: "" | "steady" | "gutter"
var resolve_mode := ""
var resolve_elapsed := 0.0
# Snapshot of tension/amplitude scale used while a resolve envelope overrides
# the normal tension-driven flicker.
var resolve_from_amp_scale := 1.0
var resolve_from_speed_scale := 1.0


func _ready():
	_setup_noise()
	_build_environment()
	_build_candle_light()
	_build_moon_light()


func _setup_noise():
	noise_a.seed = 1
	noise_a.octaves = 2
	noise_a.period = 1.0
	noise_a.persistence = 0.5

	noise_b.seed = 7
	noise_b.octaves = 1
	noise_b.period = 1.0
	noise_b.persistence = 0.5

	noise_c.seed = 42
	noise_c.octaves = 1
	noise_c.period = 1.0
	noise_c.persistence = 0.5


func _build_environment():
	environment = Environment.new()

	environment.background_mode = Environment.BG_COLOR
	environment.background_color = COAL_BLACK

	# Cheap always-on fill so nothing is ever pure black, even outside the
	# candle's falloff. Kept very dim and cool -- moonlight, not daylight.
	environment.ambient_light_color = COAL_BLUE_GREY
	environment.ambient_light_energy = 0.18

	# Subtle atmospheric haze -- just enough to add depth to the beam.
	environment.fog_enabled = true
	environment.fog_color = COAL_BLUE_GREY
	environment.fog_depth_enabled = true
	environment.fog_depth_begin = 1.0
	environment.fog_depth_end = 14.0
	environment.fog_depth_curve = 1.0

	# Warm bloom around the candle's bright core.
	environment.glow_enabled = true
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.25
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	environment.glow_hdr_threshold = 0.85

	# Restrained desaturated grade. Godot 3.5's Environment has no built-in
	# vignette, so per the task instructions that is intentionally skipped
	# rather than hand-rolling a shader pass.
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.0
	environment.adjustment_contrast = 1.05
	environment.adjustment_saturation = 0.82

	# Godot 3.5 exposes TONE_MAPPER_FILMIC (no ACES option on this build's
	# enum), which is a reasonable soft-rolloff choice for a bright candle
	# core against a near-black room.
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC

	world_environment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)


func _build_candle_light():
	candle_light = OmniLight.new()
	candle_light.light_color = CANDLE_AMBER
	candle_light.light_energy = CANDLE_BASE_ENERGY
	candle_light.omni_range = CANDLE_RANGE
	candle_light.omni_attenuation = CANDLE_ATTENUATION
	candle_light.shadow_enabled = true
	add_child(candle_light)


func _build_moon_light():
	moon_light = OmniLight.new()
	moon_light.light_color = DIRTY_SNOW.linear_interpolate(SLATE, 0.4)
	moon_light.light_energy = MOON_ENERGY
	moon_light.omni_range = MOON_RANGE
	moon_light.omni_attenuation = 1.2
	moon_light.shadow_enabled = false
	moon_light.translation = MOON_POSITION
	add_child(moon_light)
	# OmniLight radiates in all directions -- there's no "aim" to set, its
	# position near the window is what reads as a directional cold accent.
	# MOON_AIM_TARGET is kept only as documentation of intent / for a future
	# SpotLight swap.


func attach_to_candle(anchor: Spatial):
	candle_anchor = anchor
	if candle_anchor != null:
		candle_base_position = candle_anchor.global_transform.origin
		candle_light.global_transform.origin = candle_base_position


func set_tension_level(level: float):
	tension = clamp(level, 0.0, 1.0)


func resolve_steady():
	resolve_mode = "steady"
	resolve_elapsed = 0.0
	resolve_from_amp_scale = _current_amp_scale()
	resolve_from_speed_scale = _current_speed_scale()


func resolve_gutter_and_recover():
	resolve_mode = "gutter"
	resolve_elapsed = 0.0
	resolve_from_amp_scale = _current_amp_scale()
	resolve_from_speed_scale = _current_speed_scale()


func _current_amp_scale() -> float:
	return lerp(FLICKER_AMP_MIN, FLICKER_AMP_MAX, tension)


func _current_speed_scale() -> float:
	return lerp(FLICKER_SPEED_MIN, FLICKER_SPEED_MAX, tension)


func _process(delta):
	time_accum += delta

	if candle_anchor != null:
		candle_base_position = candle_anchor.global_transform.origin

	var amp_scale: float
	var speed_scale: float
	var energy_mult := 1.0

	match resolve_mode:
		"steady":
			resolve_elapsed += delta
			var t = clamp(resolve_elapsed / STEADY_SETTLE_SECONDS, 0.0, 1.0)
			var target_amp = lerp(FLICKER_AMP_MIN, FLICKER_AMP_MAX, STEADY_TENSION)
			var target_speed = lerp(FLICKER_SPEED_MIN, FLICKER_SPEED_MAX, STEADY_TENSION)
			amp_scale = lerp(resolve_from_amp_scale, target_amp, t)
			speed_scale = lerp(resolve_from_speed_scale, target_speed, t)
		"gutter":
			resolve_elapsed += delta
			var dip_t = clamp(resolve_elapsed / GUTTER_DIP_SECONDS, 0.0, 1.0)
			if resolve_elapsed <= GUTTER_DIP_SECONDS:
				# Dip toward near-zero, but the hard floor (CANDLE_MIN_ENERGY)
				# is enforced later regardless of energy_mult.
				energy_mult = lerp(1.0, 0.02, _ease_in_out(dip_t))
				amp_scale = lerp(resolve_from_amp_scale, FLICKER_AMP_MIN * 0.5, _ease_in_out(dip_t))
				speed_scale = lerp(resolve_from_speed_scale, FLICKER_SPEED_MIN * 0.5, _ease_in_out(dip_t))
			else:
				var rec_t = clamp((resolve_elapsed - GUTTER_DIP_SECONDS) / GUTTER_RECOVER_SECONDS, 0.0, 1.0)
				var target_amp = lerp(FLICKER_AMP_MIN, FLICKER_AMP_MAX, STEADY_TENSION)
				var target_speed = lerp(FLICKER_SPEED_MIN, FLICKER_SPEED_MAX, STEADY_TENSION)
				energy_mult = lerp(0.02, 1.0, _ease_in_out(rec_t))
				amp_scale = lerp(FLICKER_AMP_MIN * 0.5, target_amp, _ease_in_out(rec_t))
				speed_scale = lerp(FLICKER_SPEED_MIN * 0.5, target_speed, _ease_in_out(rec_t))
				if rec_t >= 1.0:
					resolve_mode = "steady"
					resolve_elapsed = 0.0
					resolve_from_amp_scale = target_amp
					resolve_from_speed_scale = target_speed
		_:
			amp_scale = _current_amp_scale()
			speed_scale = _current_speed_scale()

	_apply_flicker(delta, amp_scale, speed_scale, energy_mult)


func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _apply_flicker(delta: float, amp_scale: float, speed_scale: float, energy_mult: float):
	# Combine a few noise signals at different frequencies/phases so the
	# flame reads as organic rather than a metronome. speed_scale stretches
	# the sample coordinate (faster tension = faster wander through noise
	# space); amp_scale controls how much the combined signal perturbs the
	# base energy.
	var x = time_accum * speed_scale
	var n1 = noise_a.get_noise_1d(x * 1.0)
	var n2 = noise_b.get_noise_1d(x * 2.3 + 100.0)
	var n3 = noise_c.get_noise_1d(x * 4.7 + 250.0)
	var combined = n1 * 0.55 + n2 * 0.30 + n3 * 0.15 # roughly in [-1, 1]

	var energy = CANDLE_BASE_ENERGY * energy_mult * (1.0 + combined * amp_scale)
	energy = max(energy, CANDLE_MIN_ENERGY)
	candle_light.light_energy = energy

	# Subtle warm/hot color shift: brighter instants lean toward the pale
	# candle highlight, dimmer instants sit in the deeper amber.
	var color_t = clamp((combined * amp_scale) * 0.5 + 0.5, 0.0, 1.0)
	candle_light.light_color = CANDLE_AMBER.linear_interpolate(CANDLE_HIGHLIGHT, color_t)

	# Small position jitter, scaled the same way, so the flame visibly
	# trembles under high tension instead of just pulsing in place.
	var jitter_amount = JITTER_POS_MAX * (amp_scale / FLICKER_AMP_MAX)
	var jx = noise_a.get_noise_1d(x * 3.1 + 500.0) * jitter_amount
	var jy = noise_b.get_noise_1d(x * 3.7 + 700.0) * jitter_amount * 0.6
	var jz = noise_c.get_noise_1d(x * 2.9 + 900.0) * jitter_amount
	candle_light.global_transform.origin = candle_base_position + Vector3(jx, jy, jz)
