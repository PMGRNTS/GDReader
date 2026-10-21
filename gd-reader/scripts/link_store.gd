class_name LinkStore
extends RefCounted

## Persistence for user-authored twine (§6).
##
## Lives in the TARGET project at .gdreader/links.json — shared, diffable,
## committable. Holds annotation only: no layout, no camera, no scroll position.
## Those go in user:// because nobody should diff someone else's viewport.

const DIR_NAME := ".gdreader"
const FILE_NAME := "links.json"

var links: Array = []            # [{ id, from:{file,symbol}, to:{file,symbol}, description }]
var _root := ""


func load_from(project_root: String) -> void:
	_root = project_root
	links.clear()
	var path := _path()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary and data.has("links"):
		var raw: Array = data["links"]
		for l in raw:
			if l is Dictionary and l.has("from") and l.has("to"):
				links.append(l)


func save() -> void:
	if _root == "":
		return
	var dir_path := _root.path_join(DIR_NAME)
	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)
	var f := FileAccess.open(_path(), FileAccess.WRITE)
	if f == null:
		push_warning("GDReader: cannot write %s" % _path())
		return
	f.store_string(JSON.stringify({"version": 1, "links": links}, "  "))
	f.close()


func add(from_file: String, from_sym: String, to_file: String, to_sym: String,
		description: String) -> Dictionary:
	var link := {
		"id": "%x%x" % [Time.get_unix_time_from_system(), randi() % 0xffff],
		"from": {"file": from_file, "symbol": from_sym},
		"to": {"file": to_file, "symbol": to_sym},
		"description": description,
	}
	links.append(link)
	save()
	return link


func remove(id: String) -> void:
	for i in links.size():
		var l: Dictionary = links[i]
		if l.get("id", "") == id:
			links.remove_at(i)
			save()
			return


## Every link with an endpoint in this file — the basis for the §5.4 clutter rule
## and for Tab-cycling (§5.5).
func links_touching(file_key: String) -> Array:
	var out: Array = []
	for l in links:
		if l["from"]["file"] == file_key or l["to"]["file"] == file_key:
			out.append(l)
	return out


func _path() -> String:
	return _root.path_join(DIR_NAME).path_join(FILE_NAME)
