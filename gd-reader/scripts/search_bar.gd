class_name SearchBar
extends CanvasLayer

## Find within the focused card (§3.9).
##
## Scoped to one card deliberately: Ctrl+P covers paths, this covers the file in
## front of you, and a project-wide grep would want a results surface the canvas
## doesn't have.

signal query_changed(q: String)
signal stepped(dir: int)
signal closed()

var _line: LineEdit
var _count: Label


func _init(font: Font, bold: Font) -> void:
	layer = 40
	visible = false

	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	centre.offset_top = -78
	centre.offset_bottom = -18
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.CARD
	box.border_color = Palette.CARD_BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", box)
	centre.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var tag := Label.new()
	tag.text = "find"
	tag.add_theme_font_override("font", bold)
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", Palette.META)
	row.add_child(tag)

	_line = LineEdit.new()
	_line.custom_minimum_size = Vector2(420, 0)
	_line.add_theme_font_override("font", font)
	_line.add_theme_font_size_override("font_size", 15)
	_line.text_changed.connect(func(t: String) -> void: query_changed.emit(t))
	row.add_child(_line)

	_count = Label.new()
	_count.add_theme_font_override("font", font)
	_count.add_theme_font_size_override("font_size", 13)
	_count.add_theme_color_override("font_color", Palette.META)
	_count.custom_minimum_size = Vector2(120, 0)
	row.add_child(_count)


func open() -> void:
	visible = true
	_line.text = ""
	set_count(0, -1)
	_line.grab_focus()


## Dev entry point for capturing the bar mid-query.
func seed_query(q: String) -> void:
	_line.text = q


func close() -> void:
	visible = false
	closed.emit()


func set_count(total: int, current: int) -> void:
	if total == 0:
		_count.text = "no matches" if not _line.text.is_empty() else ""
	else:
		_count.text = "%d / %d" % [current + 1, total]


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			close()
		KEY_ENTER, KEY_KP_ENTER:
			stepped.emit(-1 if event.shift_pressed else 1)
		_:
			return
	get_viewport().set_input_as_handled()
