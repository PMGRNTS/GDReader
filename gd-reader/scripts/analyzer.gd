class_name Analyzer
extends RefCounted

## Automatic coupling detection (§10).
##
## GDScript can't be fully resolved without running it — but it is strongly
## idiomatic, and coupling leaves recognisable text behind. Every rule here is
## evidence-bearing: each edge cites the lines that produced it, so a wrong guess
## is visibly wrong rather than mysterious.
##
## What we deliberately do NOT do is invent meaning. These stay inferred (blue)
## edges. Promoting one to red twine is the user's act, because only they know
## WHY two things are related — the analyser only knows THAT they are.

## Weights are relative, not absolute. Inheritance is the strongest coupling a
## file can have; a shared group string is real but loose.
const W := {
	"extends": 10.0,      # subclass — cannot be broken without editing both
	"preload": 6.0,       # hard compile-time reference
	"autoload": 5.0,      # global singleton reach
	"type": 4.0,          # class_name used as a type or constructor
	"group": 3.0,         # bound by a string neither file imports
	"signal": 2.5,        # name-convention pairing
}

## Repeat references matter, but 40 uses isn't 40x the coupling of one.
const REPEAT_GAIN := 0.35
const REPEAT_CAP := 4.0
const KEY_SEP := " -> "

## Engine types are not project coupling; they'd otherwise dominate everything.
const ENGINE_PREFIXES := [
	"Node", "Control", "Resource", "Ref", "Object", "Scene", "Packed", "Array",
	"Dictionary", "String", "Vector", "Color", "Rect", "Transform", "Basis",
	"Quaternion", "Signal", "Callable", "Input", "Time", "Engine", "OS", "JSON",
	"File", "Dir", "Image", "Texture", "Mesh", "Shader", "Material", "Audio",
	"Animation", "Tween", "Timer", "Camera", "Character", "Rigid", "Static",
	"Area", "Collision", "Sprite", "Label", "Button", "Panel", "Line", "Text",
	"Physics", "Viewport", "Window", "Canvas", "Tile", "Navigation", "Random",
]


## Builds weighted, evidence-bearing edges from the parsed index.
##
##   index     : file_key -> parse result (plus "class_name_")
##   autoloads : singleton name -> file_key
##
## Returns [{ from_file, to_file, kinds: {kind: count}, weight, evidence: [str] }]
static func build(index: Dictionary, autoloads: Dictionary) -> Array:
	var by_class := {}                     # class_name -> file_key
	for key in index:
		var cn: String = index[key].get("class_name_", "")
		if cn != "":
			by_class[cn] = key

	var acc := {}                          # "from -> to" -> edge

	for key in index:
		var data: Dictionary = index[key]

		# --- extends: by class_name ---
		var ext: String = data.get("extends_name", "")
		if ext != "" and by_class.has(ext) and by_class[ext] != key:
			_add(acc, key, by_class[ext], "extends", "extends %s" % ext)

		# --- preload / load with a literal path ---
		for r in data.get("refs", []):
			var target: String = r["target"]
			if index.has(target) and target != key:
				_add(acc, key, target, "preload", "%s(%s)" % [r["kind"], target])

		# --- capitalised identifiers: class_name types and autoload singletons ---
		for id in data.get("idents", []):
			var name: String = id["name"]
			if name == ext:
				continue                   # already counted as inheritance
			if autoloads.has(name) and autoloads[name] != key:
				_add(acc, key, autoloads[name], "autoload", "%s (autoload)" % name)
			elif by_class.has(name) and by_class[name] != key and not _is_engine_type(name):
				_add(acc, key, by_class[name], "type", name)

	_add_group_edges(index, acc)
	_add_signal_edges(index, acc)

	var out: Array = []
	for k in acc:
		var e: Dictionary = acc[k]
		e["weight"] = _weigh(e["kinds"])
		out.append(e)
	out.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	return out


## Whoever joins a group and whoever queries it are coupled through a string that
## appears in neither file's imports — invisible to every other rule here.
static func _add_group_edges(index: Dictionary, acc: Dictionary) -> void:
	var joiners := {}                      # group -> [file]
	var queriers := {}
	for key in index:
		for g in index[key].get("groups", []):
			var bucket: Dictionary = joiners if g["mode"] == "join" else queriers
			if not bucket.has(g["name"]):
				bucket[g["name"]] = []
			if not bucket[g["name"]].has(key):
				bucket[g["name"]].append(key)

	for group in queriers:
		if not joiners.has(group):
			continue
		for q in queriers[group]:
			for j in joiners[group]:
				if q != j:
					_add(acc, q, j, "group", "group %s" % group)


## A file declaring `signal died` and another handling `_on_died` or connecting
## to `died` are paired by convention. Weakest rule here, and marked as such.
static func _add_signal_edges(index: Dictionary, acc: Dictionary) -> void:
	var declared := {}                     # signal name -> [file]
	for key in index:
		for sym in index[key].get("symbols", []):
			if sym["kind"] == "signal":
				if not declared.has(sym["name"]):
					declared[sym["name"]] = []
				declared[sym["name"]].append(key)

	for key in index:
		for used in index[key].get("signals_used", []):
			var name: String = used["name"]
			if not declared.has(name):
				continue
			for owner_file in declared[name]:
				if owner_file != key:
					_add(acc, key, owner_file, "signal", "signal %s" % name)


## How hard a file reaches outside itself. Not an edge — a property of the file,
## because the target usually cannot be resolved statically. Still worth showing:
## it is the coupling that hurts and the one nothing else marks.
static func reach_score(data: Dictionary) -> int:
	return data.get("reaches", []).size()


static func _add(acc: Dictionary, from_file: String, to_file: String,
		kind: String, evidence: String) -> void:
	var k := from_file + KEY_SEP + to_file
	if not acc.has(k):
		acc[k] = {
			"from_file": from_file,
			"to_file": to_file,
			"kinds": {},
			"evidence": [],
			"weight": 0.0,
		}
	var e: Dictionary = acc[k]
	e["kinds"][kind] = int(e["kinds"].get(kind, 0)) + 1
	if e["evidence"].size() < 6 and not e["evidence"].has(evidence):
		e["evidence"].append(evidence)


static func _weigh(kinds: Dictionary) -> float:
	var total := 0.0
	for kind in kinds:
		var count: int = kinds[kind]
		var repeat: float = minf(1.0 + REPEAT_GAIN * (count - 1), REPEAT_CAP)
		total += float(W.get(kind, 1.0)) * repeat
	return total


static func _is_engine_type(name: String) -> bool:
	for prefix in ENGINE_PREFIXES:
		if name.begins_with(prefix):
			return true
	return false


## A short human phrase for an edge, used to prefill the description when the
## user adopts it as twine.
static func describe(edge: Dictionary) -> String:
	var parts: Array = []
	var kinds: Dictionary = edge["kinds"]
	for kind in ["extends", "preload", "autoload", "type", "group", "signal"]:
		if kinds.has(kind):
			var n: int = kinds[kind]
			parts.append(kind if n == 1 else "%s x%d" % [kind, n])
	return " · ".join(parts)
