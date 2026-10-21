class_name Legend
extends CanvasLayer

## Keyboard shortcut legend, toggled with ? or F1.
##
## Lists only what is actually wired up — a legend that promises bindings the app
## doesn't have is worse than no legend.

const ROWS := [
	["§", "Navigate"],
	["H  L        ← →", "Focus previous / next file"],
	["Shift+J  Shift+K", "Hop folder up / down"],
	["Shift+Wheel", "Hop folder up / down"],
	["Wheel", "Scroll the focused card"],
	["Space  (hold)", "Peek the row; keep holding for the whole project"],
	["Alt+←  Alt+→", "Back / forward through jumps"],
	["Ctrl+P", "Jump to any file by name"],
	["M", "Overview: whole project, click a card to land"],
	["Click", "Focus a card"],

	["§", "Zoom"],
	["Ctrl+Wheel", "Zoom continuously: Read → Skim → Map"],
	["+   -", "Zoom in / out"],
	["0", "Back to 100% (Read)"],

	["§", "Twine"],
	["Drag card → card", "Draw twine, then choose both ends"],
	["Tab  Shift+Tab", "Cycle the focused file's twine"],
	["Enter", "Follow the selected twine to its far end"],
	["Delete", "Remove the selected twine"],
	["Ctrl+L", "Loose ends: unlabelled and broken twine"],

	["§", "Connections"],
	["C", "Show or hide the connections panel"],
	["Ctrl+E", "Detected lines: pointed at → this file → all"],
	["G  Shift+G", "Cycle couplings; the camera frames each pair"],
	["A", "Adopt the selected coupling as twine"],
	["B", "Blast radius: what depends on this file, ring by ring"],
	["1  2  3", "Blast radius depth, in hops"],

	["§", "Read"],
	["Ctrl+F", "Find within the focused card"],
	["Alt+drag", "Select text"],
	["Ctrl+C", "Copy the selection"],

	["§", "Other"],
	["Ctrl+O", "Open a different project"],
	["R", "Re-read the project from disk"],
	["?   F1", "Show or hide this legend"],
	["Esc", "Back out: blast, overview, framing, then selection"],
	["Ctrl+Q", "Quit"],
]


func _init(font: Font, bold: Font) -> void:
	layer = 50
	visible = false

	var scrim := ColorRect.new()
	scrim.color = Color(Palette.CANVAS.r, Palette.CANVAS.g, Palette.CANVAS.b, 0.86)
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
	box.set_content_margin_all(30)
	panel.add_theme_stylebox_override("panel", box)
	centre.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	panel.add_child(col)

	var title := Label.new()
	title.text = "Shortcuts"
	title.add_theme_font_override("font", bold)
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Palette.HEADING)
	col.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 34)
	grid.add_theme_constant_override("v_separation", 6)
	col.add_child(grid)

	for row in ROWS:
		var key: String = row[0]
		var desc: String = row[1]
		if key == "§":
			grid.add_child(_spacer())
			grid.add_child(_spacer())
			var head := Label.new()
			head.text = desc.to_upper()
			head.add_theme_font_override("font", bold)
			head.add_theme_font_size_override("font_size", 12)
			head.add_theme_color_override("font_color", Palette.META)
			grid.add_child(head)
			grid.add_child(_spacer())
			continue

		var k := Label.new()
		# Every chord takes Ctrl or Cmd; name the one this platform uses.
		k.text = key.replace("Ctrl+", UIKit.mod(""))
		k.add_theme_font_override("font", font)
		k.add_theme_font_size_override("font_size", 14)
		k.add_theme_color_override("font_color", Palette.TYPE)
		k.custom_minimum_size = Vector2(210, 0)
		grid.add_child(k)

		var d := Label.new()
		d.text = desc
		d.add_theme_font_override("font", font)
		d.add_theme_font_size_override("font_size", 14)
		d.add_theme_color_override("font_color", Palette.INK)
		grid.add_child(d)


func _spacer() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, 7)
	return c


func toggle() -> void:
	visible = not visible
