class_name BlastLayer
extends Node2D

## Draws the blast radius (§10.6): what depends on the focused file, ring by ring.
##
## The rings ignite in order — direct users first, then their users — so the
## animation IS the information: you watch the change spread. Halos and the
## edges that carried it sit beneath the cards, so the gaps between cards glow
## and no card's text is drawn over; ring badges sit on top so they read at Map.

const HOP_DELAY := 0.28          # 🎚 seconds between one ring igniting and the next
const IGNITE := 0.30             # 🎚 how long a card takes to light
const SHOCK_TIME := 0.9
const PING_TIME := 0.6
const EDGE_HOLD := 0.8           # 🎚 edges stay bright this long after their ring lights…
const EDGE_FADE := 0.6           # …then fade to a whisper, so a big blast doesn't end as a fan

# Screen pixels, like the twine layer, so the glow holds its size at Map zoom.
const HALO_PX := 18.0
const HALO_STEPS := 6
const EDGE_PX := 2.0
const BADGE_PX := 11.0

var view: Node2D
var _font: Font
var _top: Node2D


## 0 → 1 as a ring ignites, `t` seconds after the blast started.
static func reveal(ring: int, t: float) -> float:
	return clampf((t - ring * HOP_DELAY) / IGNITE, 0.0, 1.0)


## When the last ring has finished flashing and nothing more will move.
static func settle_time(depth: int) -> float:
	return depth * HOP_DELAY + maxf(IGNITE, PING_TIME) + 0.1


func setup(owner_view: Node2D, bold: Font) -> void:
	view = owner_view
	_font = bold
	z_index = -1                           # beneath the cards
	_top = Node2D.new()
	_top.z_index = 96                      # above cards, below twine (relative to -1)
	_top.draw.connect(_draw_badges)
	add_child(_top)


func repaint() -> void:
	queue_redraw()
	_top.queue_redraw()


func _px(v: float) -> float:
	return v / maxf(view.px_scale(), 0.0001)


func _rect(card: Card) -> Rect2:
	return Rect2(card.position, Vector2(Card.W, Card.H))


func _draw() -> void:
	if not view.blast_on or view.cards.is_empty():
		return
	var t: float = view.blast_elapsed()
	var hops: Dictionary = view.blast_hops
	var src: Card = view.focused_card()
	var origin := _rect(src).get_center()

	# Shock ring: one wave off the source, sized to pass the farthest card hit.
	var reach := 0.0
	for key in hops:
		var c: Card = view.blast_cards.get(key)
		if c != null:
			reach = maxf(reach, origin.distance_to(_rect(c).get_center()))
	var st := t / SHOCK_TIME
	if st < 1.0:
		var col := Palette.BLAST_SRC
		col.a = (1.0 - st) * 0.45
		var radius := lerpf(Card.W * 0.5, reach + Card.H, 1.0 - pow(1.0 - st, 3.0))
		draw_arc(origin, radius, 0.0, TAU, 128, col, _px(3.0), true)

	# The edges that carried it, growing from parent to child as each ring lights.
	var parents: Dictionary = view.blast_parent
	for key in parents:
		var child: Card = view.blast_cards.get(key)
		var par: Card = view.blast_cards.get(parents[key])
		if child == null or par == null:
			continue
		var ring: int = hops[key]
		var grow := clampf((t - (ring - 1) * HOP_DELAY) / HOP_DELAY, 0.0, 1.0)
		if grow <= 0.0:
			continue
		var a := _rect(par).get_center()
		var b := _rect(child).get_center()
		var fade := clampf((t - ring * HOP_DELAY - EDGE_HOLD) / EDGE_FADE, 0.0, 1.0)
		var col := Palette.blast_color(ring)
		col.a = lerpf(0.6, 0.12, fade)
		draw_line(a, a.lerp(b, grow), col, _px(EDGE_PX), true)

	# Halos: stacked outlines fading outward read as a glow without a blur pass,
	# which GL Compatibility can't afford across dozens of cards.
	for key in hops:
		var card: Card = view.blast_cards.get(key)
		if card == null:
			continue
		var ring: int = hops[key]
		var lit := reveal(ring, t)
		if lit <= 0.0:
			continue
		var since := t - ring * HOP_DELAY
		var flash := exp(-maxf(since, 0.0) * 4.0)   # bright on ignition, then settles
		var col := Palette.blast_color(ring)
		var rect := _rect(card)
		var step := _px(HALO_PX) / HALO_STEPS
		for i in HALO_STEPS:
			var k := float(i) / HALO_STEPS
			var c := col
			c.a = (1.0 - k) * (1.0 - k) * 0.34 * lit * (1.0 + 1.6 * flash)
			draw_rect(rect.grow(step * (i + 0.5)), c, false, step * 1.2)
		# A ping that leaves each card as it lights.
		if since >= 0.0 and since < PING_TIME:
			var p := since / PING_TIME
			var c := col
			c.a = (1.0 - p) * 0.8
			draw_rect(rect.grow(_px(HALO_PX + 36.0 * p)), c, false, _px(2.0))


## Ring numbers, so a glance at Map tells near from far without judging colour.
## Drawn on the child node, which sits above the cards.
func _draw_badges() -> void:
	if not view.blast_on or view.cards.is_empty():
		return
	var t: float = view.blast_elapsed()
	var hops: Dictionary = view.blast_hops
	var r := _px(BADGE_PX)
	var fsize := int(_px(13.0))
	for key in hops:
		var ring: int = hops[key]
		if ring == 0:
			continue
		var card: Card = view.blast_cards.get(key)
		var lit := reveal(ring, t)
		if card == null or lit <= 0.0:
			continue
		var centre := card.position + Vector2(Card.W - r * 1.4, r * 1.4)
		var col := Palette.blast_color(ring)
		col.a = lit
		_top.draw_circle(centre, r * (1.0 + 0.35 * (1.0 - lit)), col)
		var ink := Palette.BLAST_INK
		ink.a = lit
		var label := str(ring)
		var size := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
		_top.draw_string(_font, centre + Vector2(-size.x * 0.5, size.y * 0.32), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, ink)
