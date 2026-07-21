extends CanvasLayer

# Rimon — Chapter One: The Razzia
# Procedural UI controller. Builds every screen in _ready() and exposes a
# small public API + signals so gameplay code never has to touch node internals.

signal start_pressed
signal reduced_motion_toggled(enabled)
signal door_tone_chosen(tone)
signal restart_pressed

const COLOR_PANEL_BG = Color(0.0784314, 0.0901961, 0.101961, 0.92) # #14171A @ 92%
const COLOR_DIM_BG = Color(0, 0, 0, 0.55)
const COLOR_AMBER = Color8(0xE9, 0xA8, 0x4C)
const COLOR_AMBER_LIGHT = Color8(0xF4, 0xC8, 0x78)
const COLOR_CREAM = Color8(0xC4, 0xC9, 0xCC)
const COLOR_CREAM_DIM = Color8(0x9A, 0xA0, 0xA3)

const PANEL_MAX_WIDTH = 620
const PANEL_PADDING_H = 48
const PANEL_PADDING_V = 40

const DOOR_TONE_CHOICES = [
	{"tone": "warm", "label": "Warm", "hint": "greet her like an old friend"},
	{"tone": "silent", "label": "Silent", "hint": "open it without a word"},
	{"tone": "indignant", "label": "Indignant", "hint": "meet suspicion with defiance"},
]

const EPILOGUE_PROSE = {
	"calm": "Mevrouw De Vos's voice carried down the stairwell, easy as Sunday — 'Just my sister's boy, officer, sleeping off a fever.' Boots turned. A door closed somewhere else. Daniel slept through all of it, his hand still sticky with honey. Someone had opened a door for Sara once, long before this street had a name for what was happening. Tonight, she only had to hold still and trust that the debt would be repaid.",
	"nearMiss": "Something crashed on the stairs — a pot, a curse, Mevrouw De Vos scolding a soldier for his clumsy boots in her narrow hall. Under the noise of it, Daniel's breath, and Sara's, and nothing else. When the street finally went quiet, Sara realized she had been holding the candle so tightly the wax had cooled between her fingers. Daniel was still warm. That was the only thing that had to be true.",
	"costly": "The knock came again, softer, and Mevrouw De Vos's voice moved away from their door instead of toward it — down the stairs, out into the snow, drawing the boots after her like a lantern draws moths. Sara heard her laugh at something, too loud, too far down the street. She did not hear her come back. In the room above the shuttered shop, a child slept on, warm, unknowing, alive. Someone had opened a door for Sara once. Tonight she could only wait behind the one Mevrouw De Vos had closed on her way out.",
}

const EPILOGUE_CLOSING_LINE = "A door had opened for her, once. That is how she knew to hold this one."
const EPILOGUE_CHAPTER_LINE = "Chapter Two · Antwerp · today"

# -- node refs, populated in _ready() --
var _start_overlay
var _reduced_motion_checkbox
var _hud_layer
var _reticle
var _interact_prompt
var _subtitle_label
var _subtitle_tween
var _subtitle_hide_timer
var _door_tone_overlay
var _door_tone_buttons = []
var _epilogue_overlay
var _epilogue_prose_label

var _suppress_reduced_motion_signal = false


func _ready():
	layer = 10
	_build_start_overlay()
	_build_hud()
	_build_subtitle()
	_build_door_tone_panel()
	_build_epilogue_panel()


# ---------------------------------------------------------------------------
# START OVERLAY
# ---------------------------------------------------------------------------

