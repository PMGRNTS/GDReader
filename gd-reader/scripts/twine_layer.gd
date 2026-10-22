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

# Red twine is string, so it behaves like string: each one's middle is a damped
# spring that lags when its ends move or the camera swings, then settles. Blue
# edges stay still — they're the analyser's claim, not something you tied.
# Offsets are in SCREEN pixels so the sway reads the same at every zoom.
const SWAY_HZ := 1.4                       # 🎚 how fast a swaying twine swings
const SWAY_DAMPING := 0.22                 # 🎚 damping ratio: lower swings longer
const ENDPOINT_LAG := 0.55                 # 🎚 how much of an end's move the middle lags
const CAM_INERTIA := 0.08                  # 🎚 how hard a camera move throws the string
const SWAY_MAX_PX := 28.0                  # 🎚 a swing never exceeds this…
const SWAY_MAX_FRAC := 0.18                # …or this fraction of the twine's span

# New twine is pulled taut, held a beat, then let go: it drops into its sag and
# rings out, while both pins pop in. You just made a claim; it should land.
const TWANG_HOLD := 0.09                   # 🎚 seconds held straight before release
const TWANG_HZ := 2.6                      # 🎚 a fresh twang rings faster…
const TWANG_DAMPING := 0.13                # 🎚 …and longer than an ordinary sway
const PIN_PX := 3.4                        # 🎚 pushpin head radius
const PIN_POP := 0.36                      # 🎚 seconds for a new pin to pop in
const PIN_POP_OVERSHOOT := 1.7             # 🎚 back-ease overshoot on the pop
const RIPPLE_PX := 17.0                    # 🎚 how far the pin's ripple spreads
const RIPPLE_TIME := 0.5

# Broken twine lets go of its missing end: it hangs off the end that still
# holds, frayed, instead of pretending to reach a symbol that is gone (§5.6).
const DANGLE_FRAC := 0.38                  # 🎚 hangs this fraction of the old span…
const DANGLE_MAX_PX := 150.0               # 🎚 …up to this long on screen
const DANGLE_REACH := 0.45                 # 🎚 how far it still leans toward its target
const DANGLE_IDLE_PX := 1.6                # 🎚 a slow idle drift; 0 holds it still
const DANGLE_IDLE_PERIOD := 3.4
const FRAY := [[-0.55, 7.0], [-0.18, 10.0], [0.22, 8.5], [0.6, 6.0]]  # 🎚 [angle, px]

## Holds every twine still, drops the twang and pin pop. Set by the canvas.
var reduce_motion := false

var view: Node2D                           # the CanvasView that owns the model
var _font: Font
var _bold: Font

# key -> { off, vel (screen px), mid (world), span_px, hz, zeta, hold, seen,
#          twang: waiting to be pulled taut, ringing: twanged and not yet settled }
var _springs := {}
var _pops := {}                            # link id -> seconds it was tied
var _frame := 0
var _cam_pos := Vector2.INF
var _cam_vel := Vector2.ZERO


func setup(owner_view: Node2D, font: Font, bold: Font) -> void:
	view = owner_view
	_font = font
	_bold = bold
	z_index = 100                          # above the cards


## A twine was just tied: pull it taut and pop its pins.
func tie(link_id: String) -> void:
	if reduce_motion or link_id == "":
		return
	_pops[link_id] = _now()
	var s := _spring(link_id)
	s["twang"] = true


