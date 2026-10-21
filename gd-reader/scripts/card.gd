class_name Card
extends Control

## One .gd file as a fixed letter-paper rectangle (§2.3).
##
## The card never resizes to its content and never paginates — the file scrolls
## inside a fixed viewport. No scrollbars (§2.3): position is read from the header
## line-range, the edge fades, and a hairline tick that fades after scrolling stops.
##
## Three detail modes (§4). Skim and Map render from the SYMBOL INDEX rather than
## from file text, so they cost nothing for cards that were never loaded — which
## is every card but a handful once you zoom out.

enum Detail { READ, SKIM, MAP }

## Semantic zoom breakpoints (§4). Pure, so it can be tested without a viewport.
const SKIM_AT := 0.50
const MAP_AT := 0.25

static func detail_for_zoom(z: float) -> Detail:
	if z < MAP_AT:
		return Detail.MAP
	if z < SKIM_AT:
		return Detail.SKIM
	return Detail.READ

const W := 850.0                 # 8.5:11 portrait, in world units
const H := 1100.0
const PAD := 28.0
const HEADER_H := 64.0
const FONT_SIZE := 16
const LINE_H := 23.0
const TAB_SPACES := "    "
const TICK_FADE_DELAY := 0.6     # 🎚 §2.3
const FADE_BAND := 26.0

var file_name := ""
var abs_path := ""
var rel_path := ""

var lines: PackedStringArray = []
var parsed: Dictionary = {}
var loaded := false

## Populated once at project open from the shared symbol index, so anchors resolve
## for cards whose text is not loaded — which is most of them, most of the time.
var file_key := ""               # "res://player/player.gd"
var total_lines := 0
var symbols: Dictionary = {}     # "func take_damage" -> line
var ordered: Array = []          # same keys, in source order
var extends_name := ""
var reach := 0                   # §10 — how hard this file grabs outside itself

var scroll_line := 0.0
var focused := false

## Text selection (§8) and find-in-card (§3.9), both in (line, column) space —
## which is exact here because lines are never wrapped (§2.4).
var sel_a := Vector2i(-1, -1)
var sel_b := Vector2i(-1, -1)
var search_query := ""
var search_hits: Array = []      # [Vector2i(line, col)]
var search_current := -1
var detail := Detail.READ
var peek_selected := false
var px_scale := 1.0              # world→screen factor, for legibility compensation

var _font: Font
var _bold: Font
var _char_w := 9.6
var _ascent := 12.0
var _tick_alpha := 0.0
var _tick_timer := 0.0


