extends Node2D

## The strip (§2) and its navigation (§3).
##
## Focus is a single cell and the camera is DERIVED from it — the user never
## scrolls the camera directly (§1). Row = folder, column = file, alphabetical.

const COL_GAP := 120.0
const ROW_GAP := 200.0
const INDENT := 160.0            # per folder depth (§2.2)
const CAM_EASE := 12.0           # 🎚 ~180ms settle (§3.4)
const LIVE_RADIUS := 3           # cards holding real text around focus (§Open Q2)
const SCROLL_LINES := 3.0

## Semantic zoom breakpoints (§4). 1.0 is Read at 100%, where the card fills the
## viewport vertically.
const ZOOM_MIN := 0.07
const ZOOM_MAX := 1.40
const ZOOM_STEP := 1.14
const ZOOM_EASE := 15.0

## Peek (§3.6). Spring-loaded: a glance, not a mode.
const PEEK_TAP_MS := 150       # 🎚 below this a press does nothing at all
const PEEK_MAP_MS := 550       # 🎚 keep holding and it opens out to the project
const PEEK_MARGIN := 1.12
const MAX_RECENTS := 12
const NOTICE_MS := 1800         # 🎚 how long a one-off confirmation stays up

## Framing a coupling pair (§10.5) reuses peek's fit maths with a little more air.
const FRAME_MARGIN := 1.30

## Fly-to (§3.4a). A long jump pulls back far enough to show where you are and
## where you're going, pans while zoomed out, then drops in.
const FLY_MIN_SCREENS := 0.9     # 🎚 nearer than this, the ordinary ease is enough
const FLY_BASE := 0.50           # 🎚 seconds for the shortest flight…
const FLY_PER_DOUBLING := 0.14   # 🎚 …plus this for each doubling of distance
const FLY_MAX := 1.15
const FLY_MARGIN := 1.25

var rows: Array = []             # from ProjectScanner
var cards: Array = []            # Array[Array[Card]], parallel to rows
var project_root := ""

var focus_row := 0
var focus_col := 0
var _column_memory := {}         # row index -> last focused col (§3.3)

var _font: Font
var _bold: Font
## Twine model (§5). The symbol index is built once at open for EVERY file, so a
## twine's far endpoint resolves even when that card's text isn't loaded — which
## is the normal case, since only cards near focus hold text.
var store := LinkStore.new()
var index := {}                  # file_key -> { symbols: {name->line}, refs: [], line_count }
var inferred: Array = []         # weighted coupling edges from Analyzer (§10)
var autoloads := {}              # singleton name -> file_key
var adopt_idx := -1              # which inferred edge is selected for adoption
## Which detected (blue) lines the canvas draws (§5.4). Forty lines leaving one
## card corner tell you nothing, so by default only the one you point at in the
## connections panel — or select with G — is drawn.
enum Lines { POINTED, FILE, ALL }
var lines_mode := Lines.POINTED   # Ctrl+E cycles
var reduce_motion := false        # Ctrl+Shift+M: twine holds still
var hover_edge_idx := -1         # row under the pointer in the connections panel
var hover_link_id := ""
var zoom_level := 1.0            # §4, the animated value
var detail := Card.Detail.READ
var selected_link_id := ""

var drag_active := false
var drag_from_pos := Vector2.ZERO
var drag_to_pos := Vector2.ZERO

var _drag_card: Card = null
var _drag_symbol := ""
var _press_world := Vector2.ZERO
var _press_card: Card = null

var _pending_from := ""
var _pending_to := ""
var _cycle: Array = []           # links touching the focused file (§5.5)
var _cycle_idx := -1
var _history: Array = []         # [Vector2i(row, col)] (§3.8)
var _hist_idx := -1

var _twine: TwineLayer
var _dialog: LinkDialog
var _cam: Camera2D
var _cam_target := Vector2.ZERO
var _toolbar: Toolbar
var _conn: ConnectionsPanel
var _pill: ContextPill
var _conn_key := ""              # file the connections panel was last built for
var _loose_n := 0
var _overview := false           # latched project view; a click lands (M)
var _overview_saved_zoom := 1.0
var _cli_overview := false
var _cli_hover := -1
var _cli_twine := -1
var _cli_blast := 0
var _cli_jump := Vector2i(-1, -1)
var _fly := {}                   # the flight in progress, empty when there's none
var _shot_wait := 30

## Blast radius (§10.6): what depends on the focused file, ring by ring.
const BLAST_DIM := Color(0.26, 0.28, 0.32, 1.0)
var blast_on := false
var blast_depth := 2
var blast_hops := {}             # file_key -> ring (focus is 0)
var blast_parent := {}           # file_key -> the file it was reached through
var blast_cards := {}            # file_key -> Card, for the layer's per-frame draw
var _blast_started := 0
var _blast_saved_zoom := 1.0
var _blast: BlastLayer
var _cli_project := ""
var _shot_path := ""
var _cli_focus := Vector2i(-1, -1)
var _cli_zoom := 0.0
var _last_px := -1.0
var _zoom_goal := 1.0
var _peek_down_at := -1
var _peek_stage := 0             # 0 none, 1 row fit, 2 project fit
var _peek_saved_zoom := 1.0
var _peek_sel := Vector2i(-1, -1)
var _legend: Legend
var _finder: Finder
var _search: SearchBar
var _loose: LooseEnds
var _selecting := false
var _sel_card: Card = null
var _search_saved_scroll := 0.0
var _cli_peek := ""
var _cli_legend := false
var _cli_still := false
var _cli_tie := -1
var _notice := ""                 # a one-off confirmation the pill shows briefly
var _notice_until := 0
var _cli_find := ""
var _cli_search := ""
var _cli_loose := false
var _cli_adopt := -1
var _cli_picker := false
var _picker: ProjectPicker
var _framing := false
var _frame_saved_zoom := 1.0
var _last_focus := Vector2i(-1, -1)
var _peek_bias := 0


func _ready() -> void:
	_build_backdrop()
	_font = _make_font(false)
	_bold = _make_font(true)

	_cam = Camera2D.new()
	add_child(_cam)
	_cam.make_current()

	_build_chrome()

	_twine = TwineLayer.new()
	_twine.setup(self, _font, _bold)
	add_child(_twine)

	_blast = BlastLayer.new()
	_blast.setup(self, _bold)
	add_child(_blast)

	_dialog = LinkDialog.new()
	var dlg_layer := CanvasLayer.new()
	add_child(dlg_layer)
	dlg_layer.add_child(_dialog)
	_dialog.confirmed.connect(_on_link_confirmed)

	_legend = Legend.new(_font, _bold)
	add_child(_legend)

	_finder = Finder.new(_font, _bold)
	add_child(_finder)
	_finder.picked.connect(_on_file_picked)

	_search = SearchBar.new(_font, _bold)
	add_child(_search)
	_search.query_changed.connect(_on_search_query)
	_search.stepped.connect(_on_search_step)
	_search.closed.connect(_on_search_closed)

	_picker = ProjectPicker.new(_font, _bold)
	add_child(_picker)
	_picker.chosen.connect(switch_project)
	_picker.browse_requested.connect(func() -> void: browse_for_project(true))

	_loose = LooseEnds.new(_font, _bold)
	add_child(_loose)
	_loose.jumped.connect(_on_loose_jump)
	_loose.described.connect(_on_loose_described)
	_loose.removed.connect(_on_loose_removed)

	_parse_cmdline()
	if _cli_still:
		reduce_motion = true
	_twine.reduce_motion = reduce_motion

	var target := _cli_project
	if target == "":
		var recents := recent_projects()
		target = str(recents[0]) if not recents.is_empty() else ""
	if target != "" and ProjectScanner.is_project_root(target):
		open_project(target)
	else:
		browse_for_project(false)

	if _cli_legend:
		_legend.toggle()
	if _cli_find != "":
		open_finder()
		_finder.seed_query(_cli_find)
	if _cli_search != "":
		open_search()
		_on_search_query(_cli_search)
		_search.seed_query(_cli_search)
	if _cli_loose:
		open_loose_ends()
	if _cli_picker:
		open_project_picker()
	if _cli_adopt >= 0:
		for i in _cli_adopt + 1:
			cycle_adopt(1)
	if _cli_hover >= 0:
		_on_edge_hovered(_cli_hover)
	if _cli_twine >= 0:
		select_twine(_cli_twine)
	if _cli_tie >= 0 and _cli_tie < store.links.size():
		_twine.tie(store.links[_cli_tie].get("id", ""))
	if _cli_jump.x >= 0 and not cards.is_empty():
		var jr := clampi(_cli_jump.x, 0, rows.size() - 1)
		_jump_to(Vector2i(jr, clampi(_cli_jump.y, 0, cards[jr].size() - 1)))
	if _cli_blast > 0:
		blast_depth = clampi(_cli_blast, 1, 3)
		toggle_blast()
	if _cli_overview:
		toggle_overview()
	if _cli_peek != "":
		# Bias the held time so the capture lands in the requested stage. (Adding
		# to the elapsed time rather than backdating the timestamp, which can go
		# negative when the engine has only been up a few hundred ms.)
		peek_press()
		_peek_bias = (PEEK_MAP_MS + 20) if _cli_peek == "map" else (PEEK_TAP_MS + 20)

	if _shot_path != "":
		_capture_and_quit()


