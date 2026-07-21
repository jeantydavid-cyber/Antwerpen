extends CanvasLayer

# Rimon — Chapter One: The Razzia
# Procedural UI controller. Builds every screen in _ready() and exposes a
# small public API + signals so gameplay code never has to touch node internals.
#
# Visual language: a quiet, candle-lit museum-placard aesthetic — coal-black
# translucent panels, a hairline warm-amber border, restrained corner
# rounding, and a soft drop shadow for depth. No bright/saturated color,
# no bubbly "app" chrome.

signal start_pressed
signal reduced_motion_toggled(enabled)
signal door_tone_chosen(tone)
signal restart_pressed

const COLOR_PANEL_BG = Color(0.0784314, 0.0901961, 0.101961, 0.92) # #14171A @ 92%
const COLOR_DIM_BG = Color(0, 0, 0, 0.55)
const COLOR_AMBER = Color8(0xE9, 0xA8, 0x4C)
const COLOR_AMBER_LIGHT = Color8(0xF4, 0xC8, 0x78)
const COLOR_AMBER_DIM = Color8(0xB9, 0x93, 0x5E)
const COLOR_CREAM = Color8(0xC4, 0xC9, 0xCC)
const COLOR_CREAM_DIM = Color8(0x9A, 0xA0, 0xA3)
const COLOR_WARM_WHITE = Color8(0xEE, 0xE6, 0xD6)

# -- panel chrome --
const COLOR_BORDER = Color(0.913725, 0.658824, 0.298039, 0.4)   # amber @ ~40%
const COLOR_SHADOW = Color(0, 0, 0, 0.45)
const PANEL_BORDER_WIDTH = 1
const PANEL_CORNER_RADIUS = 3

# -- button chrome --
const COLOR_BTN_BG = Color(0.0666667, 0.0745098, 0.0823529, 0.88)
const COLOR_BTN_BG_HOVER = Color(0.113725, 0.0901961, 0.0627451, 0.92)
const COLOR_BTN_BG_PRESSED = Color(0.0470588, 0.0509804, 0.0588235, 0.94)
const COLOR_BTN_BORDER = Color(0.913725, 0.658824, 0.298039, 0.5)
const COLOR_BTN_BORDER_HOVER = Color8(0xE9, 0xA8, 0x4C)
const COLOR_BTN_BORDER_PRESSED = Color8(0xF4, 0xC8, 0x78)
const COLOR_FOCUS_GLOW = Color8(0xF4, 0xC8, 0x78, 235)
const BUTTON_BORDER_WIDTH = 1
const BUTTON_CORNER_RADIUS = 2

const PANEL_MAX_WIDTH = 620
const PANEL_PADDING_H = 48
const PANEL_PADDING_V = 40

const FONT_REGULAR_PATH = "res://assets/fonts/LiberationSerif-Regular.ttf"
const FONT_BOLD_PATH = "res://assets/fonts/LiberationSerif-Bold.ttf"
const FONT_ITALIC_PATH = "res://assets/fonts/LiberationSerif-Italic.ttf"

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

# -- cached font data, loaded once in _ready() --
var _font_data_regular
var _font_data_bold
var _font_data_italic