func setup(entry: Dictionary, font: Font, bold: Font) -> void:
	file_name = entry["name"]
	abs_path = entry["abs_path"]
	rel_path = entry["rel_path"]
	_font = font
	_bold = bold
	# Measure over a run of glyphs, not one: a single-char measurement rounds up
	# just enough that each drawn run drifts off the column grid and leaves gaps.
	_char_w = _font.get_string_size("0123456789", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x / 10.0
	_ascent = _font.get_ascent(FONT_SIZE)
	size = Vector2(W, H)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func load_text() -> void:
	if loaded:
		return
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		lines = PackedStringArray(["# unreadable: %s" % abs_path])
		loaded = true
		return
	var text := f.get_as_text()
	f.close()
	parsed = GDParser.parse(text)
	# Tabs are expanded once, at load. A tab's glyph advance is not char_w, so
	# leaving them in would break both the column grid and the visible structure
	# of the indentation — which is most of what you read a script's shape from.
	lines = text.replace("\t", TAB_SPACES).split("\n")
	loaded = true
	queue_redraw()


func unload_text() -> void:
	if not loaded:
		return
	lines = PackedStringArray()
	parsed = {}
	loaded = false
	queue_redraw()


func visible_line_count() -> int:
	return int(floor((H - HEADER_H - PAD) / LINE_H))


func max_scroll() -> float:
	return maxf(0.0, float(total_lines) - float(visible_line_count()))


## Scrolling never leaves the focused card and never chains into the next folder
## (§3.1) — it simply clamps.
func scroll_by(delta_lines: float) -> void:
	var before := scroll_line
	scroll_line = clampf(scroll_line + delta_lines, 0.0, max_scroll())
	if not is_equal_approx(before, scroll_line):
		_tick_alpha = 1.0
		_tick_timer = TICK_FADE_DELAY
		queue_redraw()


## Refresh holds position by LINE NUMBER, not pixel offset (§6.2), so the line
## you were reading stays where it was.
func refresh_from_disk() -> void:
	var anchor_line := int(scroll_line)
	loaded = false
	load_text()
	total_lines = lines.size()
	scroll_line = clampf(float(anchor_line), 0.0, max_scroll())
	queue_redraw()


## Resolves a symbol to an attachment point in LOCAL card coordinates, plus the
## state that tells the twine layer how to draw it (§5.1).
##
##   exact  — the anchored line is on screen, attach at its exact y
##   above  — scrolled off the top, clamp to the card's top edge
##   below  — scrolled off the bottom, clamp to the bottom edge
##   dock   — whole-file anchor, or a card too small to resolve lines
##   broken — the symbol no longer exists (§5.6); never silently dropped
func anchor_info(symbol: String) -> Dictionary:
	if symbol == "":
		return {"y": HEADER_H * 0.5, "state": "dock", "line": -1}
	if not symbols.has(symbol):
		return {"y": HEADER_H * 0.5, "state": "broken", "line": -1}

	var line: int = symbols[symbol]

	# Below Read zoom the card can't resolve individual lines, so every twine
	# converges on one dock point per edge and is fanned by the twine layer (§5.1).
	if detail != Detail.READ:
		return {"y": H * 0.5, "state": "dock", "line": line}

	var first := int(scroll_line)
	var count := visible_line_count()
	if line < first:
		return {"y": HEADER_H + 8.0, "state": "above", "line": line}
	if line >= first + count:
		return {"y": H - PAD - 8.0, "state": "below", "line": line}
	return {
		"y": HEADER_H + (line - first) * LINE_H + LINE_H * 0.5,
		"state": "exact",
		"line": line,
	}


## The symbol whose body contains a given local y — used to preselect the source
## end when a drag starts on a func (§5.2).
func symbol_at_local_y(local_y: float) -> String:
	if local_y < HEADER_H or detail != Detail.READ:
		return ""
	var line := int(scroll_line) + int((local_y - HEADER_H) / LINE_H)
	var best := ""
	var best_line := -1
	for sym in symbols:
		var sl: int = symbols[sym]
		if sl <= line and sl > best_line:
			best_line = sl
			best = sym
	return best


func _process(delta: float) -> void:
	if _tick_timer > 0.0:
		_tick_timer -= delta
		if _tick_timer <= 0.0:
			_tick_alpha = maxf(0.0, _tick_alpha - delta * 3.0)
			queue_redraw()
			if _tick_alpha > 0.0:
				_tick_timer = 0.001


# --------------------------------------------------------------------- drawing

func _draw() -> void:
	draw_rect(Rect2(Vector2(5, 7), Vector2(W, H)), Palette.CARD_SHADOW)
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)),
		Palette.CARD_FOCUS if focused else Palette.CARD)
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Palette.CARD_BORDER, false, 1.5)

	# Peek selection reads at any zoom, so its outline is sized in screen pixels.
	if peek_selected:
		var wgt := maxf(3.0, 4.0 / maxf(px_scale, 0.0001))
		draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Palette.TWINE_SEL, false, wgt)

	match detail:
		Detail.READ:
			_draw_header()
			_draw_source()
		Detail.SKIM:
			_draw_header()
			_draw_skim()
		Detail.MAP:
			_draw_map()


## Text is sized to a target PIXEL height and converted back to world units, so
## zooming out shows less detail at a readable size rather than the same detail
## shrunk into illegibility. That is what makes the breakpoints semantic (§4).
func _world_size(target_px: float, min_world: float, max_world: float) -> int:
	return int(clampf(target_px / maxf(px_scale, 0.0001), min_world, max_world))


## Largest size at or below `start` that fits the card's text width.
func _fit(font: Font, text: String, start: int, floor_size: int) -> int:
	var avail := W - PAD * 2.0
	var s := start
	while s > floor_size and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x > avail:
		s = int(s * 0.88)
	return maxi(s, floor_size)


