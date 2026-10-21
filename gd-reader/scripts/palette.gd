class_name Palette
extends RefCounted

## Every colour in the app, in one place.
##
## The card is still "a sheet of letter paper" in shape and behaviour (§2.3) —
## it's just dark stock with light ink now. Swapping this file's values for light
## ones is the whole of a light theme; nothing else reads a literal colour.

# Canvas
const CANVAS := Color("0e1013")

## The canvas sits at 95% opacity so the desktop shows faintly through the gutters
## between cards. Cards themselves stay fully opaque — this is atmosphere, not a
## readability tax.
const CANVAS_ALPHA := 0.95

static func canvas_color() -> Color:
	return Color(CANVAS.r, CANVAS.g, CANVAS.b, CANVAS_ALPHA)
const ROW_GUTTER := Color("262c36")
const ROW_LABEL := Color("5a6474")
const ROW_LABEL_ON := Color("c8d0da")

# Card stock
const CARD := Color("1b1f26")
const CARD_FOCUS := Color("20252e")       # focused stock lifts slightly
const CARD_SHADOW := Color("00000066")
const CARD_BORDER := Color("ffffff10")
const HEADING := Color("dbe3ee")
const META := Color("7c8799")
const RULE := Color("ffffff14")
const LINE_NUM := Color("4d5766")
const TICK := Color("ffffff33")
const CLIP_MARK := Color("e0714f")

# Code
const INK := Color("cdd6e3")
const COMMENT := Color("6b7688")
const STRING := Color("8fbf7f")
const KEYWORD := Color("c58fd8")
const TYPE := Color("6fb3e0")
const NUMBER := Color("e0a35c")
const FUNC := Color("7fc3f5")
const ANNOT := Color("e0b75c")

# Selection and search
const SELECTION := Color("3a5a8c66")
const MATCH := Color("b0742a55")
const MATCH_CURRENT := Color("e0a35c88")

# Twine
const TWINE := Color("e0503f")
const TWINE_DIM := Color("e0503f55")
const TWINE_SEL := Color("ff8a6b")
const TWINE_BROKEN := Color("c9a34e")
const INFERRED := Color("5b8fc9aa")
const ADOPT := Color("57c2a8")
const LABEL_BG := Color("0a0c0fee")
const LABEL_FG := Color("e8edf4")

# Blast radius (§10.6): heat that cools with distance from the source.
const BLAST_SRC := Color("fff1c9")
const BLAST_RINGS := [Color("ff7a3d"), Color("ffb347"), Color("e8d46a")]
const BLAST_INK := Color("1a1206")        # badge numerals, on the heat colour

static func blast_color(ring: int) -> Color:
	if ring <= 0:
		return BLAST_SRC
	return BLAST_RINGS[mini(ring, BLAST_RINGS.size()) - 1]


## Symbol kind colours, shared by the Skim table of contents and the picker.
static func for_kind(kind: String) -> Color:
	match kind:
		"func":
			return FUNC
		"signal":
			return ANNOT
		"const":
			return NUMBER
		"var":
			return TYPE
	return INK
