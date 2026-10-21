class_name LooseEnds
extends CanvasLayer

## The review surface for twine that needs attention (§5.6).
##
## Two kinds share one panel because they are the same thing to the reader —
## something left unfinished:
##   undescribed — drawn but never labelled, rendered dashed on the canvas
##   broken      — its anchored symbol or file is gone after a refresh
##
## Broken twine is never auto-deleted. A rename and a deletion are identical to a
## text scanner, so discarding silently would eat annotations on every refactor.

signal jumped(link_id: String)
signal described(link_id: String, text: String)
signal removed(link_id: String)

var _list: ItemList
var _desc: LineEdit
var _title: Label
var _rows: Array = []            # [{ id, kind }]


func _init(font: Font, bold: Font) -> void:
	layer = 55
	visible = false

	var scrim := ColorRect.new()
	scrim.color = Color(Palette.CANVAS.r, Palette.CANVAS.g, Palette.CANVAS.b, 0.84)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.CARD
	box.border_color = Palette.CARD_BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", box)
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(880, 480)
	panel.add_child(col)

	_title = Label.new()
	_title.add_theme_font_override("font", bold)
	_title.add_theme_font_size_override("font_size", 18)
	_title.add_theme_color_override("font_color", Palette.HEADING)
	col.add_child(_title)

	var hint := Label.new()
	hint.text = "Enter jump to it   ·   type a description and Tab to label   ·   Delete discard"
	hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Palette.META)
	col.add_child(hint)

	_list = ItemList.new()
	_list.add_theme_font_override("font", font)
	_list.add_theme_font_size_override("font_size", 14)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 340)
	_list.item_activated.connect(func(i: int) -> void: _jump(i))
	col.add_child(_list)

	_desc = LineEdit.new()
	_desc.placeholder_text = "label the selected twine…"
	_desc.add_theme_font_override("font", font)
	_desc.add_theme_font_size_override("font_size", 15)
	_desc.text_submitted.connect(_on_submit)
	col.add_child(_desc)


## `entries` are built by the canvas, which knows how to resolve anchors.
func open(entries: Array) -> void:
	_rows = entries
	_list.clear()
	for e in entries:
		var entry: Dictionary = e
		var idx := _list.add_item("%s   %s" % [entry["badge"], entry["text"]])
		_list.set_item_custom_fg_color(idx,
			Palette.TWINE_BROKEN if entry["kind"] == "broken" else Palette.TWINE)
	_title.text = "Loose ends — %d" % entries.size()
	if entries.is_empty():
		_list.add_item("nothing loose: every twine is labelled and lands somewhere")
		_list.set_item_custom_fg_color(0, Palette.META)
		_list.set_item_selectable(0, false)
	else:
		_list.select(0)
	_desc.text = ""
	visible = true
	_list.grab_focus()


func close() -> void:
	visible = false


func _selected_row() -> Dictionary:
	var sel := _list.get_selected_items()
	if sel.is_empty() or sel[0] >= _rows.size():
		return {}
	return _rows[sel[0]]


func _jump(i: int) -> void:
	if i < 0 or i >= _rows.size():
		return
	close()
	jumped.emit(str(_rows[i]["id"]))


func _on_submit(text: String) -> void:
	var row := _selected_row()
	if row.is_empty() or text.strip_edges().is_empty():
		return
	described.emit(str(row["id"]), text.strip_edges())
	_desc.text = ""


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	# The description field owns typing; only Esc escapes it.
	if _desc.has_focus():
		if event.keycode == KEY_ESCAPE:
			_list.grab_focus()
			get_viewport().set_input_as_handled()
		return

	match event.keycode:
		KEY_ESCAPE:
			close()
		KEY_ENTER, KEY_KP_ENTER:
			var sel := _list.get_selected_items()
			if not sel.is_empty():
				_jump(sel[0])
		KEY_TAB:
			_desc.grab_focus()
		KEY_DELETE, KEY_BACKSPACE:
			var row := _selected_row()
			if not row.is_empty():
				removed.emit(str(row["id"]))
		_:
			return
	get_viewport().set_input_as_handled()