## Dev entry points:  godot -- <project_dir> [--shot out.png]
func _parse_cmdline() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		if a == "--shot" and i + 1 < args.size():
			_shot_path = args[i + 1]
		elif a == "--focus" and i + 1 < args.size():
			var rc: PackedStringArray = args[i + 1].split(",")
			if rc.size() == 2:
				_cli_focus = Vector2i(int(rc[0]), int(rc[1]))
		elif a == "--zoom" and i + 1 < args.size():
			_cli_zoom = float(args[i + 1])
		elif a == "--all-inferred":
			lines_mode = Lines.ALL
		elif a == "--file-lines":
			lines_mode = Lines.FILE
		elif a == "--overview":
			_cli_overview = true
		elif a == "--hover" and i + 1 < args.size():
			_cli_hover = int(args[i + 1])
		elif a == "--jump" and i + 1 < args.size():
			var jc: PackedStringArray = args[i + 1].split(",")
			if jc.size() == 2:
				_cli_jump = Vector2i(int(jc[0]), int(jc[1]))
		elif a == "--wait" and i + 1 < args.size():
			_shot_wait = int(args[i + 1])
		elif a == "--blast" and i + 1 < args.size():
			_cli_blast = int(args[i + 1])
		elif a == "--twine" and i + 1 < args.size():
			_cli_twine = int(args[i + 1])
		elif a == "--no-connections":
			_conn.visible = false
		elif a == "--peek" and i + 1 < args.size():
			_cli_peek = args[i + 1]
		elif a == "--legend":
			_cli_legend = true
		elif a == "--reduce-motion":
			_cli_still = true
		elif a == "--tie" and i + 1 < args.size():
			_cli_tie = int(args[i + 1])
		elif a == "--find" and i + 1 < args.size():
			_cli_find = args[i + 1]
		elif a == "--search" and i + 1 < args.size():
			_cli_search = args[i + 1]
		elif a == "--loose":
			_cli_loose = true
		elif a == "--picker":
			_cli_picker = true
		elif a == "--adopt" and i + 1 < args.size():
			_cli_adopt = int(args[i + 1])
		elif not a.begins_with("--") and _cli_project == "":
			_cli_project = a


func _capture_and_quit() -> void:
	await get_tree().process_frame
	# Let the camera settle and the near-focus cards finish loading text.
	for i in _shot_wait:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shot_path)
	get_tree().quit()


func _make_font(bold: bool) -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"JetBrains Mono", "SF Mono", "Menlo", "DejaVu Sans Mono", "Consolas", "monospace",
	])
	f.font_weight = 700 if bold else 400
	return f


## macOS translucency (§ Theme). Under GL Compatibility a transparent viewport
## clears alpha to ZERO regardless of the clear colour's alpha — so the window
## would be fully see-through. The backdrop is therefore painted explicitly, on a
## layer beneath everything, at the opacity we actually want.
func _build_backdrop() -> void:
	get_viewport().transparent_bg = true
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 0))

	var layer := CanvasLayer.new()
	layer.layer = -100
	add_child(layer)

	var rect := ColorRect.new()
	rect.color = Palette.canvas_color()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)


## Toolbar on top, connections on the right, context pill at the bottom. The
## canvas keeps every piece of state; these only display it and report clicks.
func _build_chrome() -> void:
	_toolbar = Toolbar.new(_font, _bold)
	add_child(_toolbar)
	_toolbar.action.connect(_on_action)

	_pill = ContextPill.new(_font, _bold)
	add_child(_pill)
	_pill.action.connect(_on_action)

	_conn = ConnectionsPanel.new(_font, _bold)
	add_child(_conn)
	_conn.edge_hovered.connect(_on_edge_hovered)
	_conn.edge_clicked.connect(select_coupling)
	_conn.edge_go.connect(_on_edge_go)
	_conn.edge_adopt.connect(func(idx: int) -> void:
		select_coupling(idx)
		adopt_selected())
	_conn.twine_hovered.connect(func(id: String) -> void:
		hover_link_id = id
		_twine.queue_redraw())
	_conn.twine_clicked.connect(select_twine)
	_conn.twine_go.connect(func(idx: int) -> void:
		select_twine(idx)
		follow_twine())
	_conn.twine_delete.connect(_delete_link)
	_conn.lines_mode_chosen.connect(set_lines_mode)
	_conn.close_requested.connect(toggle_connections)

	var ui: Dictionary = _read_session().get("ui", {})
	lines_mode = clampi(int(ui.get("lines", Lines.POINTED)), 0, 2) as Lines
	reduce_motion = bool(ui.get("reduce_motion", false))
	_conn.visible = bool(ui.get("connections", true))
	_conn.set_lines_mode(lines_mode)


## Read / Skim / Map are about the focused card, so they bring the camera back
## to it from overview or a framed coupling rather than zooming those in place.
func _zoom_to_mode(z: float) -> void:
	if blast_on:
		end_blast()
	elif _overview:
		end_overview()
	elif _framing:
		_framing = false
		adopt_idx = -1
		_apply_focus()
	set_zoom(z)


## Every button in the chrome lands here, so a button and its key share one path.
func _on_action(name: String) -> void:
	if cards.is_empty() and name not in ["open", "help"]:
		return
	match name:
		"prev_file": step_col(-1)
		"next_file": step_col(1)
		"folder_up": hop_row(-1)
		"folder_down": hop_row(1)
		"back": history_step(-1)
		"forward": history_step(1)
		"finder": open_finder()
		"search": open_search()
		"zoom_out": zoom_by(1.0 / ZOOM_STEP)
		"zoom_in": zoom_by(ZOOM_STEP)
		"read": _zoom_to_mode(1.0)
		"skim": _zoom_to_mode(0.38)
		"map": _zoom_to_mode(0.16)
		"overview": toggle_overview()
		"blast": toggle_blast()
		"blast_1": set_blast_depth(1)
		"blast_2": set_blast_depth(2)
		"blast_3": set_blast_depth(3)
		"connections": toggle_connections()
		"loose": open_loose_ends()
		"refresh": refresh_all()
		"open": open_project_picker()
		"help": _legend.toggle()
		"escape": back_out()
		"coupling_prev": cycle_adopt(-1)
		"coupling_next": cycle_adopt(1)
		"adopt": adopt_selected()
		"twine_prev": cycle_twine(-1)
		"twine_next": cycle_twine(1)
		"follow": follow_twine()
		"delete":
			if selected_link_id != "":
				_delete_link(selected_link_id)
	_refresh_chrome()


# ---------------------------------------------------------------- project open

## `cancellable` is false only at startup, where there is nothing to fall back to.
func browse_for_project(cancellable: bool) -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.title = "Open a Godot project to read"
	dlg.size = Vector2i(900, 620)
	if project_root != "":
		dlg.current_dir = project_root.get_base_dir()
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)
	layer.add_child(dlg)

	dlg.dir_selected.connect(func(d: String) -> void:
		if ProjectScanner.is_project_root(d):
			layer.queue_free()
			switch_project(d)
		else:
			dlg.title = "No project.godot there — pick a project root"
	)
	dlg.canceled.connect(func() -> void:
		layer.queue_free()
		if not cancellable:
			get_tree().quit()
	)
	dlg.popup_centered()


func open_project_picker() -> void:
	_picker.open(recent_projects(), project_root)


## Swap the canvas to another project. One project at a time (§1), so this tears
## the old one down rather than adding to it — but the old one's position is
## saved first, and restored if you come back.
func switch_project(root_abs: String) -> void:
	if root_abs == project_root:
		return
	save_session()
	open_project(root_abs)


