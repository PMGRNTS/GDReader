class_name ProjectScanner
extends RefCounted

## Walks a target Godot project and produces the row/column model of §2.1.
##
## Row  = folder containing at least one .gd
## Cols = its .gd files, alphabetical (§2.1 — order is never user data)
##
## Excluded entirely: addons/, .godot/, hidden dirs, and every non-.gd file (§2.1, §9).

const EXCLUDED_DIRS := ["addons", ".godot", ".git", ".import"]


## Returns an Array of row dictionaries, ordered root-first then depth-first
## alphabetical, which reads top-to-bottom the way the tree does.
##   {
##     rel_path: "scenes/enemies",   # "" for the project root
##     display:  "res://scenes/enemies/",
##     depth:    2,
##     files: [ { name, abs_path, rel_path }, ... ]
##   }
static func scan(root_abs: String) -> Array:
	var rows: Array = []
	_walk(root_abs, "", rows)
	return rows


static func _walk(abs_dir: String, rel_dir: String, rows: Array) -> void:
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("GDReader: cannot open %s" % abs_dir)
		return

	var files: Array[String] = []
	var subdirs: Array[String] = []

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir():
			if not entry.begins_with(".") and not EXCLUDED_DIRS.has(entry):
				subdirs.append(entry)
		elif entry.ends_with(".gd"):
			files.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()

	files.sort()
	subdirs.sort()

	if not files.is_empty():
		var file_entries: Array = []
		for f in files:
			file_entries.append({
				"name": f,
				"abs_path": abs_dir.path_join(f),
				"rel_path": f if rel_dir == "" else rel_dir + "/" + f,
			})
		rows.append({
			"rel_path": rel_dir,
			"display": "res://" + ("" if rel_dir == "" else rel_dir + "/"),
			"depth": 0 if rel_dir == "" else rel_dir.split("/").size(),
			"files": file_entries,
		})

	for sub in subdirs:
		_walk(abs_dir.path_join(sub), sub if rel_dir == "" else rel_dir + "/" + sub, rows)


## True if the directory looks like a Godot project root.
static func is_project_root(abs_dir: String) -> bool:
	return FileAccess.file_exists(abs_dir.path_join("project.godot"))
