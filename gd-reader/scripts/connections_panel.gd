class_name ConnectionsPanel
extends CanvasLayer

## The focused file's connections, as a list you can read (§5.7).
##
## On the canvas a connection is a line, and a line to a card that's off-screen
## only says "somewhere that way". Forty of them from one corner say nothing at
## all. Here each one is named — the far file, its folder, the evidence — and
## the canvas line is the thing you summon by pointing at a row, not the other
## way round.
##
## Rows carry indices into the canvas's own lists (its twine cycle and
## inferred_for_focus()), so the panel and the keyboard select the same things.

signal edge_hovered(idx: int)            # -1 when the pointer leaves
signal edge_clicked(idx: int)
signal edge_go(idx: int)
signal edge_adopt(idx: int)
signal twine_hovered(id: String)         # "" when the pointer leaves
signal twine_clicked(idx: int)
signal twine_go(idx: int)
signal twine_delete(id: String)
signal lines_mode_chosen(mode: int)
signal close_requested()

const W := 360.0
const ROW_H := 46.0

var _font: Font
var _bold: Font
var _root: PanelContainer
var _subtitle: Label
var _list: VBoxContainer
var _modes: Array = []
var _edge_rows := {}             # idx -> Button
var _twine_rows := {}            # cycle idx -> Button


func _init(font: Font, bold: Font) -> void:
	layer = 30
	_font = font
	_bold = bold

	_root = PanelContainer.new()
	_root.add_theme_stylebox_override("panel", UIKit.panel_box(0.97, 12))
	_root.anchor_left = 1.0
	_root.anchor_right = 1.0
	_root.anchor_top = 0.0
	_root.anchor_bottom = 1.0
	_root.offset_left = -W - 10.0
	_root.offset_right = -10.0
	_root.offset_top = UIKit.BAR_H + 10.0
	_root.offset_bottom = -10.0
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_root.add_child(col)

	# --- header
	var head := HBoxContainer.new()
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(UIKit.label("Connections", bold, 15, Palette.HEADING))
	_subtitle = UIKit.label("", font, 12, Palette.META)
	_subtitle.clip_text = true
	titles.add_child(_subtitle)
	var close := UIKit.button("×", "Hide this panel  ·  C", font)
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)

	# --- which lines the canvas draws
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 2)
	col.add_child(modes)
	var ml := UIKit.label("Lines", font, 12, Palette.META)
	ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.add_child(ml)
	var mode_names := ["Pointed at", "This file", "All"]
	var mode_tips := [
		"Draw a detected line only for the row you point at or select  ·  "
			+ UIKit.mod("E") + " cycles",
		"Draw every detected line touching the focused file",
		"Draw the whole project's detected web — best at Map zoom",
	]
	for i in 3:
		var b := UIKit.button(mode_names[i], mode_tips[i], font, true)
		var m := i
		b.pressed.connect(func() -> void: lines_mode_chosen.emit(m))
		modes.add_child(b)
		_modes.append(b)

	var rule := ColorRect.new()
	rule.color = Palette.RULE
	rule.custom_minimum_size = Vector2(0, 1)
	col.add_child(rule)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


## Screen pixels the panel takes from the right of the viewport, for the canvas
## to centre focus in what's left.
func occupied_width() -> float:
	return W + 20.0 if visible else 0.0


func set_lines_mode(mode: int) -> void:
	for i in _modes.size():
		_modes[i].set_pressed_no_signal(i == mode)


## `twines`: [{ id, idx, outgoing, far_name, far_dir, here_sym, far_sym, desc, broken }]
## `edges` : [{ idx, outgoing, far_name, far_dir, desc, weight }]
func show_for(file_name: String, twines: Array, edges: Array) -> void:
	for c in _list.get_children():
		c.queue_free()
	_edge_rows.clear()
	_twine_rows.clear()

	var uses := edges.filter(func(e): return e["outgoing"])
	var used_by := edges.filter(func(e): return not e["outgoing"])
	_subtitle.text = "%s  ·  %d twine  ·  %d detected" % [file_name, twines.size(), edges.size()]

	_section("Twine", twines.size(), Palette.TWINE)
	if twines.is_empty():
		_hint("Nothing drawn yet. Drag from this card onto another to tie them "
			+ "together, or press + on a detected connection below.")
	for t in twines:
		_twine_row(t)

	_section("Uses", uses.size(), Palette.TYPE)
	if uses.is_empty():
		_hint("This file doesn't reach any other file we can see.")
	for e in uses:
		_edge_row(e)

	_section("Used by", used_by.size(), Palette.TYPE)
	if used_by.is_empty():
		_hint("Nothing else in the project refers to this file.")
	for e in used_by:
		_edge_row(e)


