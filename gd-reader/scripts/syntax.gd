class_name Syntax
extends RefCounted

## Per-line GDScript tokenizer for display only.
##
## Returns character RUNS, not pixel spans. Because the card font is monospace and
## lines are never wrapped (§2.4), column index maps to x exactly:
##     x = pad + col * char_width
## so highlighting and clipping are both integer math.

const KEYWORDS := [
	"func", "var", "const", "enum", "class", "class_name", "extends", "signal",
	"static", "if", "elif", "else", "for", "while", "match", "break", "continue",
	"pass", "return", "and", "or", "not", "in", "is", "as", "self", "super",
	"true", "false", "null", "await", "yield", "breakpoint", "assert", "void",
]

const TYPES := [
	"int", "float", "bool", "String", "Vector2", "Vector2i", "Vector3", "Vector3i",
	"Color", "Rect2", "Array", "Dictionary", "Node", "Node2D", "Node3D", "Control",
	"RefCounted", "Resource", "Object", "Callable", "Signal", "StringName",
	"PackedStringArray", "NodePath", "Transform2D", "Basis", "Quaternion",
]

const C_TEXT := Palette.INK
const C_COMMENT := Palette.COMMENT
const C_STRING := Palette.STRING
const C_KEYWORD := Palette.KEYWORD
const C_TYPE := Palette.TYPE
const C_NUMBER := Palette.NUMBER
const C_FUNC := Palette.FUNC
const C_ANNOT := Palette.ANNOT


## Splits one line into [{ start: int, len: int, color: Color }] runs.
static func tokenize(line: String) -> Array:
	var runs: Array = []
	var n := line.length()
	var i := 0

	while i < n:
		var c := line[i]

		# Comment: consumes the rest of the line.
		if c == "#":
			runs.append({"start": i, "len": n - i, "color": C_COMMENT})
			break

		# String literal, single or double quoted.
		if c == "\"" or c == "'":
			var quote := c
			var j := i + 1
			while j < n:
				if line[j] == "\\":
					j += 2
					continue
				if line[j] == quote:
					j += 1
					break
				j += 1
			runs.append({"start": i, "len": min(j, n) - i, "color": C_STRING})
			i = j
			continue

		# Annotation (@export, @onready, @tool).
		if c == "@":
			var j2 := i + 1
			while j2 < n and (line[j2].is_valid_identifier() or line[j2].is_valid_int()):
				j2 += 1
			runs.append({"start": i, "len": j2 - i, "color": C_ANNOT})
			i = j2
			continue

		# Number.
		if c.is_valid_int():
			var j3 := i
			while j3 < n and (line[j3].is_valid_int() or line[j3] == "." or line[j3] == "_"):
				j3 += 1
			runs.append({"start": i, "len": j3 - i, "color": C_NUMBER})
			i = j3
			continue

		# Identifier or keyword.
		if c.is_valid_identifier():
			var j4 := i
			while j4 < n and (line[j4].is_valid_identifier() or line[j4].is_valid_int()):
				j4 += 1
			var word := line.substr(i, j4 - i)
			var col := C_TEXT
			if KEYWORDS.has(word):
				col = C_KEYWORD
			elif TYPES.has(word):
				col = C_TYPE
			elif j4 < n and line[j4] == "(":
				col = C_FUNC
			if col != C_TEXT:
				runs.append({"start": i, "len": j4 - i, "color": col})
			i = j4
			continue

		i += 1

	return runs
