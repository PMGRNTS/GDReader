class_name TwineLayer
extends Node2D

## Draws twine above the cards (§5.4).
##
## Red  = user-authored, always drawn, dimmed when it doesn't touch focus.
## Blue = inferred from source. By default only the one pointed at in the
##        connections panel (or selected with G) is drawn: even one file's
##        inferred lines are soup once there are more than a handful, and the
##        panel is where they're read. Ctrl+E widens to the file, then to all.

const C_RED := Palette.TWINE
const C_RED_DIM := Palette.TWINE_DIM
const C_RED_SEL := Palette.TWINE_SEL
const C_BLUE := Palette.INFERRED
const C_LABEL_BG := Palette.LABEL_BG
const C_LABEL_FG := Palette.LABEL_FG
const C_BROKEN := Palette.TWINE_BROKEN
const C_ADOPT := Palette.ADOPT

const DOCK_FAN := 26.0                     # §5.1 spread for docked twine

const SAG := 0.16                          # catenary droop as a fraction of span
const SAG_MAX := 240.0
const SEGMENTS := 22

# Targets in SCREEN pixels. Twine is the point of Map zoom, so its weight and
# labels hold their apparent size instead of thinning away as you zoom out.
const STUB_PX := 64.0
const WIDTH_PX := 1.9
const WIDTH_SEL_PX := 3.0
const LABEL_PX := 12.5
const CHEVRON_PX := 12.0
const DOCK_FAN_PX := 9.0

var view: Node2D                           # the CanvasView that owns the model
var _font: Font
var _bold: Font


func setup(owner_view: Node2D, font: Font, bold: Font) -> void:
	view = owner_view
	_font = font
	_bold = bold
	z_index = 100                          # above the cards


func _draw() -> void:
	if view == null or view.cards.is_empty():
		return

	var focus_key: String = view.focused_card().file_key

	# Inferred edges first, so user twine always sits on top of them.
	var candidates: Array = view.inferred_for_focus()
	var adopt_target: Dictionary = {}
	if view.adopt_idx >= 0 and view.adopt_idx < candidates.size():
		adopt_target = candidates[view.adopt_idx]
	var hovered: Dictionary = {}
	if view.hover_edge_idx >= 0 and view.hover_edge_idx < candidates.size():
		hovered = candidates[view.hover_edge_idx]

	if view.lines_mode != view.Lines.POINTED:
		for e in view.inferred:
			var touches: bool = e["from_file"] == focus_key or e["to_file"] == focus_key
			if view.lines_mode == view.Lines.ALL or touches:
				if e != adopt_target and e != hovered:
					_draw_inferred(e, false)
	# The pointed-at and selected edges always draw, last, so they sit on top.
	if not hovered.is_empty() and hovered != adopt_target:
		_draw_inferred(hovered, true)
	if not adopt_target.is_empty():
		_draw_inferred(adopt_target, true)

	for i in view.store.links.size():
		var link: Dictionary = view.store.links[i]
		# Prefer the link's rank among the focused file's twine: those are the
		# ones drawn with labels, and they need distinct slots to stay readable.
		var slot: int = view.label_slot(link.get("id", ""))
		_draw_link(link, focus_key, i if slot < 0 else slot)

	if view.drag_active:
		_draw_drag()


# --------------------------------------------------------------------- user twine

