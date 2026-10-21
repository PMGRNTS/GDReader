class_name Finder
extends CanvasLayer

## Fuzzy jump-to-file (§3.7).
##
## Peek only helps within the region you're already near; this covers the rest of
## the project. Selecting a file flies the camera to it and focuses it.

signal picked(file_key: String)

const MAX_ROWS := 300

var _line: LineEdit
var _list: ItemList
var _entries: Array = []        # [{ key, name, dir }]
var _shown: Array = []          # file keys, parallel to list rows


func _init(font: Font, bold: Font) -> void:
	layer = 60
	visible = false

	var scrim := ColorRect.new()
	scrim.color = Color(Palette.CANVAS.r, Palette.CANVAS.g, Palette.CANVAS.b, 0.80)
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
	box.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", box)
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size = Vector2(760, 470)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Jump to file"
	title.add_theme_font_override("font", bold)
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Palette.HEADING)
	col.add_child(title)

	_line = LineEdit.new()
	_line.placeholder_text = "type to filter…"
	_line.add_theme_font_override("font", font)
	_line.add_theme_font_size_override("font_size", 16)
	_line.text_changed.connect(func(_t: String) -> void: _refilter())
	col.add_child(_line)

	_list = ItemList.new()
	_list.add_theme_font_override("font", font)
	_list.add_theme_font_size_override("font_size", 15)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.custom_minimum_size = Vector2(0, 360)
	_list.item_activated.connect(func(idx: int) -> void: _accept(idx))
	col.add_child(_list)


func open(entries: Array) -> void:
	_entries = entries
	_line.text = ""
	visible = true
	_refilter()
	_line.grab_focus()


## Dev entry point for capturing the finder mid-query.
func seed_query(q: String) -> void:
	_line.text = q
	_refilter()


func close() -> void:
	visible = false


const FILENAME_BONUS := 12

## Subsequence match with bonuses for word starts and consecutive runs, which is
## what makes "uhb" find "ui/health_bar.gd". Returns -1 for no match.
##
## Scored twice — against the path and against the filename alone — because a
## query that matches only the folder ties every file in it. "play" in a
## player/ folder should still land on player.gd, not on its three siblings.
static func score(query: String, target: String) -> int:
	if query.is_empty():
		return 0
	# Every candidate starts with "res://", so matching inside it is pure noise —
	# it let "sm" score on the s of "res" and rank main.gd above state_machine.gd.
	var rel := target.to_lower().trim_prefix("res://")
	var by_path := _seq_score(query.to_lower(), rel)
	var by_name := _seq_score(query.to_lower(), rel.get_file())
	if by_name >= 0:
		by_name += FILENAME_BONUS
	return maxi(by_path, by_name)


static func _seq_score(q: String, t: String) -> int:
	var total := 0
	var prev := -2
	var from := 0

	for i in q.length():
		var c := q[i]
		if c == " ":
			continue
		var found := -1
		var j := from
		while j < t.length():
			if t[j] == c:
				found = j
				break
			j += 1
		if found < 0:
			return -1
		total += 1
		if found == prev + 1:
			total += 6                          # consecutive characters
		if found == 0 or t[found - 1] == "/" or t[found - 1] == "_" or t[found - 1] == ".":
			total += 9                          # start of a path or word segment
		prev = found
		from = found + 1

	return total - int(t.length() / 12.0)       # nudge shorter paths up


func _refilter() -> void:
	var q := _line.text.strip_edges()
	var scored: Array = []

	for e in _entries:
		var entry: Dictionary = e
		var s := score(q, str(entry["key"]))
		if s >= 0:
			scored.append({"s": s, "e": entry})

	if q.is_empty():
		scored.sort_custom(func(a, b): return str(a["e"]["key"]) < str(b["e"]["key"]))
	else:
		scored.sort_custom(func(a, b): return int(a["s"]) > int(b["s"]))

	_list.clear()
	_shown.clear()
	for row in scored.slice(0, MAX_ROWS):
		var entry: Dictionary = row["e"]
		var idx := _list.add_item("%s      %s" % [entry["name"], entry["dir"]])
		_list.set_item_custom_fg_color(idx, Palette.INK)
		_shown.append(str(entry["key"]))

	if _list.item_count > 0:
		_list.select(0)
		_list.ensure_current_is_visible()


func _accept(idx: int) -> void:
	if idx < 0 or idx >= _shown.size():
		return
	var key: String = _shown[idx]
	close()
	picked.emit(key)


func _move(delta: int) -> void:
	if _list.item_count == 0:
		return
	var sel := _list.get_selected_items()
	var cur: int = sel[0] if not sel.is_empty() else 0
	var next := clampi(cur + delta, 0, _list.item_count - 1)
	_list.select(next)
	_list.ensure_current_is_visible()


## The LineEdit holds focus, so arrows and Enter have to be intercepted here
## before it treats them as caret movement.
func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			close()
		KEY_UP:
			_move(-1)
		KEY_DOWN:
			_move(1)
		KEY_ENTER, KEY_KP_ENTER:
			var sel := _list.get_selected_items()
			_accept(sel[0] if not sel.is_empty() else 0)
		_:
			return
	get_viewport().set_input_as_handled()
