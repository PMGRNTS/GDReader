class_name Toolbar
extends CanvasLayer

## The top bar: where you are, and a button for every keybinding worth one.
##
## Grouped left to right by how often a hand reaches for it — moving, then
## finding, then zooming, then the panels. Every tooltip names its key, so the
## bar doubles as the way people learn the keyboard.
##
## The bar owns no state. The canvas pushes a snapshot through refresh() and
## hears back through `action`, so there is exactly one source of truth.

signal action(name: String)

var _crumb_dir: Label
var _crumb_file: Label
var _back: Button
var _fwd: Button
var _find: Button
var _modes: Array = []           # [Read, Skim, Map], indexed by Card.Detail
var _zoom_pct: Label
var _overview: Button
var _blast: Button
var _connections: Button
var _loose: Button


func _init(font: Font, bold: Font) -> void:
	layer = 30

	var bar := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.CANVAS.r, Palette.CANVAS.g, Palette.CANVAS.b, 0.94)
	box.border_color = Palette.RULE
	box.border_width_bottom = 1
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	bar.add_theme_stylebox_override("panel", box)
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, UIKit.BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bar)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	bar.add_child(row)

	# --- move
	_add(row, "‹", "Previous file  ·  H / ←", "prev_file", font)
	_add(row, "›", "Next file  ·  L / →", "next_file", font)
	_add(row, "▴", "Folder above  ·  Shift+K / Shift+Wheel", "folder_up", font)
	_add(row, "▾", "Folder below  ·  Shift+J / Shift+Wheel", "folder_down", font)
	_gap(row)
	_back = _add(row, "←", "Back to the previous jump  ·  Alt+←", "back", font)
	_fwd = _add(row, "→", "Forward  ·  Alt+→", "forward", font)
	_gap(row)

	# --- where you are. The file name always shows; the folder and position
	# after it trim with an ellipsis before any button gives way.
	_crumb_file = UIKit.label("", bold, 14, Palette.HEADING)
	row.add_child(_crumb_file)
	_crumb_dir = UIKit.label("", font, 12, Palette.META)
	_crumb_dir.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crumb_dir.clip_text = true
	_crumb_dir.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_crumb_dir)

	# --- find
	# Key hints live in the tooltips; in the labels they cost more room than the
	# bar has once every button is on it.
	_add(row, "Go to file", "Jump to any file by name  ·  " + UIKit.mod("P"), "finder", font)
	_find = _add(row, "Find", "Find within the focused card  ·  " + UIKit.mod("F"), "search", font)
	_gap(row)

	# --- zoom: the three modes are the zoom axis's named stops (§4)
	_add(row, "−", "Zoom out  ·  -  or  " + UIKit.mod("Wheel"), "zoom_out", font)
	var tips := [
		"Read — full source  ·  0 resets to 100%",
		"Skim — signatures only, a table of contents",
		"Map — every file as a titled node",
	]
	var names := ["Read", "Skim", "Map"]
	for i in 3:
		_modes.append(_add(row, names[i], tips[i], ["read", "skim", "map"][i], font, true))
	_add(row, "+", "Zoom in  ·  +  or  " + UIKit.mod("Wheel"), "zoom_in", font)
	_zoom_pct = UIKit.label("", font, 12, Palette.LINE_NUM)
	_zoom_pct.custom_minimum_size = Vector2(40, 0)
	_zoom_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_zoom_pct)
	_overview = _add(row, "Overview", "Whole project; click a card to land there  ·  M\n"
		+ "(or hold Space to peek)", "overview", font, true)
	_blast = _add(row, "Blast", "Blast radius — everything that depends on this file, ring by ring  ·  B\n"
		+ "1 / 2 / 3 set how many hops", "blast", font, true)
	_blast.add_theme_color_override("font_color", Palette.blast_color(1))
	_gap(row)

	# --- panels
	_loose = _add(row, "", "Unlabelled and broken twine  ·  " + UIKit.mod("L"), "loose", font)
	_loose.add_theme_color_override("font_color", Palette.TWINE_BROKEN)
	_connections = _add(row, "Connections", "What this file touches, and what touches it  ·  C",
		"connections", font, true)
	_add(row, "⟳", "Re-read the project from disk  ·  R", "refresh", font)
	_add(row, "Open…", "Open a different project  ·  " + UIKit.mod("O"), "open", font)
	_add(row, "?", "All shortcuts  ·  ? / F1", "help", font)


func _add(parent: Control, text: String, tip: String, name: String, font: Font,
		toggle := false) -> Button:
	var b := UIKit.button(text, tip, font, toggle)
	# Toggle buttons would flip themselves before the canvas decides; the canvas
	# owns the state and sets it back through refresh(), so read `pressed` only.
	b.pressed.connect(func() -> void: action.emit(name))
	parent.add_child(b)
	return b


func _gap(parent: Control) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(6, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(spacer)
	parent.add_child(UIKit.divider())
	var spacer2 := spacer.duplicate()
	parent.add_child(spacer2)


## `s` is a plain snapshot from the canvas — see CanvasView._toolbar_state().
func refresh(s: Dictionary) -> void:
	_crumb_file.text = str(s.get("file", ""))
	_crumb_dir.text = "   %s   %d/%d  ·  folder %d/%d" % [s.get("dir", ""),
		s.get("file_i", 0), s.get("file_n", 0), s.get("row_i", 0), s.get("row_n", 0)]
	_back.disabled = not s.get("can_back", false)
	_fwd.disabled = not s.get("can_fwd", false)
	_find.disabled = not s.get("can_find", false)

	var detail: int = s.get("detail", 0)
	for i in _modes.size():
		_modes[i].set_pressed_no_signal(i == detail)
	_zoom_pct.text = "%d%%" % int(s.get("zoom_pct", 100))
	_overview.set_pressed_no_signal(s.get("overview", false))
	_blast.set_pressed_no_signal(s.get("blast", false))

	var n: int = s.get("connections_n", 0)
	_connections.text = "Connections  %d" % n if n > 0 else "Connections"
	_connections.set_pressed_no_signal(s.get("connections_open", false))

	# Loose ends only take up room when there's something loose.
	var loose: int = s.get("loose_n", 0)
	_loose.visible = loose > 0
	_loose.text = "◌ %d loose" % loose