func open_project(root_abs: String) -> void:
	project_root = root_abs
	for row in cards:
		for c in row:
			c.queue_free()
	cards.clear()

	# Everything below is about the previous project and must not leak into this
	# one: stale history would jump to cards that no longer exist.
	_column_memory.clear()
	_history.clear()
	_hist_idx = -1
	_cycle.clear()
	_cycle_idx = -1
	selected_link_id = ""
	adopt_idx = -1
	_framing = false
	_clear_peek_marks()

	rows = ProjectScanner.scan(root_abs)
	_overview = false
	_conn_key = ""
	if rows.is_empty():
		_pill.present("No .gd files found in %s" % root_abs, Palette.TWINE_BROKEN,
			[["Open another…", "Open a different project  ·  " + UIKit.mod("O"), "open"]])
		return

	autoloads = Autoloads.scan(root_abs)
	_build_index()
	inferred = Analyzer.build(index, autoloads)
	store.load_from(root_abs)
	_layout()
	_loose_n = loose_end_entries().size()
	# §3.5 — first open lands at Read zoom on the first file of the root row.
	focus_row = 0
	focus_col = 0
	_restore_session(root_abs)
	if _cli_focus.x >= 0 or _cli_zoom > 0.0:
		if _cli_focus.x >= 0:
			focus_row = clampi(_cli_focus.x, 0, rows.size() - 1)
			focus_col = clampi(_cli_focus.y, 0, cards[focus_row].size() - 1)
		if _cli_zoom > 0.0:
			set_zoom(_cli_zoom, true)
	_apply_focus(true)
	save_session()


## One pass over every .gd at open. Cards still lazy-load their TEXT, but anchors
## and inferred edges need symbol lines for files that will never be on screen.
func _build_index() -> void:
	index.clear()
	inferred.clear()
	for row in rows:
		var files: Array = row["files"]
		for entry in files:
			var key := "res://" + str(entry["rel_path"])
			var f := FileAccess.open(entry["abs_path"], FileAccess.READ)
			if f == null:
				continue
			var parsed := GDParser.parse(f.get_as_text())
			f.close()
			var syms := {}
			var ordered: Array = []
			for s in parsed["symbols"]:
				var name_key: String = "%s %s" % [s["kind"], s["name"]]
				syms[name_key] = s["line"]
				ordered.append(name_key)
			# The whole parse is kept: the analyser (§10) needs the coupling
			# evidence, not just the symbol positions.
			parsed["symbols_by_name"] = syms
			parsed["ordered"] = ordered
			index[key] = parsed


func _layout() -> void:
	for r in rows.size():
		var row: Dictionary = rows[r]
		var files: Array = row["files"]
		var row_cards: Array = []
		var y := r * (Card.H + ROW_GAP)
		var x0: float = float(row["depth"]) * INDENT
		for c in files.size():
			var entry: Dictionary = files[c]
			var card := Card.new()
			card.setup(entry, _font, _bold)
			card.file_key = "res://" + str(entry["rel_path"])
			# Hit-testing happens in world space on the canvas so a single press
			# can mean either "focus this card" or "start drawing twine".
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var idx: Dictionary = index.get(card.file_key, {})
			card.symbols = idx.get("symbols_by_name", {})
			card.reach = Analyzer.reach_score(idx)
			card.ordered = idx.get("ordered", [])
			card.total_lines = idx.get("line_count", 0)
			card.extends_name = idx.get("extends_name", "")
			card.position = Vector2(x0 + c * (Card.W + COL_GAP), y)
			add_child(card)
			row_cards.append(card)
		cards.append(row_cards)


# ---------------------------------------------------------------- focus/camera

## World-space attachment point for one end of a twine, plus its §5.1 state.
## Which edge it leaves from depends on where the other card sits.
func resolve_anchor(file_key: String, symbol: String, partner_key := "") -> Dictionary:
	var card := card_for(file_key)
	if card == null:
		return {}
	var info := card.anchor_info(symbol)
	# The edge is chosen relative to the twine's OTHER end, not to focus —
	# otherwise a link to a card on the left exits right and drags string across
	# the page you are trying to read.
	var edge_x: float = Card.W
	var partner := card_for(partner_key)
	if partner != null and partner != card and partner.position.x < card.position.x:
		edge_x = 0.0
	return {
		"pos": card.position + Vector2(edge_x, info["y"]),
		"state": info["state"],
		"card": card,
	}


func card_for(file_key: String) -> Card:
	for row in cards:
		for card in row:
			if card.file_key == file_key:
				return card
	return null


func cell_for(file_key: String) -> Vector2i:
	for r in cards.size():
		var row_cards: Array = cards[r]
		for c in row_cards.size():
			if row_cards[c].file_key == file_key:
				return Vector2i(r, c)
	return Vector2i(-1, -1)


func card_at_world(p: Vector2) -> Card:
	for row in cards:
		for card in row:
			if Rect2(card.position, Vector2(Card.W, Card.H)).has_point(p):
				return card
	return null


## World→screen factor, for anything that must stay a constant size on screen.
func px_scale() -> float:
	return _cam.zoom.x if _cam != null else 1.0


func is_point_visible(p: Vector2) -> bool:
	var half := get_viewport_rect().size * 0.5 / _cam.zoom
	return Rect2(_cam.position - half, half * 2.0).grow(80.0).has_point(p)


func symbols_of(file_key: String) -> Array:
	var idx: Dictionary = index.get(file_key, {})
	return idx.get("ordered", [])


func focused_card() -> Card:
	if cards.is_empty():
		return null
	return cards[focus_row][focus_col]


func _apply_focus(snap := false) -> void:
	_column_memory[focus_row] = focus_col

	for r in cards.size():
		var row_cards: Array = cards[r]
		for c in row_cards.size():
			var card: Card = row_cards[c]
			var is_focus: bool = r == focus_row and c == focus_col
			card.focused = is_focus
			# Unfocused cards are dimmed and lowered in contrast; no blur,
			# which is expensive under GL Compatibility (§3.4).
			card.modulate = _tint_for(card, is_focus)

			# Only Read zoom needs file text at all; Skim and Map render from
			# the symbol index, so zooming out frees every card's text (§4).
			var near: bool = detail == Card.Detail.READ \
				and absi(r - focus_row) <= 1 and absi(c - focus_col) <= LIVE_RADIUS
			if near:
				card.load_text()
			else:
				card.unload_text()
			card.queue_redraw()

	var card2 := focused_card()
	# While framing a coupling the camera belongs to the pair, not to focus.
	if not _framing:
		_cam_target = card2.position + Vector2(Card.W, Card.H) * 0.5
	if snap:
		_cam.position = _cam_target + _chrome_offset() / px_scale()
	_rebuild_cycle()
	# Only a real focus CHANGE clears the coupling selection. _apply_focus also
	# runs when zoom crosses a detail breakpoint, and framing a coupling does
	# exactly that — so resetting unconditionally cancelled the thing you were
	# cycling through the moment the camera moved to show it.
	var here := Vector2i(focus_row, focus_col)
	if here != _last_focus:
		_last_focus = here
		adopt_idx = -1
		hover_edge_idx = -1
		_framing = false
		# Moving focus by key while in overview lands you, at the zoom you left.
		if _overview:
			_overview = false
			_clear_peek_marks()
			set_zoom(_overview_saved_zoom)
		# In blast radius, stepping to another file re-runs it from there, so you
		# can walk a folder and watch each file's reach.
		if blast_on:
			_run_blast()
	_sync_connections()
	_refresh_chrome()


## Focus is lit and the rest dimmed; in blast radius the rings are lit instead,
## brightest nearest, and each card ignites as its ring arrives.
func _tint_for(card: Card, is_focus: bool) -> Color:
	if not blast_on:
		return Color.WHITE if is_focus else Color(0.62, 0.65, 0.70, 1.0)
	if not blast_hops.has(card.file_key):
		return BLAST_DIM
	var ring: int = blast_hops[card.file_key]
	var lit := Color.WHITE if ring <= 1 else Color.WHITE.darkened(0.1 * (ring - 1))
	return BLAST_DIM.lerp(lit, BlastLayer.reveal(ring, blast_elapsed()))


## Screen pixels to shift the focal point by, so focus centres in the part of
## the window the toolbar and connections panel leave free.
func _chrome_offset() -> Vector2:
	var right := _conn.occupied_width() if _conn != null else 0.0
	return Vector2(right * 0.5, -UIKit.BAR_H * 0.5)


func _refresh_chrome() -> void:
	if cards.is_empty() or _toolbar == null:
		return
	var row: Dictionary = rows[focus_row]
	var card := focused_card()
	var here := Vector2i(focus_row, focus_col)
	_toolbar.refresh({
		"dir": str(row["display"]),
		"file": card.file_name,
		"file_i": focus_col + 1, "file_n": cards[focus_row].size(),
		"row_i": focus_row + 1, "row_n": rows.size(),
		"can_back": _hist_idx > 0 or (_hist_idx == 0 and _history[0] != here),
		"can_fwd": _hist_idx >= 0 and _hist_idx < _history.size() - 1,
		"can_find": card.loaded,
		"detail": detail,
		"zoom_pct": round(zoom_level * 100.0),
		"overview": _overview,
		"blast": blast_on,
		"connections_open": _conn.visible,
		"connections_n": _cycle.size() + inferred_for_focus().size(),
		"loose_n": _loose_n,
	})
	_conn.mark(adopt_idx, _cycle_idx)
	_refresh_pill()


