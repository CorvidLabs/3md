extends SceneTree

const Parser = preload("res://addons/threemd/parser.gd")
const Errors = preload("res://addons/threemd/error.gd")
const Editing = preload("res://addons/threemd/editing.gd")
const Planes = preload("res://addons/threemd/plane.gd")

const SOURCE := """---
3md: \"1.0\"
axis: \"layer\"
title: \"Edit\"
---

@plane z=0 label=\"Ground\" 3md-id=\"ground\"
Floor

@plane z=1 label=\"HUD\" 3md-id=\"hud\"
Map
"""

func fail(message: String) -> void:
	print("FAIL ", message)
	quit(1)

func _init() -> void:
	var parsed: Variant = Parser.parse(SOURCE)
	if Errors.is_error(parsed):
		fail("parse")
		return
	var snap: Variant = Editing.snapshot(parsed)
	if Errors.is_error(snap):
		fail("snapshot " + str(snap.code))
		return
	var removed: Variant = Editing.apply({
		"expected_revision": snap["revision"],
		"operations": [{"kind": "remove", "id": "hud"}],
	}, snap)
	if Errors.is_error(removed):
		fail("remove " + str(removed.code) + " " + str(removed.message))
		return
	if removed["document"].planes.size() != 1 or str(removed["document"].planes[0].label) != "Ground":
		fail("shape")
		return
	var stale: Variant = Editing.apply({
		"expected_revision": "stale",
		"operations": [{"kind": "remove", "id": "ground"}],
	}, snap)
	if not Errors.is_error(stale) or str(stale.code) != "staleRevision":
		fail("stale")
		return
	var bare: Variant = Parser.parse("---\n3md: \"1.0\"\naxis: \"layer\"\n---\n\nHello\n")
	if Errors.is_error(bare):
		fail("bare parse")
		return
	var adopted: Variant = Editing.adopt_document(bare)
	if Errors.is_error(adopted):
		fail("adopt " + str(adopted.code))
		return
	if str(Editing.stable_id(adopted.planes[0])) != "plane-1":
		fail("adopt id " + str(Editing.stable_id(adopted.planes[0])))
		return
	var plane = Planes.new()
	plane.z = 2.0
	plane.label = "Sky"
	plane.attributes = {"3md-id": "sky"}
	plane.body = "Clouds"
	var inserted: Variant = Editing.apply({
		"expected_revision": removed["revision"],
		"operations": [{"kind": "insert", "at": 1, "plane": plane}],
	}, removed)
	if Errors.is_error(inserted) or inserted["document"].planes.size() != 2:
		fail("insert")
		return
	print("EDIT OK")
	quit(0)
