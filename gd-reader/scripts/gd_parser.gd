class_name GDParser
extends RefCounted

## Hand-rolled line scanner over raw GDScript text (§7).
##
## We deliberately do NOT load the script as a resource and call get_method_list():
## that yields names without line numbers, and loading a foreign .gd can fire
## class_name registration or tool-script side effects.
##
## Every symbol carries its line, because anchor clamping (§5.1), the line-range
## readout (§2.3) and refresh-by-line-number (§6.2) all need exact positions.

const KEYWORD_RE := "^\\s*(func|signal|const|var|class_name|extends|enum|class|static func)\\s"


## Parses source text into a symbol index.
##   {
##     extends_name: "CharacterBody2D",
##     class_name_: "Player",
##     symbols: [ { kind: "func", name: "take_damage", line: 42, text: "..." }, ... ],
##     refs:    [ { kind: "preload", target: "res://x.gd", line: 7 }, ... ],
##     line_count: 520
##   }
static func parse(text: String) -> Dictionary:
	var lines := text.split("\n")
	var out := {
		"extends_name": "",
		"class_name_": "",
		"symbols": [],
		"refs": [],
		# Coupling evidence (§10). Collected in the same pass as everything else.
		"idents": [],        # capitalised identifiers -> class_name / autoload use
		"groups": [],        # { name, line, mode: "join" | "query" }
		"signals_used": [],  # { name, line } — .connect() targets and _on_ handlers
		"reaches": [],       # { kind, line } — scripts grabbing outside themselves
		"line_count": lines.size(),
	}

	for i in lines.size():
		var raw: String = lines[i]
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue

		# Only treat top-level-ish declarations as symbols; indented inner funcs
		# in nested classes still register, which is what we want for anchors.
		if line.begins_with("func ") or line.begins_with("static func "):
			var n := _ident_after(line, "func ")
			if n != "":
				out["symbols"].append({"kind": "func", "name": n, "line": i, "text": line})
		elif line.begins_with("signal "):
			var n2 := _ident_after(line, "signal ")
			if n2 != "":
				out["symbols"].append({"kind": "signal", "name": n2, "line": i, "text": line})
		elif line.begins_with("class_name "):
			out["class_name_"] = _ident_after(line, "class_name ")
		elif line.begins_with("extends "):
			if out["extends_name"] == "":
				out["extends_name"] = _ident_after(line, "extends ")
		elif line.begins_with("const "):
			var n3 := _ident_after(line, "const ")
			if n3 != "":
				out["symbols"].append({"kind": "const", "name": n3, "line": i, "text": line})
		elif raw.begins_with("var ") or raw.begins_with("@export"):
			# Top-level only (column 0) — locals inside funcs are noise on the map.
			var n4 := _ident_after(line.trim_prefix("@export").strip_edges(), "var ")
			if n4 != "":
				out["symbols"].append({"kind": "var", "name": n4, "line": i, "text": line})

		_collect_refs(line, i, out["refs"])
		_collect_groups(line, i, out["groups"])
		_collect_signals(line, i, out["signals_used"])
		_collect_reaches(line, i, out["reaches"])
		_collect_idents(line, i, out["idents"])

	return out


## Strips comments and string CONTENTS, keeping the quotes. Identifier scanning
## must not see words inside strings, but the string positions still matter.
static func strip_noise(line: String) -> String:
	var out := ""
	var i := 0
	var n := line.length()
	while i < n:
		var c := line[i]
		if c == "#":
			break
		if c == "\"" or c == "'":
			var quote := c
			out += " "
			i += 1
			while i < n and line[i] != quote:
				if line[i] == "\\":
					i += 1
				out += " "
				i += 1
			i += 1
			out += " "
			continue
		out += c
		i += 1
	return out


## Capitalised bare identifiers: in Godot these are class_names, autoload
## singletons and engine types. Resolved against the project's registries later.
static func _collect_idents(line: String, idx: int, out: Array) -> void:
	var clean := strip_noise(line)
	var i := 0
	var n := clean.length()
	while i < n:
		var c := clean[i]
		if not (c.is_valid_identifier() or c.is_valid_int()):
			i += 1
			continue
		var start := i
		while i < n and (clean[i].is_valid_identifier() or clean[i].is_valid_int()):
			i += 1
		var word := clean.substr(start, i - start)
		# Member access (foo.Bar) isn't a reference to a global Bar.
		if start > 0 and clean[start - 1] == ".":
			continue
		if word.length() < 2 or word[0] != word[0].to_upper() or word[0].is_valid_int():
			continue
		# ALL_CAPS is a constant, not a type.
		if word == word.to_upper():
			continue
		out.append({"name": word, "line": idx})