## The pill names whichever temporary state you're in, most specific first.
func _refresh_pill() -> void:
	if _search != null and _search.visible:
		_pill.present("", Color.WHITE, [])
		return
	var esc := ["Back  Esc", "Return to the focused card", "escape"]
	if _notice != "":
		_pill.present(_notice, Palette.HEADING, [])
	elif _peek_stage > 0:
		var sel_card: Card = cards[_peek_sel.x][_peek_sel.y]
		_pill.present("Peeking  ·  release Space to land on %s" % sel_card.file_name,
			Palette.HEADING, [])
	elif blast_on:
		var counts := [0, 0, 0, 0]
		for k in blast_hops:
			counts[blast_hops[k]] += 1
		var text := "Blast radius  ·  nothing in the project depends on %s" % focused_card().file_name
		if blast_hops.size() > 1:
			var parts: Array = ["%d direct" % counts[1]]
			for ring in range(2, blast_depth + 1):
				parts.append("%d at %d hops" % [counts[ring], ring])
			text = "Blast radius  ·  %s  ·  %s" % [focused_card().file_name, "  ·  ".join(parts)]
		var buttons: Array = []
		for d in range(1, 4):
			buttons.append([("▸ " if d == blast_depth else "") + ("%d hop" % d) + ("" if d == 1 else "s"),
				"Show what depends on this file up to %d hop%s away  ·  %d" % [d, "" if d == 1 else "s", d],
				"blast_%d" % d])
		buttons.append(esc)
		_pill.present(text, Palette.blast_color(1), buttons)
	elif _overview:
		_pill.present("Overview  ·  click a card to land there", Palette.HEADING, [esc])
	elif drag_active:
		_pill.present("Release on another card to tie twine between them", Palette.TWINE_SEL, [])
	elif adopt_idx >= 0:
		var candidates := inferred_for_focus()
		var e: Dictionary = candidates[adopt_idx]
		_pill.present("Coupling %d/%d  ·  %s  ·  %s" % [adopt_idx + 1, candidates.size(),
			_far_of(e["from_file"], e["to_file"]).get_file(), Analyzer.describe(e)],
			Palette.ADOPT, [
				["‹", "Previous coupling  ·  Shift+G", "coupling_prev"],
				["›", "Next coupling  ·  G", "coupling_next"],
				["+ Adopt as twine  A", "Turn this into twine and say why", "adopt"],
				esc,
			])
	elif _cycle_idx >= 0:
		var link: Dictionary = _cycle[_cycle_idx]
		var desc := str(link.get("description", "")).strip_edges()
		_pill.present("Twine %d/%d  ·  %s" % [_cycle_idx + 1, _cycle.size(),
			desc if desc != "" else "(unlabelled)"], Palette.TWINE_SEL, [
				["‹", "Previous twine  ·  Shift+Tab", "twine_prev"],
				["›", "Next twine  ·  Tab", "twine_next"],
				["Follow  ↵", "Fly to the other end  ·  Enter", "follow"],
				["Delete  ⌫", "Remove this twine  ·  Delete", "delete"],
				["Done  Esc", "Deselect", "escape"],
			])
	else:
		_pill.present("", Color.WHITE, [])


## The other file of a pair, seen from the focused one.
func _far_of(a: String, b: String) -> String:
	return b if a == focused_card().file_key else a


func _process(delta: float) -> void:
	if cards.is_empty():
		return
	# Focus is always centred, even at a row's end — the dead space is itself a
	# position cue (§3.4).
	_peek_tick()

	if not _fly.is_empty():
		_fly_tick()
	elif not is_equal_approx(zoom_level, _zoom_goal):
		zoom_level = lerpf(zoom_level, _zoom_goal, clampf(delta * ZOOM_EASE, 0.0, 1.0))
		if absf(zoom_level - _zoom_goal) < 0.002:
			zoom_level = _zoom_goal
		_sync_detail()

	var vp := get_viewport_rect().size
	# 100% zoom is defined by the card filling the viewport vertically (§2.3).
	var z := (vp.y * 0.90) / Card.H * zoom_level
	_cam.zoom = Vector2(z, z)
	var goal := _cam_target + _chrome_offset() / z
	if _fly.is_empty():
		_cam.position = _cam.position.lerp(goal, clampf(delta * CAM_EASE, 0.0, 1.0))
	else:
		_cam.position = _fly_centre() + _chrome_offset() / z
	# Cards size their Skim/Map text against this, so a change has to repaint
	# them — otherwise they keep text sized for the previous zoom.
	if not is_equal_approx(z, _last_px):
		_last_px = z
		for row in cards:
			for card in row:
				card.px_scale = z
				card.queue_redraw()
	_process_drag()
	_tick_blast()
	if _notice != "" and Time.get_ticks_msec() > _notice_until:
		_notice = ""
		_refresh_pill()
	queue_redraw()
	# Twine anchors follow the camera, the focused card's scroll and the drag, so
	# the layer repaints every frame rather than trying to track each of those.
	if _twine != null:
		_twine.queue_redraw()


func _draw() -> void:
	# Row gutters + folder labels (§2.2). Depth is indent plus gutter weight.
	for r in rows.size():
		var row: Dictionary = rows[r]
		var y := r * (Card.H + ROW_GAP)
		var x0: float = float(row["depth"]) * INDENT
		var on: bool = r == focus_row
		var label: String = row["display"]
		draw_rect(Rect2(Vector2(x0 - 46.0, y), Vector2(6.0, Card.H)),
			Palette.ROW_LABEL_ON if on else Palette.ROW_GUTTER)
		# Folder bands have to stay readable at Map zoom, so the label is sized
		# to a target pixel height rather than a fixed world size (§4) — but never
		# taller than the gap it lives in, or it prints over the row above.
		var lsize := int(clampf(17.0 / maxf(_cam.zoom.x, 0.0001), 30.0, ROW_GAP * 0.8))
		draw_string(_bold, Vector2(x0 - 40.0, y - lsize * 0.3), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, lsize,
			Palette.ROW_LABEL_ON if on else Palette.ROW_LABEL)


# ---------------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if cards.is_empty():
		return

	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_WHEEL_DOWN:
					if event.ctrl_pressed or event.meta_pressed:
						zoom_by(1.0 / ZOOM_STEP)
					elif event.shift_pressed:
						hop_row(1)          # §3.2 folder hop
					else:
						_scroll_focused(SCROLL_LINES)
				MOUSE_BUTTON_WHEEL_UP:
					if event.ctrl_pressed or event.meta_pressed:
						zoom_by(ZOOM_STEP)
					elif event.shift_pressed:
						hop_row(-1)
					else:
						_scroll_focused(-SCROLL_LINES)
				MOUSE_BUTTON_LEFT:
					_on_press(get_global_mouse_position())
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_on_release(get_global_mouse_position())
		return

	if event is InputEventMouseMotion:
		if _selecting and _sel_card != null:
			var local := get_global_mouse_position() - _sel_card.position
			_sel_card.set_selection(_sel_card.sel_a, _sel_card.pos_at_local(local))
			return
		if drag_active:
			drag_to_pos = get_global_mouse_position()
			_twine.queue_redraw()
			return
		if _peek_stage > 0 or _overview or blast_on:
			var over := card_at_world(get_global_mouse_position())
			if over != null:
				var cell := cell_for(over.file_key)
				if cell.x >= 0 and cell != _peek_sel:
					_peek_sel = cell
					_mark_peek()
			return

	# These run their own input handling while open.
	if _finder != null and _finder.visible:
		return
	if _loose != null and _loose.visible:
		return
	if _picker != null and _picker.visible:
		return
	if _search != null and _search.visible and event is InputEventKey:
		return

	# The legend is modal: while it's up, the only keys that do anything are the
	# ones that dismiss it.
	if _legend != null and _legend.visible:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode in [KEY_ESCAPE, KEY_F1, KEY_SLASH, KEY_QUESTION]:
				_legend.toggle()
		return

	if event is InputEventKey and not event.pressed and event.keycode == KEY_SPACE:
		peek_release()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_F1, KEY_QUESTION] \
				or (event.keycode == KEY_SLASH and event.shift_pressed):
			_legend.toggle()
			return

		if event.keycode == KEY_SPACE:
			peek_press()
			return

		# While peeking, the arrows move the selection instead of focus (§3.6).
		if _peek_stage > 0:
			match event.keycode:
				KEY_LEFT, KEY_H:
					peek_move(0, -1)
				KEY_RIGHT, KEY_L:
					peek_move(0, 1)
				KEY_UP, KEY_K:
					peek_move(-1, 0)
				KEY_DOWN, KEY_J:
					peek_move(1, 0)
			return

		# Alt+arrows walk history (§3.8) and must be checked before the plain
		# arrow bindings below, which would otherwise swallow them.
		if event.alt_pressed and event.keycode in [KEY_LEFT, KEY_RIGHT]:
			history_step(-1 if event.keycode == KEY_LEFT else 1)
			return

		# Chords first, for the same reason: `match` takes the first arm that fits,
		# so a plain KEY_L arm above a Ctrl+L one would step a file instead.
		if event.ctrl_pressed or event.meta_pressed:
			match event.keycode:
				KEY_E:
					set_lines_mode(wrapi(lines_mode + 1, 0, 3))
				KEY_M:
					# Shift only: Cmd+M alone minimises the window on macOS.
					if event.shift_pressed:
						toggle_reduce_motion()
				KEY_O:
					open_project_picker()
				KEY_P:
					open_finder()
				KEY_F:
					open_search()
				KEY_L:
					open_loose_ends()
				KEY_C:
					copy_selection()
				KEY_Q:
					save_session()
					get_tree().quit()
			return

		match event.keycode:
			KEY_L, KEY_RIGHT:
				step_col(1)
			KEY_H, KEY_LEFT:
				step_col(-1)
			KEY_J, KEY_DOWN:
				if event.shift_pressed:
					hop_row(1)
				else:
					_scroll_focused(SCROLL_LINES)
			KEY_K, KEY_UP:
				if event.shift_pressed:
					hop_row(-1)
				else:
					_scroll_focused(-SCROLL_LINES)
			KEY_TAB:
				cycle_twine(-1 if event.shift_pressed else 1)
			KEY_ENTER, KEY_KP_ENTER:
				follow_twine()
			KEY_DELETE, KEY_BACKSPACE:
				if selected_link_id != "":
					_delete_link(selected_link_id)
			KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
				zoom_by(ZOOM_STEP)
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_by(1.0 / ZOOM_STEP)
			KEY_0, KEY_KP_0:
				set_zoom(1.0)
			KEY_C:
				toggle_connections()
			KEY_M:
				toggle_overview()
			KEY_B:
				toggle_blast()
			KEY_1, KEY_2, KEY_3:
				if blast_on:
					set_blast_depth(event.keycode - KEY_0)
			KEY_G:
				cycle_adopt(-1 if event.shift_pressed else 1)
			KEY_A:
				adopt_selected()
			KEY_R:
				refresh_all()
			KEY_ESCAPE:
				back_out()