func _build_start_overlay():
	_start_overlay = ColorRect.new()
	_start_overlay.name = "StartOverlay"
	_start_overlay.color = Color(0.0392157, 0.0431373, 0.0509804, 0.86)
	_start_overlay.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_start_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_start_overlay)

	var center = CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_start_overlay.add_child(center)

	var vbox = _make_panel_box(center, COLOR_PANEL_BG)

	var title = Label.new()
	title.text = "RIMON"
	title.align = Label.ALIGN_CENTER
	title.add_font_override("font", _big_font(40))
	title.add_color_override("font_color", COLOR_AMBER_LIGHT)
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Chapter One · Antwerp, 1943"
	subtitle.align = Label.ALIGN_CENTER
	subtitle.add_font_override("font", _big_font(18))
	subtitle.add_color_override("font_color", COLOR_AMBER)
	vbox.add_child(subtitle)

	var spacer1 = Control.new()
	spacer1.rect_min_size = Vector2(0, 8)
	vbox.add_child(spacer1)

	var body = Label.new()
	body.text = "You are Sara. Above a shuttered shop, in one small room, you have kept your son safe for a year. Tonight the street is not quiet."
	body.autowrap = true
	body.align = Label.ALIGN_CENTER
	body.add_color_override("font_color", COLOR_CREAM)
	vbox.add_child(body)

	var legend = Label.new()
	legend.text = "WASD move · Mouse look · E interact · Shift hold to crouch"
	legend.autowrap = true
	legend.align = Label.ALIGN_CENTER
	legend.add_color_override("font_color", COLOR_CREAM_DIM)
	vbox.add_child(legend)

	var spacer2 = Control.new()
	spacer2.rect_min_size = Vector2(0, 8)
	vbox.add_child(spacer2)

	var enter_button = Button.new()
	enter_button.name = "EnterButton"
	enter_button.text = "Enter the Room"
	enter_button.rect_min_size = Vector2(0, 44)
	enter_button.connect("pressed", self, "_on_enter_pressed")
	vbox.add_child(enter_button)

	_reduced_motion_checkbox = CheckBox.new()
	_reduced_motion_checkbox.name = "ReducedMotionCheckBox"
	_reduced_motion_checkbox.text = "Reduce motion & screen effects"
	_reduced_motion_checkbox.align = Button.ALIGN_CENTER
	_reduced_motion_checkbox.connect("toggled", self, "_on_reduced_motion_toggled")
	vbox.add_child(_reduced_motion_checkbox)

	enter_button.grab_focus()


func _on_enter_pressed():
	emit_signal("start_pressed")


func _on_reduced_motion_toggled(enabled):
	if _suppress_reduced_motion_signal:
		return
	emit_signal("reduced_motion_toggled", enabled)


func set_reduced_motion_checked(enabled):
	_suppress_reduced_motion_signal = true
	_reduced_motion_checkbox.pressed = enabled
	_suppress_reduced_motion_signal = false


# ---------------------------------------------------------------------------
# IN-GAME HUD (reticle + interact prompt)
# ---------------------------------------------------------------------------

func _build_hud():
	_hud_layer = Control.new()
	_hud_layer.name = "HudLayer"
	_hud_layer.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud_layer.visible = false
	add_child(_hud_layer)

	_reticle = ColorRect.new()
	_reticle.name = "Reticle"
	_reticle.color = Color(1, 1, 1, 0.75)
	_reticle.rect_size = Vector2(4, 4)
	_reticle.anchor_left = 0.5
	_reticle.anchor_top = 0.5
	_reticle.anchor_right = 0.5
	_reticle.anchor_bottom = 0.5
	_reticle.margin_left = -2
	_reticle.margin_top = -2
	_reticle.margin_right = 2
	_reticle.margin_bottom = 2
	_hud_layer.add_child(_reticle)

	_interact_prompt = Label.new()
	_interact_prompt.name = "InteractPrompt"
	_interact_prompt.align = Label.ALIGN_CENTER
	_interact_prompt.add_color_override("font_color", COLOR_CREAM)
	_interact_prompt.add_color_override("font_color_shadow", Color(0, 0, 0, 0.8))
	_interact_prompt.add_constant_override("shadow_offset_x", 1)
	_interact_prompt.add_constant_override("shadow_offset_y", 1)
	_interact_prompt.anchor_left = 0.5
	_interact_prompt.anchor_right = 0.5
	_interact_prompt.anchor_top = 1.0
	_interact_prompt.anchor_bottom = 1.0
	_interact_prompt.margin_left = -260
	_interact_prompt.margin_right = 260
	_interact_prompt.margin_top = -96
	_interact_prompt.margin_bottom = -64
	_interact_prompt.visible = false
	_hud_layer.add_child(_interact_prompt)