func _draw_header() -> void:
	# In Skim the header must scale up with everything else, or the card's own
	# name becomes the least readable thing on it.
	var name_size := 19
	var meta_size := 13
	var baseline := 30.0
	var meta_baseline := 50.0
	if detail == Detail.SKIM:
		name_size = _world_size(13.5, 19.0, 62.0)
		meta_size = int(name_size * 0.68)
		baseline = name_size * 1.5
		meta_baseline = baseline + meta_size * 1.4

	draw_string(_bold, Vector2(PAD, baseline), file_name,
		HORIZONTAL_ALIGNMENT_LEFT, W - PAD * 2.0, name_size,
		Palette.HEADING if focused else Palette.META)

	var meta := ""
	if extends_name != "":
		meta = "extends " + extends_name
	draw_string(_font, Vector2(PAD, meta_baseline), meta,
		HORIZONTAL_ALIGNMENT_LEFT, W * 0.6, meta_size, Palette.META)

	if detail == Detail.READ and loaded and not lines.is_empty():
		var first := int(scroll_line) + 1
		var last: int = mini(int(scroll_line) + visible_line_count(), lines.size())
		draw_string(_font, Vector2(W - PAD - 190, 50), "%d–%d / %d" % [first, last, lines.size()],
			HORIZONTAL_ALIGNMENT_RIGHT, 190, 13, Palette.META)
	elif detail == Detail.SKIM:
		draw_string(_font, Vector2(W - PAD - 320, baseline), "%d lines" % total_lines,
			HORIZONTAL_ALIGNMENT_RIGHT, 320, meta_size, Palette.META)

	if detail == Detail.READ:
		draw_rect(Rect2(Vector2(PAD, HEADER_H - 10), Vector2(W - PAD * 2.0, 1.0)), Palette.RULE)


func _draw_source() -> void:
	if not loaded:
		return
	var first := int(scroll_line)
	var count := visible_line_count()
	_draw_search_hits(first, count)
	_draw_selection(first, count)
	var avail := W - PAD * 2.0 - 46.0
	var max_chars := int(floor(avail / _char_w))

	for row in count:
		var idx := first + row
		if idx >= lines.size():
			break
		var y := HEADER_H + row * LINE_H + _ascent
		draw_string(_font, Vector2(PAD, y), str(idx + 1),
			HORIZONTAL_ALIGNMENT_RIGHT, 34, 12, Palette.LINE_NUM)
		_draw_code_line(lines[idx], y, max_chars)

	_draw_edge_fades(first, count)
	_draw_tick(first, count)


## Skim (§4): the card becomes a table of contents. Built from the symbol index,
## so it needs no file text at all.
func _draw_skim() -> void:
	var fsize := _world_size(13.0, 20.0, 58.0)
	var row_h := fsize * 1.75
	var y := fsize * 4.2          # clear of the scaled header
	var shown := 0

	for key in ordered:
		if y > H - PAD:
			break
		var parts: PackedStringArray = str(key).split(" ", true, 1)
		var kind: String = parts[0]
		var sym_name: String = parts[1] if parts.size() > 1 else ""
		var col := Palette.for_kind(kind)

		draw_string(_font, Vector2(PAD + 6, y), kind,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(fsize * 0.8), Palette.META)
		draw_string(_bold, Vector2(PAD + 6 + fsize * 3.4, y), sym_name,
			HORIZONTAL_ALIGNMENT_LEFT, W - PAD * 2.0 - fsize * 3.4, fsize, col)
		y += row_h
		shown += 1

	if shown < ordered.size():
		draw_string(_font, Vector2(PAD + 6, y), "+%d more" % (ordered.size() - shown),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(fsize * 0.85), Palette.META)
	elif ordered.is_empty():
		draw_string(_font, Vector2(PAD + 6, y), "no symbols",
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(fsize * 0.85), Palette.META)


