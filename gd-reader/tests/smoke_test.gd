extends SceneTree

## Headless checks for the parts a screenshot can't show.
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path gd-reader \
##       --script res://tests/smoke_test.gd

var _failed := 0
var _passed := 0


func _init() -> void:
	_test_parser()
	_test_anchor_states()
	_test_link_store()
	_test_zoom_breakpoints()
	_test_fuzzy_score()
	_test_coupling()
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


## §4 breakpoints. Pure mapping, so it can be checked without a viewport.
func _test_zoom_breakpoints() -> void:
	check("100% is Read", Card.detail_for_zoom(1.0), Card.Detail.READ)
	check("60% is Read", Card.detail_for_zoom(0.60), Card.Detail.READ)
	check("50% is Read (boundary)", Card.detail_for_zoom(0.50), Card.Detail.READ)
	check("49% is Skim", Card.detail_for_zoom(0.49), Card.Detail.SKIM)
	check("25% is Skim (boundary)", Card.detail_for_zoom(0.25), Card.Detail.SKIM)
	check("24% is Map", Card.detail_for_zoom(0.24), Card.Detail.MAP)
	check("8% is Map", Card.detail_for_zoom(0.08), Card.Detail.MAP)


## §3.7 fuzzy matching. Pure, so the ranking can be pinned down in tests.
func _test_fuzzy_score() -> void:
	var player := "res://player/player.gd"
	var health := "res://ui/health_bar.gd"

	check("empty query matches", Finder.score("", player) >= 0, true)
	check("non-subsequence misses", Finder.score("zzz", player), -1)
	check("exact substring matches", Finder.score("player", player) >= 0, true)

	# Initials across path segments should find the file — "phb" for
	# player/health_bar is the whole point of fuzzy jump.
	check("initials match", Finder.score("uhb", health) >= 0, true)

	# A word-start match must outrank the same letters buried mid-token.
	check("word starts outrank mid-token",
		Finder.score("hb", health) > Finder.score("hb", "res://x/those_bits.gd"), true)

	# The "res://" prefix must not be matchable: every candidate has it, so a query
	# scoring inside it ranks unrelated files above real word-start matches.
	check("prefix is not matchable",
		Finder.score("sm", "res://player/state_machine.gd")
			> Finder.score("sm", "res://ui/pause_menu.gd"), true)
	check("prefix-only match fails", Finder.score("res", "res://player/player.gd"), -1)

	# A query matching only the FOLDER ties every file in it, so the filename is
	# weighted: "play" under player/ must still land on player.gd.
	check("filename beats folder-only match",
		Finder.score("play", "res://player/player.gd")
			> Finder.score("play", "res://player/inventory.gd"), true)

	# Consecutive runs outrank scattered hits.
	check("runs outrank scatter",
		Finder.score("play", player) > Finder.score("pyr", player), true)


## §10 coupling detection. Each rule is pinned so a parser change can't quietly
## stop finding a kind of edge.
func _test_coupling() -> void:
	var index := {
		"res://a.gd": GDParser.parse("extends Base\nfunc go():\n\tGlobals.score += 1\n"),
		"res://base.gd": GDParser.parse("class_name Base\nextends Node2D\nsignal died\n"),
		"res://spawn.gd": GDParser.parse("extends Node\nfunc f():\n\tadd_to_group(\"mobs\")\n"),
		"res://hunt.gd": GDParser.parse("extends Node\nfunc f():\n\tget_tree().get_nodes_in_group(\"mobs\")\n"),
		"res://ear.gd": GDParser.parse("extends Node\nfunc _on_died() -> void:\n\tpass\n"),
		"res://globals.gd": GDParser.parse("extends Node\nvar score := 0\n"),
	}
	var edges := Analyzer.build(index, {"Globals": "res://globals.gd"})

	check("extends by class_name detected", _edge_kind(edges, "res://a.gd", "res://base.gd", "extends"), true)
	check("autoload detected", _edge_kind(edges, "res://a.gd", "res://globals.gd", "autoload"), true)
	check("group pairs querier to joiner",
		_edge_kind(edges, "res://hunt.gd", "res://spawn.gd", "group"), true)
	check("signal handler pairs to declarer",
		_edge_kind(edges, "res://ear.gd", "res://base.gd", "signal"), true)

	# Engine types must not become project edges, or Node2D would couple
	# everything to everything.
	check("engine base type is not an edge",
		_edge_kind(edges, "res://base.gd", "res://base.gd", "type"), false)
	for e in edges:
		check("no self edges", e["from_file"] != e["to_file"], true)

	# Inheritance must outrank a shared group string.
	check("extends outweighs group",
		_weight_of(edges, "res://a.gd", "res://base.gd")
			> _weight_of(edges, "res://hunt.gd", "res://spawn.gd"), true)

	check("reach counts tree-climbing",
		Analyzer.reach_score(GDParser.parse("func f():\n\tget_parent().x = 1\n\towner.y = 2\n")), 2)
	check("plain code has no reach",
		Analyzer.reach_score(GDParser.parse("func f():\n\tvar a := 1\n")), 0)