func show_hud():
	_hud_layer.visible = true


func hide_hud():
	_hud_layer.visible = false


func hide_start_overlay():
	_start_overlay.visible = false


func show_start_overlay():
	_start_overlay.visible = true


func show_interact_prompt(label):
	_interact_prompt.text = label
	_interact_prompt.visible = true


func hide_interact_prompt():
	_interact_prompt.visible = false


# ---------------------------------------------------------------------------
# SUBTITLE
# ---------------------------------------------------------------------------

func _build_subtitle():
	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.align = Label.ALIGN_CENTER
	_subtitle_label.valign = Label.VALIGN_CENTER
	_subtitle_label.autowrap = true
	_subtitle_label.add_color_override("font_color", COLOR_CREAM)
	_subtitle_label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
	_subtitle_label.add_constant_override("shadow_offset_x", 1)
	_subtitle_label.add_constant_override("shadow_offset_y", 1)
	_subtitle_label.anchor_left = 0.5
	_subtitle_label.anchor_right = 0.5
	_subtitle_label.anchor_top = 0.0
	_subtitle_label.anchor_bottom = 0.0
	_subtitle_label.margin_left = -360
	_subtitle_label.margin_right = 360
	_subtitle_label.margin_top = 48
	_subtitle_label.margin_bottom = 108
	_subtitle_label.modulate = Color(1, 1, 1, 0)
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_label.visible = false
	add_child(_subtitle_label)

	_subtitle_tween = Tween.new()
	_subtitle_tween.name = "SubtitleTween"
	add_child(_subtitle_tween)

	_subtitle_hide_timer = Timer.new()
	_subtitle_hide_timer.name = "SubtitleHideTimer"
	_subtitle_hide_timer.one_shot = true
	_subtitle_hide_timer.connect("timeout", self, "hide_subtitle")
	add_child(_subtitle_hide_timer)


func show_subtitle(text, duration_sec = 4.5):
	_subtitle_hide_timer.stop()
	_subtitle_label.text = text
	_subtitle_label.visible = true
	_subtitle_tween.stop_all()
	_subtitle_tween.interpolate_property(_subtitle_label, "modulate:a", _subtitle_label.modulate.a, 1.0, 0.35,
		Tween.TRANS_SINE, Tween.EASE_OUT)
	_subtitle_tween.start()
	if duration_sec > 0:
		_subtitle_hide_timer.start(duration_sec)


func hide_subtitle():
	_subtitle_hide_timer.stop()
	_subtitle_tween.stop_all()
	_subtitle_tween.interpolate_property(_subtitle_label, "modulate:a", _subtitle_label.modulate.a, 0.0, 0.35,
		Tween.TRANS_SINE, Tween.EASE_IN)
	_subtitle_tween.start()
	_subtitle_tween.connect("tween_all_completed", self, "_on_subtitle_hidden", [], CONNECT_ONESHOT)


func _on_subtitle_hidden():
	_subtitle_label.visible = false


# ---------------------------------------------------------------------------
# DOOR-TONE CHOICE PANEL
# ---------------------------------------------------------------------------

func _build_door_tone_panel():
	_door_tone_overlay = ColorRect.new()
	_door_tone_overlay.name = "DoorToneOverlay"
	_door_tone_overlay.color = COLOR_DIM_BG
	_door_tone_overlay.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_door_tone_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_door_tone_overlay.visible = false
	add_child(_door_tone_overlay)

	var center = CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_door_tone_overlay.add_child(center)

	var vbox = _make_panel_box(center, COLOR_PANEL_BG)
	vbox.add_constant_override("separation", 14)

	var prompt = Label.new()
	prompt.text = "Boots stop outside. A knock. How do you open the door?"
	prompt.autowrap = true
	prompt.align = Label.ALIGN_CENTER
	prompt.add_color_override("font_color", COLOR_AMBER_LIGHT)
	vbox.add_child(prompt)

	var spacer = Control.new()
	spacer.rect_min_size = Vector2(0, 6)
	vbox.add_child(spacer)

	_door_tone_buttons = []
	for choice in DOOR_TONE_CHOICES:
		var btn = Button.new()
		btn.name = "DoorTone_%s" % choice["tone"]
		btn.text = choice["label"]
		btn.hint_tooltip = choice["hint"]
		btn.rect_min_size = Vector2(0, 44)
		btn.connect("pressed", self, "_on_door_tone_pressed", [choice["tone"]])
		vbox.add_child(btn)

		var hint_label = Label.new()
		hint_label.text = choice["hint"]
		hint_label.align = Label.ALIGN_CENTER
		hint_label.add_color_override("font_color", COLOR_CREAM_DIM)
		vbox.add_child(hint_label)

		_door_tone_buttons.append(btn)


