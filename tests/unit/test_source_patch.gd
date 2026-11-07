extends EdTestCase
## Ported from main:src/core/commands/SourcePatch.test.ts. The UTF-16
## surrogate cases have no equivalent: Godot String offsets are code points.


func test_applies_non_overlapping_edits() -> void:
	eq(EdSourcePatch.apply("abcde", [p(1, 2, "X"), p(4, 4, "!")]), "aXcd!e")


func test_validate_returns_sorted_copies_without_mutating_input() -> void:
	var first := p(3, 4, "D")
	var second := p(0, 1, "A")
	var patches := [first, second]
	var v := EdSourcePatch.validate("abcd", patches)
	eq(v["ok"], true)
	eq(patches, [first, second], "caller array unchanged")
	eq(v["patches"], [second, first])


func test_structured_error_for_out_of_range() -> void:
	var v := EdSourcePatch.validate("abc", [p(0, 4, "x")])
	eq(v, {"ok": false, "error": {"code": "out-of-range", "patch_index": 0, "message": "Patch 0 ends at 4, outside source length 3."}})


func test_rejects_malformed_patches() -> void:
	var cases := [
		[[{"start": 0.5, "end": 1, "replacement": ""}], "non-integer"],
		[[p(-1, 0, "")], "negative-offset"],
		[[p(2, 1, "")], "reversed-span"],
		[[p(0, 4, "")], "out-of-range"],
		[[{"start": 0, "end": 1, "replacement": 5}], "invalid-replacement"],
		[["not a patch"], "invalid-patch"],
	]
	for c in cases:
		var v := EdSourcePatch.validate("abc", c[0])
		eq(v["ok"], false, c[1])
		eq(v.get("error", {}).get("code"), c[1])
		eq(EdSourcePatch.apply("abc", c[0]), null, "apply refuses " + c[1])
		eq(EdSourcePatch.invert("abc", c[0]), null, "invert refuses " + c[1])


func test_rejects_overlap_with_conflicting_index() -> void:
	var v := EdSourcePatch.validate("abc", [p(0, 2, "x"), p(1, 3, "y")])
	eq(v["error"]["code"], "overlap")
	eq(v["error"]["patch_index"], 1)
	eq(v["error"]["conflicting_patch_index"], 0)


func test_rejects_same_start_combinations() -> void:
	for set in [[p(1, 1, "x"), p(1, 1, "y")], [p(1, 2, "x"), p(1, 1, "y")]]:
		var v := EdSourcePatch.validate("abc", set)
		eq(v["error"]["code"], "ambiguous-same-start")


func test_allows_adjacent_edits_and_insertion_after_replacement() -> void:
	var set := [p(0, 1, "A"), p(1, 2, "B"), p(2, 2, "!")]
	eq(EdSourcePatch.validate("abc", set)["ok"], true)
	eq(EdSourcePatch.apply("abc", set), "AB!c")


func test_allows_insertions_at_boundaries() -> void:
	eq(EdSourcePatch.apply("abc", [p(0, 0, "<")]), "<abc")
	eq(EdSourcePatch.apply("abc", [p(3, 3, ">")]), "abc>")


func test_offsets_are_code_points() -> void:
	var src := "A😀B"
	eq(src.length(), 3)
	eq(EdSourcePatch.apply(src, [p(1, 2, "X")]), "AXB")


func test_inverse_merges_adjacent_patches() -> void:
	var src := "abcdef"
	var set := [p(1, 2, "XX"), p(2, 4, ""), p(5, 5, "!")]
	var after: String = EdSourcePatch.apply(src, set)
	eq(after, "aXXe!f")
	var inv: Array = EdSourcePatch.invert(src, set)
	eq(inv.size(), 2, "adjacent patches merge")
	eq(EdSourcePatch.apply(after, inv), src)


func test_exhaustive_round_trip_against_naive_slicing() -> void:
	# Every valid set of up to two patches over a short source: apply must
	# equal naive right-to-left slicing, and the inverse must restore it.
	var src := "abc"
	var singles: Array = []
	for s in range(0, 4):
		for e in range(s, 4):
			for r in ["", "Z", "YY"]:
				singles.append(p(s, e, r))
	var tried := 0
	for a in singles:
		_check_round_trip(src, [a])
		tried += 1
		for b in singles:
			var v := EdSourcePatch.validate(src, [a, b])
			if not v["ok"]:
				continue
			_check_round_trip(src, [a, b])
			tried += 1
	ok(tried > 200, "enough combinations tried (%d)" % tried)


func _check_round_trip(src: String, set: Array) -> void:
	var sorted := set.duplicate()
	sorted.sort_custom(func(x, y): return x["start"] > y["start"])
	var naive := src
	for q in sorted:
		naive = naive.substr(0, q["start"]) + q["replacement"] + naive.substr(q["end"])
	var applied = EdSourcePatch.apply(src, set)
	if applied != naive:
		eq(applied, naive, str(set))
		return
	var inv = EdSourcePatch.invert(src, set)
	if EdSourcePatch.apply(applied, inv) != src:
		eq(EdSourcePatch.apply(applied, inv), src, "inverse of " + str(set))
	else:
		checks += 1


func test_sequential_composer_matches_sequential_application() -> void:
	var src := "<a><b/></a>"
	var c := EdSequentialPatchComposer.new(src)
	var step1 := [p(3, 3, "<x/>")]
	var mid: String = EdSourcePatch.apply(src, step1)
	c.apply(step1)
	var step2 := [p(0, 2, "<A"), p(mid.length() - 2, mid.length() - 1, "A")]
	var final_text: String = EdSourcePatch.apply(mid, step2)
	c.apply(step2)
	eq(EdSourcePatch.apply(src, c.patches()), final_text)