func _draw_link(link: Dictionary, focus_key: String, slot: int) -> void:
	var from_file: String = link["from"]["file"]
	var to_file: String = link["to"]["file"]
	var a: Dictionary = view.resolve_anchor(from_file, link["from"]["symbol"], to_file)
	var b: Dictionary = view.resolve_anchor(to_file, link["to"]["symbol"], from_file)
	if a.is_empty() or b.is_empty():
		return

	var touches: bool = link["from"]["file"] == focus_key or link["to"]["file"] == focus_key
	var selected: bool = view.selected_link_id == link.get("id", "") \
		or view.hover_link_id == link.get("id", "")
	var broken: bool = a["state"] == "broken" or b["state"] == "broken"
	var described: bool = str(link.get("description", "")).strip_edges() != ""

	var col := C_RED_DIM
	if selected:
		col = C_RED_SEL
	elif broken:
		col = C_BROKEN
	elif touches:
		col = C_RED

	var width := _px(WIDTH_SEL_PX if selected else WIDTH_PX)

	# A far endpoint entirely off-screen becomes a stub at the card edge, angled
	# toward its target — Tab-cycling is how you actually traverse it (§5.1).
	var a_vis: bool = view.is_point_visible(a["pos"])
	var b_vis: bool = view.is_point_visible(b["pos"])
	if not a_vis and not b_vis and view.lines_mode != view.Lines.ALL:
		return
	if a_vis and not b_vis:
		_draw_stub(a, b["pos"], col, width, to_file, slot)
		return
	if b_vis and not a_vis:
		_draw_stub(b, a["pos"], col, width, from_file, slot)
		return

	var ap: Vector2 = a["pos"] + _fan(a, slot)
	var bp: Vector2 = b["pos"] + _fan(b, slot)
	var pts := _curve(ap, bp)
	if described:
		draw_polyline(pts, col, width, true)
	else:
		_draw_dashed(pts, col, width)     # loose end: drawn but never labelled (§5.6)

	_draw_chevron(a, col)
	_draw_chevron(b, col)

	if touches or selected:
		var mid: Vector2 = pts[pts.size() / 2] + _slot_offset(slot)
		var text: String = link.get("description", "")
		if text.strip_edges() == "":
			text = "(unlabelled)"
		if broken:
			text = "⚠ " + text
		_draw_label(mid, text, selected)


## The anchored line is off-screen above or below — the twine clamps to the card
## edge and a chevron says which way (§5.1).
func _draw_chevron(anchor: Dictionary, col: Color) -> void:
	var glyph := ""
	match anchor["state"]:
		"above":
			glyph = "▲"
		"below":
			glyph = "▼"
		"broken":
			glyph = "✕"
		_:
			return
	var ap: Vector2 = anchor["pos"]
	var cs := int(_px(CHEVRON_PX))
	draw_string(_bold, ap + Vector2(-cs * 0.35, -cs * 0.55), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, cs, col)


## The far end is entirely off-screen: a short stub angled at its target, named
## with the file it reaches. Tab-cycling is how you actually travel it (§5.1).
func _draw_stub(from_anchor: Dictionary, toward: Vector2, col: Color, width: float,
		far_file: String, slot: int) -> void:
	var from_pos: Vector2 = from_anchor["pos"]
	var dir: Vector2 = (toward - from_pos).normalized()
	var end: Vector2 = from_pos + dir * _px(STUB_PX)
	draw_line(from_pos, end, col, width, true)
	draw_circle(end, _px(3.5), col)
	_draw_chevron(from_anchor, col)
	_draw_label(end + dir * _px(10.0) + _slot_offset(slot), far_file.get_file(), false)


## Several twines on one card put their labels in nearly the same place, so each
## gets a row in a stack centred on the midpoint.
func _slot_offset(slot: int) -> Vector2:
	var n: int = maxi(view.cycle_count(), 1)
	return Vector2(0.0, (float(slot) - (n - 1) * 0.5) * _px(19.0))


## World units for a target size in screen pixels.
func _px(v: float) -> float:
	return v / maxf(view.px_scale(), 0.0001)


## Below Read zoom every twine on a card converges on one dock point, so they are
## fanned slightly to stay countable (§5.1).
func _fan(anchor: Dictionary, slot: int) -> Vector2:
	if anchor["state"] != "dock":
		return Vector2.ZERO
	return Vector2(0.0, (slot % 5 - 2) * _px(DOCK_FAN_PX))


# ------------------------------------------------------------------ inferred edges

