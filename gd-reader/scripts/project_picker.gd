class_name ProjectPicker
extends CanvasLayer

## Switch projects at any time (Ctrl+O).
##
## One project is open at a time (§1), so this replaces what's on the canvas
## rather than adding to it. Recents come first because reopening the same few
## projects is the common case; browsing is always one key away.

signal chosen(path: String)
signal browse_requested()

const BROWSE_ROW := "＋  Browse for a project folder…"

var _list: ItemList
var _paths: Array = []          # parallel to list rows, "" for the browse row


func _init(font: Font, bold: Font) -> void:
	layer = 65
	visible = false

	var scrim := ColorRect.new()
	scrim.color = Color(Palette.CANVAS.r, Palette.CANVAS.g, Palette.CANVAS.b, 0.88)
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
	col.custom_minimum_size = Vector2(820, 420)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Open project"
	title.add_theme_font_override("font", bold)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Palette.HEADING)
	col.add_child(title)

	var hint := Label.new()
	hint.text = "Enter open   ·   B browse   ·   Esc cancel"
	hint.add_theme_font_override("font", font)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Palette.META)
	col.add_child(hint)

	_list = ItemList.new()
	_list.add_theme_font_override("font", font)
	_list.add_theme_font_size_override("font_size", 15)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 320)
	_list.item_activated.connect(_activate)
	col.add_child(_list)


func open(recents: Array, current: String) -> void:
	_list.clear()
	_paths.clear()

	var idx := _list.add_item(BROWSE_ROW)
	_list.set_item_custom_fg_color(idx, Palette.TYPE)
	_paths.append("")

	for path in recents:
		var p := str(path)
		var label := "%s      %s" % [p.get_file(), p.get_base_dir()]
		if p == current:
			label += "      (open)"
		var i := _list.add_item(label)
		_list.set_item_custom_fg_color(i, Palette.META if p == current else Palette.INK)
		_paths.append(p)

	_list.select(1 if _paths.size() > 1 else 0)
	visible = true
	_list.grab_focus()


func close() -> void:
	visible = false


func _activate(i: int) -> void:
	if i < 0 or i >= _paths.size():
		return
	if _paths[i] == "":
		close()
		browse_requested.emit()
		return
	close()
	chosen.emit(str(_paths[i]))


func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			close()
		KEY_B:
			close()
			browse_requested.emit()
		KEY_ENTER, KEY_KP_ENTER:
			var sel := _list.get_selected_items()
			if not sel.is_empty():
				_activate(sel[0])
		_:
			return
	get_viewport().set_input_as_handled()
