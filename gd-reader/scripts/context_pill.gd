class_name ContextPill
extends CanvasLayer

## What's selected right now, and what you can do with it.
##
## Peek, overview, framing a coupling and cycling twine are all temporary states
## that the keyboard enters silently. The pill names the state and puts its
## next moves under the pointer, so none of them is a mode you can get lost in.

signal action(name: String)

var _font: Font
var _row: HBoxContainer
var _text: Label
var _sig := ""                   # what's showing, so an unchanged frame rebuilds nothing


func _init(font: Font, bold: Font) -> void:
	layer = 35
	visible = false
	_font = font

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	centre.offset_top = -70
	centre.offset_bottom = -18
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(0.97, 8))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	centre.add_child(panel)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	panel.add_child(_row)

	_text = UIKit.label("", bold, 13, Palette.HEADING)
	_text.custom_minimum_size = Vector2(0, 26)
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_row.add_child(_text)


## `buttons` is [[text, tooltip, action_name], …]. An empty `text` hides the pill.
func present(text: String, accent: Color, buttons: Array) -> void:
	var sig := text + str(buttons)
	if sig == _sig:
		return
	_sig = sig
	visible = text != ""
	if not visible:
		return
	_text.text = "  " + text + "  "
	_text.add_theme_color_override("font_color", accent)
	for i in range(_row.get_child_count() - 1, 0, -1):
		_row.get_child(i).queue_free()
	for spec in buttons:
		var name: String = spec[2]
		var b := UIKit.button(spec[0], spec[1], _font)
		b.pressed.connect(func() -> void: action.emit(name))
		_row.add_child(b)
