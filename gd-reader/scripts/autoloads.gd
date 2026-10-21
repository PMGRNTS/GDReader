class_name Autoloads
extends RefCounted

## Reads the [autoload] block from the target project's project.godot.
##
## Autoloads are the classic tight coupling in a Godot project: any file can
## touch any singleton with no import and no declaration, so the dependency is
## invisible in the source. Resolving the names makes those edges real.

static func scan(project_root: String) -> Dictionary:
	var out := {}
	var path := project_root.path_join("project.godot")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out

	var in_block := false
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("["):
			in_block = line == "[autoload]"
			continue
		if not in_block or line.is_empty() or line.begins_with(";"):
			continue
		var eq := line.find("=")
		if eq == -1:
			continue
		var name := line.substr(0, eq).strip_edges()
		var value := line.substr(eq + 1).strip_edges()
		value = value.lstrip("\"").rstrip("\"")
		# A leading * means "enabled"; the rest is a res:// path.
		value = value.trim_prefix("*")
		if value.ends_with(".gd"):
			out[name] = value
	f.close()
	return out