# ----------------------------------------------------------------- twine drag

const DRAG_THRESHOLD := 26.0     # below this, a press is a click, not a drag


func _on_press(world: Vector2) -> void:
	_press_world = world
	_press_card = card_at_world(world)

	# Alt-drag selects text; plain drag draws twine, because twine is the app's
	# defining act and gets the unmodified gesture (§8).
	if _press_card != null and Input.is_key_pressed(KEY_ALT) \
			and _press_card.detail == Card.Detail.READ and _press_card.loaded:
		_clear_selection_everywhere()
		_selecting = true
		_sel_card = _press_card
		var local := world - _sel_card.position
		_sel_card.set_selection(_sel_card.pos_at_local(local), _sel_card.pos_at_local(local))
		return

	if _press_card == null:
		selected_link_id = ""
		_twine.queue_redraw()
		return
	# Plain drag draws twine — it's the app's defining act, so it gets the
	# unmodified gesture (§5.2). Alt is reserved for text selection (§8).
	_drag_card = _press_card
	_drag_symbol = _press_card.symbol_at_local_y(world.y - _press_card.position.y)
	drag_from_pos = world
	drag_to_pos = world


func _on_release(world: Vector2) -> void:
	if _selecting:
		_selecting = false
		_sel_card = null
		_press_card = null
		return

	var moved := _press_world.distance_to(world)

	if drag_active:
		drag_active = false
		var target := card_at_world(world)
		if target != null and _drag_card != null:
			_open_link_dialog(_drag_card, target)
		_drag_card = null
		_twine.queue_redraw()
		_refresh_pill()
		return

	if _press_card != null and moved < DRAG_THRESHOLD:
		var cell := cell_for(_press_card.file_key)
		if cell.x >= 0:
			if blast_on:
				end_blast(cell)
			elif _overview:
				end_overview(cell)
			else:
				_jump_to(cell)

	_drag_card = null
	_press_card = null


func _process_drag() -> void:
	if _drag_card != null and not drag_active:
		if _press_world.distance_to(get_global_mouse_position()) >= DRAG_THRESHOLD \
				and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			drag_active = true
			drag_to_pos = get_global_mouse_position()
			_refresh_pill()


func _open_link_dialog(from_card: Card, to_card: Card) -> void:
	_pending_from = from_card.file_key
	_pending_to = to_card.file_key
	_dialog.open_for(
		from_card.file_key, symbols_of(from_card.file_key), _drag_symbol,
		to_card.file_key, symbols_of(to_card.file_key),
	)


func _on_link_confirmed(from_symbol: String, to_symbol: String, description: String) -> void:
	var link := store.add(_pending_from, from_symbol, _pending_to, to_symbol, description)
	_links_changed()
	selected_link_id = link["id"]
	_twine.tie(link["id"])
	for i in _cycle.size():
		if _cycle[i]["id"] == link["id"]:
			_cycle_idx = i
	_refresh_chrome()


# --------------------------------------------------------- twine as navigation

## Tab cycles the focused file's twines; Enter flies to the far end (§5.5).
func _rebuild_cycle() -> void:
	var card := focused_card()
	if card == null:
		return
	_cycle = store.links_touching(card.file_key)
	_cycle_idx = -1


func cycle_twine(dir: int) -> void:
	if _cycle.is_empty():
		return
	_cycle_idx = wrapi(_cycle_idx + dir, 0, _cycle.size())
	selected_link_id = _cycle[_cycle_idx]["id"]
	_twine.queue_redraw()
	_refresh_chrome()


func follow_twine() -> void:
	if _cycle_idx < 0 or _cycle_idx >= _cycle.size():
		return
	var link: Dictionary = _cycle[_cycle_idx]
	var here := focused_card().file_key
	var far: String = link["to"]["file"] if link["from"]["file"] == here else link["from"]["file"]
	var cell := cell_for(far)
	if cell.x < 0:
		return
	_jump_to(cell)
	# Bring the anchored line into view so the twine lands where it points.
	var far_sym: String = link["to"]["symbol"] if link["from"]["file"] == here \
		else link["from"]["symbol"]
	var card := focused_card()
	if far_sym != "" and card.symbols.has(far_sym):
		card.scroll_line = clampf(float(card.symbols[far_sym]) - 6.0, 0.0, card.max_scroll())
		card.queue_redraw()


# ------------------------------------------------------------------- history

## Every discrete jump goes through here, recording both ends so Back returns to
## where you were and Forward to where you went (§3.9).
func _jump_to(cell: Vector2i) -> void:
	var from := _focal_point()
	var from_zoom := zoom_level
	_push_history()
	focus_row = cell.x
	focus_col = cell.y
	_push_history()
	_apply_focus()
	_begin_fly(from, from_zoom)


# -------------------------------------------------------------------- fly-to

## The world point currently at the focal centre — where a flight starts from.
func _focal_point() -> Vector2:
	return _cam.position - _chrome_offset() / px_scale()


## Starts a flight from `from` at `from_zoom` to wherever focus now points.
##
## The path is a dip in log-zoom: out to the zoom that fits both ends on screen,
## then back in. Panning happens mostly while zoomed out, so the trip reads as
## one move across the map rather than a long smear of code.
##
## The flight reads its destination and final zoom LIVE every frame, so a
## framing, peek or zoom that retargets mid-flight bends the path rather than
## fighting it.
func _begin_fly(from: Vector2, from_zoom: float) -> void:
	var vp := get_viewport_rect().size
	var read_screen_w := vp.x / ((vp.y * 0.90) / Card.H)
	var screens := from.distance_to(_cam_target) / read_screen_w
	if screens < FLY_MIN_SCREENS:
		return
	var card := Vector2(Card.W, Card.H)
	var bounds := Rect2(from - card * 0.5, card).merge(Rect2(_cam_target - card * 0.5, card))
	var out_zoom := _fit_zoom(bounds, FLY_MARGIN)
	var mid := lerpf(log(from_zoom), log(_zoom_goal), 0.5)
	_fly = {
		"t0": Time.get_ticks_msec(),
		"dur": minf(FLY_BASE + FLY_PER_DOUBLING * log(1.0 + screens) / log(2.0), FLY_MAX),
		"from": from,
		"log_z0": log(from_zoom),
		# Only dip if the ends don't already fit — from overview it just glides in.
		"dip": maxf(0.0, mid - log(out_zoom)),
		"t": 0.0,
	}


func _fly_tick() -> void:
	var t: float = (Time.get_ticks_msec() - int(_fly["t0"])) / 1000.0 / float(_fly["dur"])
	if t >= 1.0:
		_fly = {}
		zoom_level = _zoom_goal
		_sync_detail()
		return
	_fly["t"] = t
	var sz := smoothstep(0.0, 1.0, t)
	zoom_level = exp(lerpf(_fly["log_z0"], log(_zoom_goal), sz) - float(_fly["dip"]) * sin(PI * sz))
	_sync_detail()