## Restyles the selection without rebuilding the rows.
func mark(adopt_idx: int, cycle_idx: int) -> void:
	for i in _edge_rows:
		_edge_rows[i].set_pressed_no_signal(i == adopt_idx)
	for i in _twine_rows:
		_twine_rows[i].set_pressed_no_signal(i == cycle_idx)


# ------------------------------------------------------------------- building

func _section(title: String, count: int, col: Color) -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	_list.add_child(gap)
	var row := HBoxContainer.new()
	row.add_child(UIKit.label(title.to_upper(), _bold, 11, col))
	row.add_child(UIKit.label("  %d" % count, _font, 11, Palette.META))
	_list.add_child(row)


func _hint(text: String) -> void:
	var l := UIKit.label(text, _font, 12, Palette.LINE_NUM)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(W - 40.0, 0)
	_list.add_child(l)


## A row is one big flat toggle button with its text and actions laid over it,
## so the whole row is the click target and the actions still get their own.
func _row(swatch: Color, title: String, sub: String, sub_col: Color) -> Array:
	var b := UIKit.button("", "", _font, true)
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(b)

	var h := HBoxContainer.new()
	h.set_anchors_preset(Control.PRESET_FULL_RECT)
	h.offset_left = 4
	h.offset_right = -4
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(h)

	var bar := ColorRect.new()
	bar.color = swatch
	bar.custom_minimum_size = Vector2(3, 30)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 1)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(text)
	var t := UIKit.label(title, _bold, 13, Palette.HEADING)
	t.clip_text = true
	text.add_child(t)
	var s := UIKit.label(sub, _font, 11, sub_col)
	s.clip_text = true
	text.add_child(s)
	return [b, h]


func _action(parent: Control, text: String, tip: String, fn: Callable) -> void:
	var a := UIKit.button(text, tip, _font)
	a.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	a.pressed.connect(fn)
	parent.add_child(a)


func _edge_row(e: Dictionary) -> void:
	var idx: int = e["idx"]
	var t: float = clampf(float(e["weight"]) / 20.0, 0.0, 1.0)
	var swatch := Palette.INFERRED
	swatch.a = lerpf(0.45, 1.0, t)
	var arrow := "→ " if e["outgoing"] else "← "
	var parts := _row(swatch, arrow + str(e["far_name"]),
		"%s   %s" % [e["desc"], e["far_dir"]], Palette.META)
	var b: Button = parts[0]
	var h: HBoxContainer = parts[1]
	b.tooltip_text = "Click to frame both files  ·  G cycles"
	b.pressed.connect(func() -> void: edge_clicked.emit(idx))
	b.mouse_entered.connect(func() -> void: edge_hovered.emit(idx))
	b.mouse_exited.connect(func() -> void: edge_hovered.emit(-1))
	_action(h, "Go", "Focus %s" % e["far_name"], func() -> void: edge_go.emit(idx))
	_action(h, "+", "Adopt as twine — you write why  ·  A",
		func() -> void: edge_adopt.emit(idx))
	_edge_rows[idx] = b


func _twine_row(tw: Dictionary) -> void:
	var idx: int = tw["idx"]
	var id: String = tw["id"]
	var desc: String = str(tw["desc"]).strip_edges()
	var broken: bool = tw["broken"]
	var arrow := "→ " if tw["outgoing"] else "← "
	var sub := desc if desc != "" else "unlabelled  ·  %s to label" % UIKit.mod("L")
	if broken:
		sub = "⚠ an end no longer resolves  ·  " + sub
	var parts := _row(Palette.TWINE_BROKEN if broken else Palette.TWINE,
		arrow + str(tw["far_name"]), sub,
		Palette.INK if desc != "" and not broken else Palette.TWINE_BROKEN)
	var b: Button = parts[0]
	var h: HBoxContainer = parts[1]
	b.tooltip_text = "%s%s  ↔  %s\nClick to select  ·  Tab cycles" % [
		(desc + "\n") if desc != "" else "", tw["here_sym"], tw["far_sym"]]
	b.pressed.connect(func() -> void: twine_clicked.emit(idx))
	b.mouse_entered.connect(func() -> void: twine_hovered.emit(id))
	b.mouse_exited.connect(func() -> void: twine_hovered.emit(""))
	_action(h, "Go", "Follow to %s  ·  Enter" % tw["far_name"], func() -> void: twine_go.emit(idx))
	_action(h, "×", "Delete this twine  ·  Delete", func() -> void: twine_delete.emit(id))
	_twine_rows[idx] = b