func _process(delta: float) -> void:
	_frame += 1
	if delta <= 0.0:
		return
	var cam := get_viewport().get_camera_2d()
	var kick := Vector2.ZERO
	if cam != null:
		var p := cam.global_position
		var step: Vector2 = (p - _cam_pos) * view.px_scale()
		# A cut (project switch, instant jump) isn't motion; don't throw string at it.
		if _cam_pos == Vector2.INF or step.length() > get_viewport_rect().size.x:
			_cam_vel = Vector2.ZERO
		else:
			var vel: Vector2 = step / delta
			kick = -(vel - _cam_vel) * CAM_INERTIA
			_cam_vel = vel
		_cam_pos = p

	var now := _now()
	for key in _springs.keys():
		var s: Dictionary = _springs[key]
		if _frame - int(s["seen"]) > 30:
			_springs.erase(key)            # off-screen a while: rest when it returns
			continue
		if reduce_motion:
			s["off"] = Vector2.ZERO
			s["vel"] = Vector2.ZERO
			continue
		if now < float(s["hold"]):
			continue
		var stepped := spring_step(s["off"], s["vel"] + kick, float(s["hz"]), float(s["zeta"]), delta)
		var off: Vector2 = stepped[0]
		var vel: Vector2 = stepped[1]
		var cap := minf(SWAY_MAX_PX, float(s["span_px"]) * SWAY_MAX_FRAC)
		if s["ringing"]:
			cap = maxf(cap, float(s["span_px"]))   # a twang starts beyond the sway cap
		if off.length() > cap:
			off = off.normalized() * cap
		if off.length() < 0.05 and vel.length() < 0.5:
			off = Vector2.ZERO
			vel = Vector2.ZERO
			s["hz"] = SWAY_HZ
			s["zeta"] = SWAY_DAMPING
			s["ringing"] = false
		s["off"] = off
		s["vel"] = vel

	for id in _pops.keys():
		if now - float(_pops[id]) > maxf(PIN_POP, RIPPLE_TIME) + TWANG_HOLD:
			_pops.erase(id)


## One semi-implicit Euler step of a damped spring. Returns [offset, velocity].
static func spring_step(off: Vector2, vel: Vector2, hz: float, zeta: float, dt: float) -> Array:
	var w := TAU * hz
	vel += (-w * w * off - 2.0 * zeta * w * vel) * dt
	return [off + vel * dt, vel]


func _spring(key: String) -> Dictionary:
	if not _springs.has(key):
		_springs[key] = {
			"off": Vector2.ZERO, "vel": Vector2.ZERO, "mid": Vector2.INF,
			"span_px": 0.0, "hz": SWAY_HZ, "zeta": SWAY_DAMPING, "hold": 0.0,
			"seen": _frame, "twang": false, "ringing": false,
		}
	return _springs[key]


## Feeds this frame's endpoints to the twine's spring and returns how far its
## middle is displaced, in world units.
func _sway(key: String, p0: Vector2, p1: Vector2, sag: float) -> Vector2:
	if reduce_motion:
		return Vector2.ZERO
	var s := _spring(key)
	s["seen"] = _frame
	var scale: float = view.px_scale()
	var span_px := p0.distance_to(p1) * scale
	s["span_px"] = span_px
	var mid := (p0 + p1) * 0.5
	if s["twang"]:
		# Straight line: the quadratic's midpoint sits half the sag below the chord.
		s["twang"] = false
		s["off"] = Vector2(0.0, -sag * 0.5 * scale)
		s["vel"] = Vector2.ZERO
		s["hz"] = TWANG_HZ
		s["zeta"] = TWANG_DAMPING
		s["ringing"] = true
		s["hold"] = _now() + TWANG_HOLD
	elif s["mid"] != Vector2.INF:
		var shift: Vector2 = (mid - s["mid"]) * scale
		# A jump past twice the span is a relayout, not a motion worth swinging at.
		if shift.length() < span_px * 2.0:
			s["off"] -= shift * ENDPOINT_LAG
	s["mid"] = mid
	return s["off"] / scale


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


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
	var id: String = link.get("id", "")
	var text: String = link.get("description", "")
	if text.strip_edges() == "":
		text = "(unlabelled)"

	# One end lost its symbol: hang from the end that still holds. It needs no
	# far end on screen, because it no longer reaches one.
	var a_lost: bool = a["state"] == "broken"
	var b_lost: bool = b["state"] == "broken"
	if a_lost != b_lost:
		var hold: Dictionary = b if a_lost else a
		var lost: Dictionary = a if a_lost else b
		if view.is_point_visible(hold["pos"]):
			var label := ""
			if touches or selected:
				label = "⚠ " + text
				if not view.is_point_visible(lost["pos"]):
					label += "  ·  " + (from_file if a_lost else to_file).get_file()
			_draw_dangle(id, hold["pos"] + _fan(hold, slot), lost, col, width,
				described, label, selected, slot)
			return

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
	var pts := _curve(ap, bp, id)
	if described:
		draw_polyline(pts, col, width, true)
	else:
		_draw_dashed(pts, col, width)     # loose end: drawn but never labelled (§5.6)

	_draw_chevron(a, col)
	_draw_chevron(b, col)
	_draw_pin(ap, col, id)
	_draw_pin(bp, col, id)

	if touches or selected:
		var mid: Vector2 = pts[pts.size() / 2] + _slot_offset(slot)
		if broken:
			text = "⚠ " + text
		_draw_label(mid, text, selected)