func show_door_tone_choice():
	_door_tone_overlay.visible = true
	if _door_tone_buttons.size() > 0:
		_door_tone_buttons[0].grab_focus()


func hide_door_tone_choice():
	_door_tone_overlay.visible = false


func _on_door_tone_pressed(tone):
	emit_signal("door_tone_chosen", tone)
	hide_door_tone_choice()


# ---------------------------------------------------------------------------
# EPILOGUE CARD
# ---------------------------------------------------------------------------

func _build_epilogue_panel():
	_epilogue_overlay = ColorRect.new()
	_epilogue_overlay.name = "EpilogueOverlay"
	_epilogue_overlay.color = Color(0.0392157, 0.0431373, 0.0509804, 0.86)
	_epilogue_overlay.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_epilogue_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_epilogue_overlay.visible = false
	add_child(_epilogue_overlay)

	var center = CenterContainer.new()
	center.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	_epilogue_overlay.add_child(center)

	var vbox = _make_panel_box(center, COLOR_PANEL_BG)
	vbox.add_constant_override("separation", 18)

	_epilogue_prose_label = Label.new()
	_epilogue_prose_label.name = "EpilogueProseLabel"
	_epilogue_prose_label.autowrap = true
	_epilogue_prose_label.align = Label.ALIGN_LEFT
	_epilogue_prose_label.add_color_override("font_color", COLOR_CREAM)
	vbox.add_child(_epilogue_prose_label)

	var chapter_label = Label.new()
	chapter_label.text = EPILOGUE_CHAPTER_LINE
	chapter_label.align = Label.ALIGN_CENTER
	chapter_label.add_color_override("font_color", COLOR_AMBER)
	vbox.add_child(chapter_label)

	var restart_button = Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "Restart"
	restart_button.rect_min_size = Vector2(0, 44)
	restart_button.connect("pressed", self, "_on_restart_pressed")
	vbox.add_child(restart_button)


func show_epilogue(ending):
	var prose = EPILOGUE_PROSE.get(ending, "")
	_epilogue_prose_label.text = "%s %s" % [prose, EPILOGUE_CLOSING_LINE]
	_epilogue_overlay.visible = true


func hide_epilogue():
	_epilogue_overlay.visible = false


func _on_restart_pressed():
	emit_signal("restart_pressed")


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

func _make_panel_box(center_parent, panel_bg_color):
	# PanelContainer is a real Container: unlike a bare ColorRect, it grows
	# to fit its content automatically, so the translucent background always
	# matches the actual text height instead of collapsing to zero.
	var style = StyleBoxFlat.new()
	style.bg_color = panel_bg_color
	style.content_margin_left = PANEL_PADDING_H
	style.content_margin_right = PANEL_PADDING_H
	style.content_margin_top = PANEL_PADDING_V
	style.content_margin_bottom = PANEL_PADDING_V

	var panel = PanelContainer.new()
	panel.rect_min_size = Vector2(PANEL_MAX_WIDTH, 0)
	panel.add_stylebox_override("panel", style)
	center_parent.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 16)
	panel.add_child(vbox)
	return vbox


func _big_font(size):
	# Reuse the engine's built-in default font data at a larger point size,
	# so titles read clearly without bundling any custom font resource.
	var base_font = Control.new().get_font("font")
	if base_font is DynamicFont and base_font.font_data != null:
		var f = DynamicFont.new()
		f.size = size
		f.font_data = base_font.font_data
		return f
	return null