func _edge_kind(edges: Array, from_file: String, to_file: String, kind: String) -> bool:
	for e in edges:
		if e["from_file"] == from_file and e["to_file"] == to_file:
			return e["kinds"].has(kind)
	return false


func _weight_of(edges: Array, from_file: String, to_file: String) -> float:
	for e in edges:
		if e["from_file"] == from_file and e["to_file"] == to_file:
			return e["weight"]
	return 0.0


func check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("FAIL  %s\n        expected: %s\n        actual:   %s" % [label, expected, actual])


func _test_parser() -> void:
	var src := "extends Node2D\nclass_name Thing\n\nconst SPEED := 3\nsignal died\n\nfunc _ready() -> void:\n\tpass\n\nfunc take_damage(n: int) -> void:\n\tpass\n"
	var p := GDParser.parse(src)

	check("extends", p["extends_name"], "Node2D")
	check("class_name", p["class_name_"], "Thing")

	var by_name := {}
	for s in p["symbols"]:
		by_name["%s %s" % [s["kind"], s["name"]]] = s["line"]

	# Lines are 0-based and must be exact — anchor clamping depends on them.
	check("func _ready line", by_name.get("func _ready"), 6)
	check("func take_damage line", by_name.get("func take_damage"), 9)
	check("signal died line", by_name.get("signal died"), 4)
	check("const SPEED line", by_name.get("const SPEED"), 3)

	var refs: Array = GDParser.parse("var a := preload(\"res://x/y.gd\")\n")["refs"]
	check("preload ref count", refs.size(), 1)
	check("preload target", refs[0]["target"] if refs.size() > 0 else "", "res://x/y.gd")


## The four degradation states of §5.1 — the twine must never simply vanish.
func _test_anchor_states() -> void:
	var card := Card.new()
	card.total_lines = 400
	card.symbols = {"func near": 10, "func far_down": 300, "func far_up": 2}

	card.scroll_line = 0.0
	check("visible anchor", card.anchor_info("func near")["state"], "exact")
	check("below anchor", card.anchor_info("func far_down")["state"], "below")

	card.scroll_line = 100.0
	check("above anchor", card.anchor_info("func far_up")["state"], "above")

	check("whole-file anchor", card.anchor_info("")["state"], "dock")
	check("missing symbol is broken", card.anchor_info("func gone")["state"], "broken")

	# Below Read zoom a card can't resolve lines, so every anchor docks (§5.1) —
	# but a broken one must stay broken, or a refactor would hide itself when you
	# zoomed out.
	card.detail = Card.Detail.SKIM
	check("skim docks exact anchors", card.anchor_info("func near")["state"], "dock")
	check("skim keeps broken broken", card.anchor_info("func gone")["state"], "broken")
	card.detail = Card.Detail.MAP
	check("map docks anchors", card.anchor_info("func far_down")["state"], "dock")
	card.detail = Card.Detail.READ

	# An exact anchor must land inside the text area, not in the header.
	card.scroll_line = 0.0
	var y: float = card.anchor_info("func near")["y"]
	check("exact anchor below header", y > Card.HEADER_H, true)
	check("exact anchor above bottom", y < Card.H, true)

	card.free()


func _test_link_store() -> void:
	var root := OS.get_user_data_dir().path_join("smoke_project")
	DirAccess.make_dir_recursive_absolute(root)

	var store := LinkStore.new()
	store.load_from(root)
	store.links.clear()
	store.save()

	store.add("res://a.gd", "func one", "res://b.gd", "func two", "because")
	store.add("res://a.gd", "", "res://c.gd", "", "")

	var reloaded := LinkStore.new()
	reloaded.load_from(root)
	check("round-trip count", reloaded.links.size(), 2)
	check("round-trip symbol", reloaded.links[0]["from"]["symbol"], "func one")
	check("round-trip description", reloaded.links[0]["description"], "because")
	check("links touching a.gd", reloaded.links_touching("res://a.gd").size(), 2)
	check("links touching b.gd", reloaded.links_touching("res://b.gd").size(), 1)
	check("links touching d.gd", reloaded.links_touching("res://d.gd").size(), 0)

	var id: String = reloaded.links[0]["id"]
	reloaded.remove(id)
	var after := LinkStore.new()
	after.load_from(root)
	check("remove persists", after.links.size(), 1)