## Broken twine hanging off the end that still holds: it heads toward where its
## target was, gives up, falls, and ends in a fray (§5.6).
func _draw_dangle(id: String, hold: Vector2, lost: Dictionary, col: Color, width: float,
		described: bool, label: String, selected: bool, slot: int) -> void:
	var toward: Vector2 = lost["pos"]
	var dir := (toward - hold).normalized()
	var length := minf(hold.distance_to(toward) * DANGLE_FRAC, _px(DANGLE_MAX_PX))
	var reach := dir.x * length * DANGLE_REACH
	var drop := sqrt(maxf(length * length - reach * reach, 0.0)) * 0.9
	var ctrl := hold + dir * length * 0.55
	var tip := hold + Vector2(reach, drop)

	if not reduce_motion:
		var s := _spring("dangle:" + id)
		s["seen"] = _frame
		s["span_px"] = length * view.px_scale() * 2.0
		if s["mid"] != Vector2.INF:
			var shift: Vector2 = (hold - s["mid"]) * view.px_scale()
			if shift.length() < s["span_px"]:
				s["off"] -= shift * ENDPOINT_LAG
		s["mid"] = hold
		# Each dangle drifts on its own phase, so a handful never swing in step.
		var phase := float(hash(id) % 1000) / 1000.0 * TAU
		var idle := sin(_now() * TAU / DANGLE_IDLE_PERIOD + phase) * DANGLE_IDLE_PX
		tip += (s["off"] + Vector2(idle, 0.0)) / view.px_scale()

	var pts := PackedVector2Array()
	var n := SEGMENTS / 2
	for i in n + 1:
		var t := float(i) / n
		pts.append(hold.lerp(ctrl, t).lerp(ctrl.lerp(tip, t), t))
	if described:
		draw_polyline(pts, col, width, true)
	else:
		_draw_dashed(pts, col, width)

	var along := (tip - pts[pts.size() - 2]).normalized()
	var strand := col
	strand.a *= 0.8
	for f in FRAY:
		var d := along.rotated(float(f[0]))
		var mid := tip + d * _px(float(f[1]) * 0.55)
		var end := mid + d.rotated(float(f[0]) * 0.5) * _px(float(f[1]) * 0.45)
		draw_polyline(PackedVector2Array([tip, mid, end]), strand, width * 0.5, true)

	_draw_chevron(lost, col)               # the ✕ still marks where it used to hold
	_draw_pin(hold, col, id)
	if label != "":
		_draw_label(pts[pts.size() / 2] + _slot_offset(slot), label, selected)


## A pushpin head where twine meets a card. Freshly tied pins pop in with a ripple.
func _draw_pin(at: Vector2, col: Color, id: String) -> void:
	var r := _px(PIN_PX)
	var head := col
	head.a = maxf(head.a, 0.6)
	if _pops.has(id):
		var t := _now() - float(_pops[id]) - TWANG_HOLD * 0.5
		if t < 0.0:
			return                         # not yet pushed in
		if t < RIPPLE_TIME:
			var k := t / RIPPLE_TIME
			var ring := head
			ring.a *= (1.0 - k) * 0.8
			draw_arc(at, r + _px(RIPPLE_PX) * k, 0.0, TAU, 24, ring, _px(1.5), true)
		r *= back_ease(clampf(t / PIN_POP, 0.0, 1.0))
	draw_circle(at, r, head)
	draw_circle(at + Vector2(-r, -r) * 0.3, r * 0.35, Color(1, 1, 1, 0.45 * head.a))


## 0 → 1 with an overshoot past 1 before settling.
static func back_ease(t: float) -> float:
	var c := PIN_POP_OVERSHOOT
	var u := t - 1.0
	return 1.0 + (c + 1.0) * u * u * u + c * u * u


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

## Slight droop, so it reads as string rather than a graph edge (§5.4). Given a
## `spring_key`, the droop sways with that twine's spring.
func _curve(p0: Vector2, p1: Vector2, spring_key := "") -> PackedVector2Array:
	var sag: float = minf(p0.distance_to(p1) * SAG, SAG_MAX)
	var ctrl := (p0 + p1) * 0.5 + Vector2(0.0, sag)
	if spring_key != "":
		# The curve's middle moves half as far as its control point.
		ctrl += _sway(spring_key, p0, p1, sag) * 2.0
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