## Map (§4): a titled node. Twine is the point of this zoom, so the card says only
## what it needs to be identifiable.
func _draw_map() -> void:
	var stem := file_name.trim_suffix(".gd")
	# Shrink to fit rather than letting a long name run off the card, which
	# clip_contents would otherwise just amputate.
	var title_size := _fit(_bold, stem, _world_size(15.0, 40.0, 150.0), 16)
	var sub_size := int(title_size * 0.55)
	draw_string(_bold, Vector2(PAD, H * 0.42), stem,
		HORIZONTAL_ALIGNMENT_CENTER, W - PAD * 2.0, title_size,
		Palette.HEADING if focused else Palette.INK)

	var sub := "%d lines · %d symbols" % [total_lines, ordered.size()]
	if extends_name != "":
		sub = extends_name + "  ·  " + sub
	sub_size = _fit(_font, sub, sub_size, 10)
	draw_string(_font, Vector2(PAD, H * 0.42 + title_size * 1.25), sub,
		HORIZONTAL_ALIGNMENT_CENTER, W - PAD * 2.0, sub_size, Palette.META)

	if focused:
		draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Palette.ROW_LABEL_ON, false, 6.0)


## Lines are clipped, never wrapped (§2.4) — which is what makes every line
## exactly one row high, and every column an exact x.
func _draw_code_line(line: String, y: float, max_chars: int) -> void:
	var x0 := PAD + 46.0
	var shown := line if line.length() <= max_chars else line.substr(0, max_chars)
	if shown.is_empty():
		return

	# Each character is painted exactly once: coloured runs from the tokenizer,
	# plain ink in the gaps between them. No overdraw, so glyph edges stay clean.
	var cursor := 0
	for run in Syntax.tokenize(shown):
		var start: int = run["start"]
		if start >= shown.length():
			break
		var length: int = mini(run["len"], shown.length() - start)
		if length <= 0:
			continue
		if start > cursor:
			_draw_run(shown.substr(cursor, start - cursor), x0, cursor, y, Palette.INK)
		_draw_run(shown.substr(start, length), x0, start, y, run["color"])
		cursor = start + length
	if cursor < shown.length():
		_draw_run(shown.substr(cursor), x0, cursor, y, Palette.INK)

	if line.length() > max_chars:
		draw_string(_bold, Vector2(W - PAD - 12, y), "›",
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Palette.CLIP_MARK)