## Smootherstep: still at both ends, fastest in the middle — where the dip has the
## camera zoomed furthest out, so the fast part of the pan is the legible part.
func _fly_centre() -> Vector2:
	var t: float = _fly["t"]
	var s := t * t * t * (t * (t * 6.0 - 15.0) + 10.0)
	return (_fly["from"] as Vector2).lerp(_cam_target, s)


func _push_history() -> void:
	var entry := Vector2i(focus_row, focus_col)
	if _hist_idx >= 0 and _hist_idx < _history.size() and _history[_hist_idx] == entry:
		return
	_history.resize(_hist_idx + 1)
	_history.append(entry)
	_hist_idx = _history.size() - 1


func history_step(dir: int) -> void:
	# Stepping with H/L doesn't push, so you may have wandered off the entry the
	# cursor points at. Remember that spot first, so Forward can bring you back.
	var here := Vector2i(focus_row, focus_col)
	if dir < 0 and _hist_idx >= 0 and _history[_hist_idx] != here:
		_push_history()
	var next := _hist_idx + dir
	if next < 0 or next >= _history.size():
		return
	_hist_idx = next
	var cell: Vector2i = _history[_hist_idx]
	var from := _focal_point()
	var from_zoom := zoom_level
	focus_row = cell.x
	focus_col = cell.y
	_apply_focus()
	_begin_fly(from, from_zoom)


func _scroll_focused(lines: float) -> void:
	var card := focused_card()
	if card != null:
		card.scroll_by(lines)


# ------------------------------------------------------------- semantic zoom

## Zoom is continuous; the breakpoints change what a card DRAWS, not what it is
## (§4). One camera, one dataset — a twine drawn in Map is the same twine here.
func zoom_by(factor: float) -> void:
	set_zoom(_zoom_goal * factor)


func set_zoom(z: float, snap := false) -> void:
	_zoom_goal = clampf(z, ZOOM_MIN, ZOOM_MAX)
	if snap:
		zoom_level = _zoom_goal
	_sync_detail()


## Zoom is continuous; the breakpoints change what a card DRAWS, not what it is.
func _sync_detail() -> void:
	var next := Card.detail_for_zoom(zoom_level)
	if next != detail:
		detail = next
		_apply_detail()
	_refresh_chrome()


func _apply_detail() -> void:
	for row in cards:
		for card in row:
			card.detail = detail
			card.queue_redraw()
	# Text loading follows the mode, so zooming out releases every card's text.
	_apply_focus()


## A link's position among the focused file's twine, so the layer can stack
## labels that would otherwise all land on the same spot. Returns -1 when the
## link doesn't touch focus.
func label_slot(link_id: String) -> int:
	for i in _cycle.size():
		if _cycle[i].get("id", "") == link_id:
			return i
	return -1


func cycle_count() -> int:
	return _cycle.size()


# ----------------------------------------------------------------------- peek

## Spring-loaded overview (§3.6). Hold to glance, release to land.
##
## A 40-card row needs a way across that isn't 40 keypresses, and full Map is too
## far out to pick a file from — so the first stage fits the CURRENT ROW, and only
## a longer hold opens out to the whole project.
func peek_press() -> void:
	if _peek_down_at >= 0 or _overview or blast_on:
		return
	_peek_down_at = Time.get_ticks_msec()
	_peek_saved_zoom = _zoom_goal
	_peek_sel = Vector2i(focus_row, focus_col)


func peek_release() -> void:
	var was_active := _peek_stage > 0
	_peek_down_at = -1
	_peek_stage = 0
	_peek_bias = 0
	_clear_peek_marks()

	if not was_active:
		return          # a tap does nothing, so taps can't flicker the view

	# Land on whatever was selected. Releasing without moving returns you exactly
	# where you started.
	set_zoom(_peek_saved_zoom)
	if _peek_sel.x >= 0 and _peek_sel != Vector2i(focus_row, focus_col):
		_jump_to(Vector2i(_peek_sel.x, clampi(_peek_sel.y, 0, cards[_peek_sel.x].size() - 1)))
	else:
		_apply_focus()


func peek_move(d_row: int, d_col: int) -> void:
	if _peek_stage == 0:
		return
	var r := clampi(_peek_sel.x + d_row, 0, rows.size() - 1)
	var c := _peek_sel.y
	if d_row != 0:
		c = clampi(c, 0, cards[r].size() - 1)
	else:
		c = clampi(c + d_col, 0, cards[r].size() - 1)
	_peek_sel = Vector2i(r, c)
	_mark_peek()


func _peek_tick() -> void:
	if _peek_down_at < 0 or cards.is_empty():
		return
	var held := Time.get_ticks_msec() - _peek_down_at + _peek_bias
	var stage := 0
	if held >= PEEK_MAP_MS:
		stage = 2
	elif held >= PEEK_TAP_MS:
		stage = 1

	if stage != _peek_stage:
		_peek_stage = stage
		if stage > 0:
			_mark_peek()

	if _peek_stage == 0:
		return

	var bounds := _row_bounds(_peek_sel.x) if _peek_stage == 1 else _project_bounds()
	set_zoom(_fit_zoom(bounds))
	_cam_target = bounds.get_center()


func _mark_peek() -> void:
	for r in cards.size():
		var row_cards: Array = cards[r]
		for c in row_cards.size():
			var card: Card = row_cards[c]
			var sel: bool = r == _peek_sel.x and c == _peek_sel.y
			if card.peek_selected != sel:
				card.peek_selected = sel
				card.queue_redraw()


func _clear_peek_marks() -> void:
	for row in cards:
		for card in row:
			if card.peek_selected:
				card.peek_selected = false
				card.queue_redraw()


func _row_bounds(r: int) -> Rect2:
	var row_cards: Array = cards[clampi(r, 0, cards.size() - 1)]
	var first: Card = row_cards[0]
	var last: Card = row_cards[row_cards.size() - 1]
	return Rect2(first.position, last.position + Vector2(Card.W, Card.H) - first.position)


func _project_bounds() -> Rect2:
	var b := Rect2(cards[0][0].position, Vector2(Card.W, Card.H))
	for row in cards:
		for card in row:
			b = b.merge(Rect2(card.position, Vector2(Card.W, Card.H)))
	return b


## The zoom_level at which `bounds` fits the viewport, with a little air.
func _fit_zoom(bounds: Rect2, margin := PEEK_MARGIN) -> float:
	var vp := get_viewport_rect().size
	var base := (vp.y * 0.90) / Card.H
	# Fit into what the chrome leaves, not the whole window.
	var free := vp - Vector2(_conn.occupied_width(), UIKit.BAR_H)
	var need := minf(free.x / maxf(bounds.size.x * margin, 1.0),
		free.y / maxf(bounds.size.y * margin, 1.0))
	return clampf(need / base, ZOOM_MIN, ZOOM_MAX)


# --------------------------------------------------------------- fuzzy find

func open_finder() -> void:
	var entries: Array = []
	for row in rows:
		var files: Array = row["files"]
		for entry in files:
			entries.append({
				"key": "res://" + str(entry["rel_path"]),
				"name": str(entry["name"]),
				"dir": str(row["display"]),
			})
	_finder.open(entries)


## Inferred edges touching the focused file, strongest first (§10).
func inferred_for_focus() -> Array:
	var card := focused_card()
	if card == null:
		return []
	var out: Array = []
	for e in inferred:
		if e["from_file"] == card.file_key or e["to_file"] == card.file_key:
			out.append(e)
	return out


## Adopt an inferred edge as real twine (§10). The analyser knows THAT two files
## are coupled; only the user knows WHY, so the description is prefilled with the
## evidence and left editable.
func cycle_adopt(dir: int) -> void:
	var candidates := inferred_for_focus()
	if candidates.is_empty():
		return
	select_coupling(wrapi(adopt_idx + dir, 0, candidates.size()))


## Selects one detected coupling by its index in inferred_for_focus() and frames
## the pair. G steps through these; the connections panel picks one directly.
func select_coupling(idx: int) -> void:
	var candidates := inferred_for_focus()
	if idx < 0 or idx >= candidates.size():
		return
	if blast_on:
		end_blast()
	if _overview:
		end_overview()
	if not _framing:
		_frame_saved_zoom = _zoom_goal          # so leaving restores your zoom
	adopt_idx = idx
	selected_link_id = ""
	_cycle_idx = -1
	_frame_edge(candidates[adopt_idx])
	_twine.queue_redraw()
	_refresh_chrome()