## Group membership is real coupling that nothing else records: whoever joins a
## group and whoever queries it are bound by a string neither file imports.
static func _collect_groups(line: String, idx: int, out: Array) -> void:
	for kw in ["add_to_group", "is_in_group", "get_nodes_in_group",
			"get_first_node_in_group", "remove_from_group"]:
		var name := _string_arg_after(line, kw)
		if name != "":
			var mode := "join" if kw == "add_to_group" else "query"
			out.append({"name": name, "line": idx, "mode": mode})


static func _collect_signals(line: String, idx: int, out: Array) -> void:
	# `something.connect(...)` — the signal is the identifier before .connect
	var at := line.find(".connect(")
	while at != -1:
		var j := at - 1
		var end := at
		while j >= 0 and (line[j].is_valid_identifier() or line[j].is_valid_int()):
			j -= 1
		var name := line.substr(j + 1, end - j - 1)
		if name != "":
			out.append({"name": name, "line": idx})
		at = line.find(".connect(", at + 1)

	# `func _on_damaged(...)` — the Godot handler convention
	if line.begins_with("func _on_"):
		var handler := _ident_after(line, "func ")
		if handler != "":
			out.append({"name": handler.trim_prefix("_on_"), "line": idx})


## "Reaching": a script grabbing something outside its own subtree. This is the
## coupling that hurts most and that nothing in the language marks.
static func _collect_reaches(line: String, idx: int, out: Array) -> void:
	var clean := line
	if clean.find("get_parent()") != -1:
		out.append({"kind": "get_parent", "line": idx})
	if clean.find("owner.") != -1:
		out.append({"kind": "owner", "line": idx})
	if clean.find("/root/") != -1:
		out.append({"kind": "absolute_path", "line": idx})
	if clean.find("get_tree().root") != -1:
		out.append({"kind": "tree_root", "line": idx})
	if clean.find("find_child(") != -1 or clean.find("find_parent(") != -1:
		out.append({"kind": "find_node", "line": idx})
	# $"../.." and get_node("../..") both climb out of the scene
	if clean.find("\"..") != -1 or clean.find("('..") != -1 or clean.find("$..") != -1:
		out.append({"kind": "parent_path", "line": idx})


static func _string_arg_after(line: String, keyword: String) -> String:
	var at := line.find(keyword + "(")
	if at == -1:
		return ""
	var open_q := line.find("\"", at)
	if open_q == -1:
		return ""
	var close_q := line.find("\"", open_q + 1)
	if close_q == -1:
		return ""
	return line.substr(open_q + 1, close_q - open_q - 1)


## Inferred-edge reference sites (§5.3). Falls out of the same pass, which is why
## blue edges are nearly free.
static func _collect_refs(line: String, idx: int, refs: Array) -> void:
	for kw in ["preload", "load"]:
		var at := line.find(kw + "(")
		while at != -1:
			# "load(" also matches inside "preload(" — require a word boundary so
			# a single preload isn't counted as two references.
			if at > 0 and (line[at - 1].is_valid_identifier() or line[at - 1].is_valid_int()):
				at = line.find(kw + "(", at + 1)
				continue
			var open_q := line.find("\"", at)
			if open_q != -1:
				var close_q := line.find("\"", open_q + 1)
				if close_q != -1:
					var target := line.substr(open_q + 1, close_q - open_q - 1)
					if target.ends_with(".gd"):
						refs.append({"kind": kw, "target": target, "line": idx})
			at = line.find(kw + "(", at + 1)


static func _ident_after(line: String, keyword: String) -> String:
	var at := line.find(keyword)
	if at == -1:
		return ""
	var rest := line.substr(at + keyword.length()).strip_edges()
	var ident := ""
	for i in rest.length():
		var c := rest[i]
		# is_valid_identifier() on a single char accepts letters and "_";
		# digits are only legal once we're past the first character.
		if c.is_valid_identifier() or (ident != "" and c.is_valid_int()):
			ident += c
		else:
			break
	return ident