## Monospace means column index is an exact x — no measuring needed (§2.4).
func _draw_run(frag: String, x0: float, col: int, y: float, color: Color) -> void:
	draw_string(_font, Vector2(x0 + col * _char_w, y), frag,
		HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


## "There is more this way" without a scrollbar (§2.3).
func _draw_edge_fades(first: int, count: int) -> void:
	var steps := 8
	var stock := Palette.CARD_FOCUS if focused else Palette.CARD
	if first > 0:
		for s in steps:
			var a := (1.0 - float(s) / steps) * 0.95
			draw_rect(Rect2(Vector2(PAD, HEADER_H + s * (FADE_BAND / steps)),
				Vector2(W - PAD * 2.0, FADE_BAND / steps)),
				Color(stock.r, stock.g, stock.b, a))
	if first + count < lines.size():
		for s in steps:
			var a2 := (float(s) / steps) * 0.95
			draw_rect(Rect2(Vector2(PAD, H - PAD - FADE_BAND + s * (FADE_BAND / steps)),
				Vector2(W - PAD * 2.0, FADE_BAND / steps)),
				Color(stock.r, stock.g, stock.b, a2))


func _draw_tick(first: int, count: int) -> void:
	if _tick_alpha <= 0.01 or lines.size() <= count:
		return
	var track := H - HEADER_H - PAD * 2.0
	var tick_h := maxf(30.0, track * (float(count) / float(lines.size())))
	var pos := track * (float(first) / float(maxf(1.0, max_scroll() + count)))
	draw_rect(Rect2(Vector2(W - 10.0, HEADER_H + pos), Vector2(3.0, tick_h)),
		Color(Palette.TICK.r, Palette.TICK.g, Palette.TICK.b, Palette.TICK.a * _tick_alpha))


# ----------------------------------------------------- selection & find (§3.9, §8)

func text_origin() -> float:
	return PAD + 46.0


## Local point -> (line, column). Monospace + no wrapping makes this exact.
func pos_at_local(local: Vector2) -> Vector2i:
	var line := int(scroll_line) + int(floor((local.y - HEADER_H) / LINE_H))
	line = clampi(line, 0, maxi(0, lines.size() - 1))
	var col := int(round((local.x - text_origin()) / _char_w))
	col = clampi(col, 0, lines[line].length() if line < lines.size() else 0)
	return Vector2i(line, col)


func set_selection(a: Vector2i, b: Vector2i) -> void:
	sel_a = a
	sel_b = b
	queue_redraw()


func clear_selection() -> void:
	if sel_a.x >= 0:
		sel_a = Vector2i(-1, -1)
		sel_b = Vector2i(-1, -1)
		queue_redraw()


func has_selection() -> bool:
	return sel_a.x >= 0 and sel_b.x >= 0 and sel_a != sel_b


## Selection in document order, regardless of drag direction.
func _sel_ordered() -> Array:
	var a := sel_a
	var b := sel_b
	if b.x < a.x or (b.x == a.x and b.y < a.y):
		var t := a
		a = b
		b = t
	return [a, b]


func selected_text() -> String:
	if not has_selection():
		return ""
	var ab := _sel_ordered()
	var a: Vector2i = ab[0]
	var b: Vector2i = ab[1]
	if a.x == b.x:
		return lines[a.x].substr(a.y, b.y - a.y)
	var out := PackedStringArray()
	out.append(lines[a.x].substr(a.y))
	for i in range(a.x + 1, b.x):
		out.append(lines[i])
	out.append(lines[b.x].substr(0, b.y))
	return "\n".join(out)


## Case-insensitive literal search over the whole file (§3.9).
func run_search(query: String) -> int:
	search_query = query
	search_hits.clear()
	search_current = -1
	if query.is_empty() or not loaded:
		queue_redraw()
		return 0
	var q := query.to_lower()
	for i in lines.size():
		var hay := lines[i].to_lower()
		var at := hay.find(q)
		while at != -1:
			search_hits.append(Vector2i(i, at))
			at = hay.find(q, at + 1)
	if not search_hits.is_empty():
		search_current = 0
	queue_redraw()
	return search_hits.size()


## Step through matches, scrolling each into view.
func step_search(dir: int) -> void:
	if search_hits.is_empty():
		return
	search_current = wrapi(search_current + dir, 0, search_hits.size())
	var line: int = search_hits[search_current].x
	var count := visible_line_count()
	if line < int(scroll_line) or line >= int(scroll_line) + count:
		scroll_line = clampf(float(line) - count * 0.4, 0.0, max_scroll())
	queue_redraw()


func clear_search() -> void:
	search_query = ""
	search_hits.clear()
	search_current = -1
	queue_redraw()


func _draw_selection(first: int, count: int) -> void:
	if not has_selection():
		return
	var ab := _sel_ordered()
	var a: Vector2i = ab[0]
	var b: Vector2i = ab[1]
	for row in count:
		var idx := first + row
		if idx < a.x or idx > b.x or idx >= lines.size():
			continue
		var from_col: int = a.y if idx == a.x else 0
		var to_col: int = b.y if idx == b.x else lines[idx].length() + 1
		if to_col <= from_col:
			continue
		var y := HEADER_H + row * LINE_H
		draw_rect(Rect2(
			Vector2(text_origin() + from_col * _char_w, y + 2.0),
			Vector2((to_col - from_col) * _char_w, LINE_H - 2.0)), Palette.SELECTION)


func _draw_search_hits(first: int, count: int) -> void:
	if search_hits.is_empty():
		return
	var w := search_query.length() * _char_w
	for i in search_hits.size():
		var hit: Vector2i = search_hits[i]
		if hit.x < first or hit.x >= first + count:
			continue
		var y := HEADER_H + (hit.x - first) * LINE_H
		var col := Palette.MATCH_CURRENT if i == search_current else Palette.MATCH
		draw_rect(Rect2(Vector2(text_origin() + hit.y * _char_w, y + 2.0),
			Vector2(w, LINE_H - 2.0)), col)