## Frames both ends of a coupling WITHOUT changing focus.
##
## Moving focus instead would rebuild the candidate list on every press — the
## list is derived from the focused file — so the thing you were cycling through
## would change under you. The camera moves; focus stays put.
func _frame_edge(edge: Dictionary) -> void:
	var a := card_for(edge["from_file"])
	var b := card_for(edge["to_file"])
	if a == null or b == null:
		return
	var bounds := Rect2(a.position, Vector2(Card.W, Card.H))
	bounds = bounds.merge(Rect2(b.position, Vector2(Card.W, Card.H)))
	_framing = true
	set_zoom(_fit_zoom(bounds, FRAME_MARGIN))
	_cam_target = bounds.get_center()


## Back to the focused card at the zoom you were reading at.
func stop_framing() -> void:
	if not _framing:
		return
	_framing = false
	adopt_idx = -1
	set_zoom(_frame_saved_zoom)
	_apply_focus()
	_twine.queue_redraw()


func adopt_selected() -> void:
	var candidates := inferred_for_focus()
	if adopt_idx < 0 or adopt_idx >= candidates.size():
		return
	var edge: Dictionary = candidates[adopt_idx]
	_framing = false
	_pending_from = edge["from_file"]
	_pending_to = edge["to_file"]
	_dialog.open_for(
		_pending_from, symbols_of(_pending_from), "",
		_pending_to, symbols_of(_pending_to),
	)
	_dialog.preset_description(Analyzer.describe(edge))


func _on_file_picked(file_key: String) -> void:
	var cell := cell_for(file_key)
	if cell.x < 0:
		return
	_jump_to(cell)


# ------------------------------------------------- connections panel (§5.7)

## Rebuilds the panel's rows only when the focused FILE changes (or `force`,
## after twine is added or removed). _apply_focus also runs on zoom breakpoints,
## and rebuilding there would reset the panel's scroll under the pointer.
func _sync_connections(force := false) -> void:
	var card := focused_card()
	if card == null or _conn == null:
		return
	if not force and card.file_key == _conn_key:
		return
	_conn_key = card.file_key

	var twines: Array = []
	for i in _cycle.size():
		var link: Dictionary = _cycle[i]
		var outgoing: bool = link["from"]["file"] == card.file_key
		var here: Dictionary = link["from"] if outgoing else link["to"]
		var far: Dictionary = link["to"] if outgoing else link["from"]
		var a := resolve_anchor(link["from"]["file"], link["from"]["symbol"], link["to"]["file"])
		var b := resolve_anchor(link["to"]["file"], link["to"]["symbol"], link["from"]["file"])
		twines.append({
			"id": link.get("id", ""),
			"idx": i,
			"outgoing": outgoing,
			"far_name": str(far["file"]).get_file(),
			"far_dir": _dir_of(far["file"]),
			"here_sym": _sym_label(here["symbol"]),
			"far_sym": _sym_label(far["symbol"]),
			"desc": link.get("description", ""),
			"broken": a.is_empty() or b.is_empty()
				or a.get("state", "") == "broken" or b.get("state", "") == "broken",
		})

	var edges: Array = []
	var candidates := inferred_for_focus()
	for i in candidates.size():
		var e: Dictionary = candidates[i]
		var outgoing: bool = e["from_file"] == card.file_key
		var far_key: String = e["to_file"] if outgoing else e["from_file"]
		edges.append({
			"idx": i,
			"outgoing": outgoing,
			"far_name": far_key.get_file(),
			"far_dir": _dir_of(far_key),
			"desc": Analyzer.describe(e),
			"weight": e.get("weight", 1.0),
		})
	_conn.show_for(card.file_name, twines, edges)


func _dir_of(file_key: String) -> String:
	var d := file_key.trim_prefix("res://").get_base_dir()
	return "res://" if d == "" else d + "/"


func _sym_label(symbol: String) -> String:
	return "whole file" if symbol == "" else symbol


## Twine was added, removed or relabelled: everything derived from the store.
func _links_changed() -> void:
	_rebuild_cycle()
	_sync_connections(true)
	_loose_n = loose_end_entries().size()
	_twine.queue_redraw()
	_refresh_chrome()


func _delete_link(id: String) -> void:
	store.remove(id)
	if selected_link_id == id:
		selected_link_id = ""
	hover_link_id = ""
	_links_changed()


func select_twine(idx: int) -> void:
	if idx < 0 or idx >= _cycle.size():
		return
	if _framing and not _overview:
		stop_framing()
	_cycle_idx = idx
	selected_link_id = _cycle[idx]["id"]
	_twine.queue_redraw()
	_refresh_chrome()


func _on_edge_hovered(idx: int) -> void:
	hover_edge_idx = idx
	_twine.queue_redraw()


## Focus the far file of a detected coupling, leaving at the zoom you read at.
func _on_edge_go(idx: int) -> void:
	var candidates := inferred_for_focus()
	if idx < 0 or idx >= candidates.size():
		return
	var e: Dictionary = candidates[idx]
	var cell := cell_for(_far_of(e["from_file"], e["to_file"]))
	if cell.x < 0:
		return
	if _framing:
		_framing = false
		set_zoom(_frame_saved_zoom)
	_jump_to(cell)


func set_lines_mode(mode: int) -> void:
	lines_mode = clampi(mode, 0, 2) as Lines
	_conn.set_lines_mode(lines_mode)
	_twine.queue_redraw()
	_save_ui()


func toggle_reduce_motion() -> void:
	reduce_motion = not reduce_motion
	_twine.reduce_motion = reduce_motion
	_save_ui()
	notify("Reduce motion on  ·  twine holds still" if reduce_motion
		else "Reduce motion off  ·  twine sways again")


## Shows `text` in the pill for a moment, over whatever state it would name.
func notify(text: String) -> void:
	_notice = text
	_notice_until = Time.get_ticks_msec() + NOTICE_MS
	_refresh_pill()


func toggle_connections() -> void:
	_conn.visible = not _conn.visible
	hover_edge_idx = -1
	hover_link_id = ""
	_save_ui()
	_refresh_chrome()


# ------------------------------------------------------------------ overview

## Peek's latched sibling, for the mouse: the whole project stays up until you
## click the card you want (§3.6). Holding a key while aiming a pointer is
## awkward; this is the same view without the hold.
func toggle_overview() -> void:
	if _overview:
		end_overview()
		return
	if cards.is_empty() or _peek_stage > 0:
		return
	if blast_on:
		end_blast()
	_overview_saved_zoom = _frame_saved_zoom if _framing else _zoom_goal
	adopt_idx = -1
	_overview = true
	_framing = true                         # the camera belongs to the bounds
	var bounds := _project_bounds()
	set_zoom(_fit_zoom(bounds))
	_cam_target = bounds.get_center()
	_peek_sel = Vector2i(focus_row, focus_col)
	_mark_peek()
	_refresh_chrome()


## Leave overview, landing on `land` if given, at the zoom you came from.
func end_overview(land := Vector2i(-1, -1)) -> void:
	if not _overview:
		return
	_overview = false
	_framing = false
	_clear_peek_marks()
	set_zoom(_overview_saved_zoom)
	if land.x >= 0 and land != Vector2i(focus_row, focus_col):
		_jump_to(land)
	else:
		_apply_focus()


# -------------------------------------------------------------- blast radius

## What might break if you touch this file (§10.6): everything that depends on
## it, ring by ring, with the camera pulled back to show the whole spread.
func toggle_blast() -> void:
	if blast_on:
		end_blast()
		return
	if cards.is_empty() or _peek_stage > 0:
		return
	if _overview:
		end_overview()
	_blast_saved_zoom = _frame_saved_zoom if _framing else _zoom_goal
	blast_on = true
	_run_blast()


func set_blast_depth(depth: int) -> void:
	blast_depth = clampi(depth, 1, 3)
	if blast_on:
		_run_blast()
	_refresh_chrome()


func blast_elapsed() -> float:
	return (Time.get_ticks_msec() - _blast_started) / 1000.0


## Computes the rings from the focused file and restarts the animation.
func _run_blast() -> void:
	var src := focused_card()
	var r := Analyzer.blast(inferred, src.file_key, blast_depth)
	blast_hops = r["hops"]
	blast_parent = r["parent"]
	blast_cards.clear()
	var bounds := Rect2(src.position, Vector2(Card.W, Card.H))
	for key in blast_hops:
		var c := card_for(key)
		if c != null:
			blast_cards[key] = c
			bounds = bounds.merge(Rect2(c.position, Vector2(Card.W, Card.H)))
	_blast_started = Time.get_ticks_msec()
	adopt_idx = -1
	_framing = true                         # the camera belongs to the spread
	# A file nothing depends on stays where it is; there's nothing to show.
	if blast_hops.size() > 1:
		set_zoom(_fit_zoom(bounds, FRAME_MARGIN))
		_cam_target = bounds.get_center()
	_blast.repaint()
	_refresh_chrome()