func _ready():
	layer = 10
	_load_font_data()
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
	title.add_font_override("font", _make_font(_font_data_bold, 46, 6, 4))
	title.add_color_override("font_color", COLOR_AMBER_LIGHT)
	title.add_color_override("font_color_shadow", Color(0, 0, 0, 0.5))
	title.add_constant_override("shadow_offset_x", 0)
	title.add_constant_override("shadow_offset_y", 2)
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "Chapter One · Antwerp, 1943"
	subtitle.align = Label.ALIGN_CENTER
	subtitle.add_font_override("font", _make_font(_font_data_italic, 18, 1, 1))
	subtitle.add_color_override("font_color", COLOR_AMBER_DIM)
	vbox.add_child(subtitle)

	var spacer1 = Control.new()
	spacer1.rect_min_size = Vector2(0, 10)
	vbox.add_child(spacer1)

	var body = Label.new()
	body.text = "You are Sara. Above a shuttered shop, in one small room, you have kept your son safe for a year. Tonight the street is not quiet."
	body.autowrap = true
	body.align = Label.ALIGN_CENTER
	body.add_font_override("font", _make_font(_font_data_regular, 16))
	body.add_color_override("font_color", COLOR_CREAM)
	vbox.add_child(body)

	var legend = Label.new()
	legend.text = "WASD move · Mouse look · E interact · Shift hold to crouch"
	legend.autowrap = true
	legend.align = Label.ALIGN_CENTER
	legend.add_font_override("font", _make_font(_font_data_italic, 14))
	legend.add_color_override("font_color", COLOR_CREAM_DIM)
	vbox.add_child(legend)

	var spacer2 = Control.new()
	spacer2.rect_min_size = Vector2(0, 10)
	vbox.add_child(spacer2)

	var enter_button = Button.new()
	enter_button.name = "EnterButton"
	enter_button.text = "Enter the Room"
	enter_button.rect_min_size = Vector2(0, 44)
	enter_button.connect("pressed", self, "_on_enter_pressed")
	_style_button(enter_button, _make_font(_font_data_regular, 17, 1, 1))
	vbox.add_child(enter_button)

	_reduced_motion_checkbox = CheckBox.new()
	_reduced_motion_checkbox.name = "ReducedMotionCheckBox"
	_reduced_motion_checkbox.text = "Reduce motion & screen effects"
	_reduced_motion_checkbox.align = Button.ALIGN_CENTER
	_reduced_motion_checkbox.connect("toggled", self, "_on_reduced_motion_toggled")
	_style_checkbox(_reduced_motion_checkbox, _make_font(_font_data_regular, 14))
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

	# Reticle: a soft dark halo behind a small warm-white dot, so it stays
	# legible against both bright candlelight and deep shadow.
	var reticle_halo = ColorRect.new()
	reticle_halo.name = "ReticleHalo"
	reticle_halo.color = Color(0, 0, 0, 0.35)
	reticle_halo.rect_size = Vector2(8, 8)
	reticle_halo.anchor_left = 0.5
	reticle_halo.anchor_top = 0.5
	reticle_halo.anchor_right = 0.5
	reticle_halo.anchor_bottom = 0.5
	reticle_halo.margin_left = -4
	reticle_halo.margin_top = -4
	reticle_halo.margin_right = 4
	reticle_halo.margin_bottom = 4
	_hud_layer.add_child(reticle_halo)

	_reticle = ColorRect.new()
	_reticle.name = "Reticle"
	_reticle.color = Color(0.933333, 0.905882, 0.839216, 0.85) # warm-white
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
	_interact_prompt.add_font_override("font", _make_font(_font_data_regular, 16))
	_interact_prompt.add_color_override("font_color", COLOR_WARM_WHITE)
	_interact_prompt.add_color_override("font_color_shadow", Color(0, 0, 0, 0.85))
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
	_subtitle_label.add_font_override("font", _make_font(_font_data_regular, 17))
	_subtitle_label.add_color_override("font_color", COLOR_WARM_WHITE)
	_subtitle_label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.9))
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
	prompt.add_font_override("font", _make_font(_font_data_bold, 19))
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
		_style_button(btn, _make_font(_font_data_regular, 17, 1, 1))
		vbox.add_child(btn)

		var hint_label = Label.new()
		hint_label.text = choice["hint"]
		hint_label.align = Label.ALIGN_CENTER
		hint_label.add_font_override("font", _make_font(_font_data_italic, 13))
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
	_epilogue_prose_label.add_font_override("font", _make_font(_font_data_regular, 17))
	_epilogue_prose_label.add_color_override("font_color", COLOR_CREAM)
	vbox.add_child(_epilogue_prose_label)

	var chapter_label = Label.new()
	chapter_label.text = EPILOGUE_CHAPTER_LINE
	chapter_label.align = Label.ALIGN_CENTER
	chapter_label.add_font_override("font", _make_font(_font_data_italic, 15))
	chapter_label.add_color_override("font_color", COLOR_AMBER)
	vbox.add_child(chapter_label)

	var restart_button = Button.new()
	restart_button.name = "RestartButton"
	restart_button.text = "Restart"
	restart_button.rect_min_size = Vector2(0, 44)
	restart_button.connect("pressed", self, "_on_restart_pressed")
	_style_button(restart_button, _make_font(_font_data_regular, 17, 1, 1))
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
# helpers — chrome
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
	style.set_border_width_all(PANEL_BORDER_WIDTH)
	style.border_color = COLOR_BORDER
	style.set_corner_radius_all(PANEL_CORNER_RADIUS)
	style.shadow_color = COLOR_SHADOW
	style.shadow_size = 18

	var panel = PanelContainer.new()
	panel.rect_min_size = Vector2(PANEL_MAX_WIDTH, 0)
	panel.add_stylebox_override("panel", style)
	center_parent.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_constant_override("separation", 16)
	panel.add_child(vbox)
	return vbox