## Inferred edges carry a coupling weight (§10), so they are drawn with it:
## an `extends` reads heavier than a shared group string, at a glance.
func _draw_inferred(edge: Dictionary, is_adopt_target: bool) -> void:
	var a: Dictionary = view.resolve_anchor(edge["from_file"], "", edge["to_file"])
	var b: Dictionary = view.resolve_anchor(edge["to_file"], "", edge["from_file"])
	if a.is_empty() or b.is_empty():
		return
	var a_vis: bool = view.is_point_visible(a["pos"])
	var b_vis: bool = view.is_point_visible(b["pos"])
	if not a_vis and not b_vis:
		return

	# A highlighted edge whose far end is off-screen would run out of the window
	# with its label somewhere past the edge. As a stub it says where it goes.
	if is_adopt_target and a_vis != b_vis:
		var near: Dictionary = a if a_vis else b
		var far_pos: Vector2 = b["pos"] if a_vis else a["pos"]
		var far_file: String = edge["to_file"] if a_vis else edge["from_file"]
		var near_pos: Vector2 = near["pos"]
		var dir: Vector2 = (far_pos - near_pos).normalized()
		var end: Vector2 = near_pos + dir * _px(STUB_PX * 2.2)
		draw_line(near_pos, end, C_ADOPT, _px(3.0), true)
		draw_circle(end, _px(4.0), C_ADOPT)
		_draw_label(end + dir * _px(12.0), "%s  ·  %s" % [far_file.get_file(),
			Analyzer.describe(edge)], false)
		return

	var ap: Vector2 = a["pos"]
	var bp: Vector2 = b["pos"]
	var weight: float = edge.get("weight", 1.0)
	var t: float = clampf(weight / 20.0, 0.0, 1.0)
	var width := _px(lerpf(1.0, 3.4, t))
	var col := C_BLUE
	col.a = lerpf(0.45, 0.95, t)

	if is_adopt_target:
		col = C_ADOPT
		width = _px(3.6)

	var pts := _curve(ap, bp)
	draw_polyline(pts, col, width, true)

	if is_adopt_target:
		var mid: Vector2 = pts[pts.size() / 2]
		var far: String = edge["to_file"] if edge["from_file"] == view.focused_card().file_key \
			else edge["from_file"]
		_draw_label(mid, "%s  ·  %s" % [far.get_file(), Analyzer.describe(edge)], false)


# ------------------------------------------------------------------------- drag

func _draw_drag() -> void:
	var pts := _curve(view.drag_from_pos, view.drag_to_pos)
	_draw_dashed(pts, C_RED_SEL, _px(2.0))
	draw_circle(view.drag_from_pos, _px(4.0), C_RED_SEL)


# ---------------------------------------------------------------------- drawing

## Slight droop, so it reads as string rather than a graph edge (§5.4).
func _curve(p0: Vector2, p1: Vector2) -> PackedVector2Array:
	var sag: float = minf(p0.distance_to(p1) * SAG, SAG_MAX)
	var ctrl := (p0 + p1) * 0.5 + Vector2(0.0, sag)
	var pts := PackedVector2Array()
	for i in SEGMENTS + 1:
		var t := float(i) / SEGMENTS
		var q0 := p0.lerp(ctrl, t)
		var q1 := ctrl.lerp(p1, t)
		pts.append(q0.lerp(q1, t))
	return pts


func _draw_dashed(pts: PackedVector2Array, col: Color, width: float) -> void:
	var i := 0
	while i < pts.size() - 1:
		draw_line(pts[i], pts[i + 1], col, width, true)
		i += 2


func _draw_label(at: Vector2, text: String, highlight: bool) -> void:
	if text == "":
		return
	var fsize := int(_px(LABEL_PX))
	var size := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
	var pad := Vector2(_px(7.0), _px(4.0))
	var rect := Rect2(at - Vector2(size.x * 0.5, size.y * 0.5) - pad,
		size + pad * 2.0)
	draw_rect(rect, C_LABEL_BG)
	if highlight:
		draw_rect(rect, C_RED_SEL, false, _px(1.5))
	draw_string(_font, at + Vector2(-size.x * 0.5, size.y * 0.30), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, C_LABEL_FG)