## While the rings are still igniting, tint and repaint every frame; after,
## only the layer repaints, because the camera may still be easing.
func _tick_blast() -> void:
	if not blast_on:
		return
	if blast_elapsed() < BlastLayer.settle_time(blast_depth):
		for row in cards:
			for card in row:
				card.modulate = _tint_for(card, card.focused)
	_blast.repaint()


## Leave blast radius, landing on `land` if given, at the zoom you came from.
func end_blast(land := Vector2i(-1, -1)) -> void:
	if not blast_on:
		return
	blast_on = false
	blast_hops = {}
	blast_parent = {}
	blast_cards.clear()
	_framing = false
	_clear_peek_marks()
	_blast.repaint()
	set_zoom(_blast_saved_zoom)
	if land.x >= 0 and land != Vector2i(focus_row, focus_col):
		_jump_to(land)
	else:
		_apply_focus()


## Esc backs out of one thing at a time, innermost first. It no longer quits:
## a key you press to dismiss things shouldn't also close the window.
func back_out() -> void:
	if blast_on:
		end_blast()
	elif _overview:
		end_overview()
	elif _framing:
		stop_framing()
	elif _cycle_idx >= 0 or selected_link_id != "":
		_cycle_idx = -1
		selected_link_id = ""
		_twine.queue_redraw()
	_refresh_chrome()


# ------------------------------------------------- find in card (§3.9)

func open_search() -> void:
	var card := focused_card()
	if card == null or not card.loaded:
		return
	_search_saved_scroll = card.scroll_line
	_search.open()
	_refresh_pill()


func _on_search_query(q: String) -> void:
	var card := focused_card()
	if card == null:
		return
	var total := card.run_search(q)
	if total > 0:
		card.step_search(0)
	_search.set_count(total, card.search_current)


func _on_search_step(dir: int) -> void:
	var card := focused_card()
	if card == null:
		return
	card.step_search(dir)
	_search.set_count(card.search_hits.size(), card.search_current)


## Esc restores the scroll position you had before searching (§3.9).
func _on_search_closed() -> void:
	var card := focused_card()
	if card == null:
		return
	card.clear_search()
	card.scroll_line = clampf(_search_saved_scroll, 0.0, card.max_scroll())
	card.queue_redraw()
	_refresh_pill()


# ------------------------------------------------- selection (§8)

func copy_selection() -> void:
	for row in cards:
		for card in row:
			if card.has_selection():
				DisplayServer.clipboard_set(card.selected_text())
				return


func _clear_selection_everywhere() -> void:
	for row in cards:
		for card in row:
			card.clear_selection()


# ------------------------------------------------- loose ends (§5.6)

## Undescribed and broken twine share one surface: both are things left
## unfinished, and both want the same three actions.
func loose_end_entries() -> Array:
	var out: Array = []
	for link in store.links:
		var from_file: String = link["from"]["file"]
		var to_file: String = link["to"]["file"]
		var a: Dictionary = resolve_anchor(from_file, link["from"]["symbol"], to_file)
		var b: Dictionary = resolve_anchor(to_file, link["to"]["symbol"], from_file)
		var broken: bool = a.is_empty() or b.is_empty() \
			or a.get("state", "") == "broken" or b.get("state", "") == "broken"
		var described: bool = str(link.get("description", "")).strip_edges() != ""

		if not broken and described:
			continue

		var label := "%s %s  →  %s %s" % [
			from_file.get_file(), link["from"]["symbol"],
			to_file.get_file(), link["to"]["symbol"],
		]
		if broken:
			var missing := from_file if (a.is_empty() or a.get("state", "") == "broken") else to_file
			out.append({
				"id": link.get("id", ""),
				"kind": "broken",
				"badge": "✕ broken",
				"text": "%s     (%s no longer resolves)" % [label, missing.get_file()],
			})
		else:
			out.append({
				"id": link.get("id", ""),
				"kind": "unlabelled",
				"badge": "◌ unlabelled",
				"text": label,
			})
	return out


func open_loose_ends() -> void:
	_loose.open(loose_end_entries())


func _link_by_id(id: String) -> Dictionary:
	for link in store.links:
		if link.get("id", "") == id:
			return link
	return {}


func _on_loose_jump(id: String) -> void:
	var link := _link_by_id(id)
	if link.is_empty():
		return
	var cell := cell_for(link["from"]["file"])
	if cell.x < 0:
		cell = cell_for(link["to"]["file"])
	if cell.x < 0:
		return
	_jump_to(cell)
	selected_link_id = id


func _on_loose_described(id: String, text: String) -> void:
	var link := _link_by_id(id)
	if link.is_empty():
		return
	link["description"] = text
	store.save()
	_links_changed()
	_loose.open(loose_end_entries())


func _on_loose_removed(id: String) -> void:
	_delete_link(id)
	_loose.open(loose_end_entries())


func detail_name() -> String:
	match detail:
		Card.Detail.SKIM:
			return "Skim"
		Card.Detail.MAP:
			return "Map"
	return "Read"


func step_col(dir: int) -> void:
	_framing = false
	var count: int = cards[focus_row].size()
	focus_col = clampi(focus_col + dir, 0, count - 1)
	_apply_focus()


## Each folder remembers the last file focused in it (§3.3) — hop away and back
## and you land where you left, not at column 0.
func hop_row(dir: int) -> void:
	_framing = false
	var next := clampi(focus_row + dir, 0, rows.size() - 1)
	if next == focus_row:
		return
	_column_memory[focus_row] = focus_col
	focus_row = next
	focus_col = _column_memory.get(focus_row, 0)
	focus_col = clampi(focus_col, 0, cards[focus_row].size() - 1)
	_apply_focus()


## Re-scan on demand; window focus-gain wiring comes with §6.1 proper.
func refresh_all() -> void:
	for row in cards:
		for card in row:
			if card.loaded:
				card.refresh_from_disk()


# --------------------------------------------------------------- session state

## Two stores, deliberately split (§6). Annotation lives in the target project's
## .gdreader/links.json; where YOU were lives here, private and uncommitted.
##
##   { recents: [path], sessions: { path: {focus_row, focus_col, zoom, columns} } }

func _session_file() -> String:
	return "user://gdreader_session.json"


func _read_session() -> Dictionary:
	if not FileAccess.file_exists(_session_file()):
		return {"recents": [], "sessions": {}}
	var f := FileAccess.open(_session_file(), FileAccess.READ)
	if f == null:
		return {"recents": [], "sessions": {}}
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		var d: Dictionary = data
		if not d.has("recents"):
			d["recents"] = []
		if not d.has("sessions"):
			d["sessions"] = {}
		# Migration: the first version stored a single "project_root". Carry it
		# into recents so upgrading doesn't lose the project you had open.
		var legacy: String = str(d.get("project_root", ""))
		if legacy != "" and not d["recents"].has(legacy):
			d["recents"].push_front(legacy)
		return d
	return {"recents": [], "sessions": {}}


func _write_session(data: Dictionary) -> void:
	var f := FileAccess.open(_session_file(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))
		f.close()


func recent_projects() -> Array:
	var out: Array = []
	for p in _read_session()["recents"]:
		if DirAccess.dir_exists_absolute(str(p)):
			out.append(str(p))
	return out


## Remembers the project and where you were in it, so switching away and back
## lands you on the same card at the same zoom.
func save_session() -> void:
	if project_root == "":
		return
	var data := _read_session()

	var recents: Array = data["recents"]
	recents.erase(project_root)
	recents.push_front(project_root)
	if recents.size() > MAX_RECENTS:
		recents.resize(MAX_RECENTS)
	data["recents"] = recents

	var columns := {}
	for r in _column_memory:
		columns[str(r)] = _column_memory[r]
	data["sessions"][project_root] = {
		"focus_row": focus_row,
		"focus_col": focus_col,
		"zoom": _zoom_goal,
		"columns": columns,
	}
	data["ui"] = _ui_prefs()
	_write_session(data)


## Panel and line preferences belong to the reader, not to a project.
func _ui_prefs() -> Dictionary:
	return {"connections": _conn.visible, "lines": int(lines_mode), "reduce_motion": reduce_motion}


func _save_ui() -> void:
	var data := _read_session()
	data["ui"] = _ui_prefs()
	_write_session(data)


func _restore_session(root_abs: String) -> void:
	var sessions: Dictionary = _read_session()["sessions"]
	if not sessions.has(root_abs):
		return
	var st: Dictionary = sessions[root_abs]

	_column_memory.clear()
	for k in st.get("columns", {}):
		_column_memory[int(k)] = int(st["columns"][k])

	focus_row = clampi(int(st.get("focus_row", 0)), 0, rows.size() - 1)
	focus_col = clampi(int(st.get("focus_col", 0)), 0, cards[focus_row].size() - 1)
	set_zoom(float(st.get("zoom", 1.0)), true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_session()