func _new_button_stylebox(bg_color, border_color, border_width):
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_border_width_all(border_width)
	style.border_color = border_color
	style.set_corner_radius_all(BUTTON_CORNER_RADIUS)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _style_button(btn, font):
	# Dark, quiet fill with a hairline amber border. Hover warms slightly;
	# pressed sinks darker; focus adds a soft amber glow outline so keyboard
	# navigation stays clearly legible without any bright/saturated color.
	btn.add_stylebox_override("normal", _new_button_stylebox(COLOR_BTN_BG, COLOR_BTN_BORDER, BUTTON_BORDER_WIDTH))
	btn.add_stylebox_override("hover", _new_button_stylebox(COLOR_BTN_BG_HOVER, COLOR_BTN_BORDER_HOVER, BUTTON_BORDER_WIDTH))
	btn.add_stylebox_override("pressed", _new_button_stylebox(COLOR_BTN_BG_PRESSED, COLOR_BTN_BORDER_PRESSED, BUTTON_BORDER_WIDTH))
	btn.add_stylebox_override("disabled", _new_button_stylebox(COLOR_BTN_BG, COLOR_CREAM_DIM, BUTTON_BORDER_WIDTH))

	var focus_style = StyleBoxFlat.new()
	focus_style.bg_color = Color(0, 0, 0, 0)
	focus_style.set_border_width_all(2)
	focus_style.border_color = COLOR_FOCUS_GLOW
	focus_style.set_corner_radius_all(BUTTON_CORNER_RADIUS)
	focus_style.shadow_color = Color(0.913725, 0.658824, 0.298039, 0.35)
	focus_style.shadow_size = 6
	btn.add_stylebox_override("focus", focus_style)

	btn.add_color_override("font_color", COLOR_AMBER)
	btn.add_color_override("font_color_hover", COLOR_AMBER_LIGHT)
	btn.add_color_override("font_color_pressed", COLOR_AMBER_LIGHT)
	btn.add_color_override("font_color_disabled", COLOR_CREAM_DIM)
	if font != null:
		btn.add_font_override("font", font)


func _style_checkbox(cb, font):
	# CheckBox keeps its own tick glyph, so the fill styles stay empty/
	# transparent — only a warm focus outline is added for accessibility.
	var empty_style = StyleBoxEmpty.new()
	cb.add_stylebox_override("normal", empty_style)
	cb.add_stylebox_override("hover", empty_style)
	cb.add_stylebox_override("pressed", empty_style)
	cb.add_stylebox_override("hover_pressed", empty_style)
	cb.add_stylebox_override("disabled", empty_style)

	var focus_style = StyleBoxFlat.new()
	focus_style.bg_color = Color(0, 0, 0, 0)
	focus_style.set_border_width_all(1)
	focus_style.border_color = COLOR_FOCUS_GLOW
	focus_style.set_corner_radius_all(2)
	focus_style.content_margin_left = 4
	focus_style.content_margin_right = 4
	focus_style.content_margin_top = 2
	focus_style.content_margin_bottom = 2
	cb.add_stylebox_override("focus", focus_style)

	cb.add_color_override("font_color", COLOR_CREAM_DIM)
	cb.add_color_override("font_color_hover", COLOR_AMBER)
	cb.add_color_override("font_color_pressed", COLOR_AMBER_LIGHT)
	cb.add_color_override("font_color_disabled", COLOR_CREAM_DIM)
	if font != null:
		cb.add_font_override("font", font)


# ---------------------------------------------------------------------------
# helpers — typography
# ---------------------------------------------------------------------------

func _load_font_data():
	# Liberation Serif (SIL OFL 1.1, bundled under assets/fonts/) gives the
	# title cards a humanist, museum-placard feel. If the resource can't be
	# loaded for any reason, _make_font() falls back to the engine's default.
	_font_data_regular = _try_load_font_data(FONT_REGULAR_PATH)
	_font_data_bold = _try_load_font_data(FONT_BOLD_PATH)
	_font_data_italic = _try_load_font_data(FONT_ITALIC_PATH)


func _try_load_font_data(path):
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	if res is DynamicFontData:
		return res
	return null


func _make_font(font_data, size, extra_spacing_char = 0, extra_spacing_space = 0):
	var f = DynamicFont.new()
	f.size = size
	if font_data != null:
		f.font_data = font_data
	else:
		# Fall back to the engine's built-in default font data at the
		# requested size, so hierarchy still reads even without the bundled
		# serif (e.g. if the .ttf assets are ever missing).
		var base_font = Control.new().get_font("font")
		if base_font is DynamicFont and base_font.font_data != null:
			f.font_data = base_font.font_data
	if extra_spacing_char != 0:
		f.extra_spacing_char = extra_spacing_char
	if extra_spacing_space != 0:
		f.extra_spacing_space = extra_spacing_space
	return f
