class_name UIKit
extends RefCounted

## Shared chrome for the toolbar, the connections panel and the context pill.
##
## Every button here is FOCUS_NONE. A focused button would swallow Space, Enter
## and the arrows — the canvas's own bindings — so clicking one would quietly
## break the keyboard until you clicked the canvas again.

const BAR_H := 46.0
const RADIUS := 5


static func panel_box(alpha := 0.96, margin := 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.CARD.r, Palette.CARD.g, Palette.CARD.b, alpha)
	box.border_color = Palette.CARD_BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(RADIUS + 1)
	box.set_content_margin_all(margin)
	return box


static func _btn_box(bg: Color, border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(RADIUS)
	box.content_margin_left = 9
	box.content_margin_right = 9
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


## A quiet button: no fill until hovered, so a row of them reads as a toolbar
## rather than a wall of boxes. `toggle` buttons show their on state filled.
static func button(text: String, tip: String, font: Font, toggle := false) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	b.add_theme_font_override("font", font)
	# A lone glyph at body size reads as a speck; give it a little more.
	b.add_theme_font_size_override("font_size", 16 if text.length() == 1 else 13)
	b.add_theme_color_override("font_color", Palette.INK)
	b.add_theme_color_override("font_hover_color", Palette.HEADING)
	b.add_theme_color_override("font_pressed_color", Palette.HEADING)
	b.add_theme_color_override("font_hover_pressed_color", Palette.HEADING)
	b.add_theme_color_override("font_disabled_color", Palette.LINE_NUM)
	b.add_theme_stylebox_override("normal", _btn_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("hover", _btn_box(Palette.RULE, Palette.CARD_BORDER))
	b.add_theme_stylebox_override("pressed", _btn_box(Palette.SELECTION, Palette.TYPE.darkened(0.4)))
	b.add_theme_stylebox_override("hover_pressed", _btn_box(Palette.SELECTION, Palette.TYPE.darkened(0.2)))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b


## Hairline between button groups.
static func divider() -> Control:
	var r := ColorRect.new()
	r.color = Palette.RULE
	r.custom_minimum_size = Vector2(1, 22)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func label(text: String, font: Font, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The canvas accepts Ctrl or Cmd for every chord; the labels should say the one
## the platform's users actually press.
static func mod(key: String) -> String:
	return ("⌘" + key) if OS.get_name() == "macOS" else ("Ctrl+" + key)
