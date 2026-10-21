class_name LinkDialog
extends PopupPanel

## Resolves both ends of a twine after a drag (§5.2).
##
## The spec described two sequential pickers; one panel showing both ends is the
## same idea with fewer modal steps. What matters is unchanged: NEITHER card ever
## has to be scrolled to line up two methods.

signal confirmed(from_symbol: String, to_symbol: String, description: String)

const WHOLE_FILE := "◻  Whole file"

var _from_list: ItemList
var _to_list: ItemList
var _desc: LineEdit
var _from_syms: Array = []
var _to_syms: Array = []


func _init() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	root.custom_minimum_size = Vector2(820, 470)
	add_child(root)

	var title := Label.new()
	title.text = "New twine"
	title.add_theme_font_size_override("font_size", 18)
	root.add_child(title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	_from_list = _make_column(cols, "From")
	_to_list = _make_column(cols, "To")

	var dlabel := Label.new()
	dlabel.text = "Description  —  optional, but an unlabelled twine stays a loose end"
	dlabel.add_theme_font_size_override("font_size", 12)
	root.add_child(dlabel)

	_desc = LineEdit.new()
	_desc.placeholder_text = "why are these related?"
	root.add_child(_desc)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(buttons)

	var cancel := Button.new()
	cancel.text = "Cancel  (Esc)"
	cancel.pressed.connect(hide)
	buttons.add_child(cancel)

	var create := Button.new()
	create.text = "Draw twine  (Enter)"
	create.pressed.connect(_emit)
	buttons.add_child(create)

	_desc.text_submitted.connect(func(_t: String) -> void: _emit())


func _make_column(parent: HBoxContainer, heading: String) -> ItemList:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(box)

	var head := Label.new()
	head.name = "Head"
	head.text = heading
	box.add_child(head)

	var list := ItemList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.custom_minimum_size = Vector2(0, 300)
	box.add_child(list)
	return list


## `preselect` is the symbol the drag started on, so the common case is one click.
func open_for(from_file: String, from_syms: Array, preselect: String,
		to_file: String, to_syms: Array) -> void:
	_from_syms = from_syms
	_to_syms = to_syms
	_fill(_from_list, from_file, from_syms, preselect)
	_fill(_to_list, to_file, to_syms, "")
	_desc.text = ""
	popup_centered()
	_desc.grab_focus()


## Used when adopting an inferred edge (§10): the evidence becomes the starting
## description, which the user can accept or rewrite.
func preset_description(text: String) -> void:
	_desc.text = text
	_desc.select_all()


func _fill(list: ItemList, file_key: String, syms: Array, preselect: String) -> void:
	list.clear()
	list.add_item(WHOLE_FILE)
	var select_idx := 0
	for i in syms.size():
		var s: String = syms[i]
		list.add_item(s)
		if s == preselect:
			select_idx = i + 1
	list.select(select_idx)
	list.ensure_current_is_visible()
	var head := list.get_parent().get_node("Head") as Label
	head.text = "%s  —  %s" % [head.text.split("  —  ")[0], file_key.get_file()]


func _selected(list: ItemList, syms: Array) -> String:
	var sel := list.get_selected_items()
	if sel.is_empty() or sel[0] == 0:
		return ""                       # whole file
	return syms[sel[0] - 1]


func _emit() -> void:
	confirmed.emit(
		_selected(_from_list, _from_syms),
		_selected(_to_list, _to_syms),
		_desc.text.strip_edges(),
	)
	hide()
