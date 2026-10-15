extends Node
## Kol sallanması eksen testi: ArmSway'e bilinen açılar verip elin nereye gittiğini ölçer.
##   Godot --headless --path . res://tests/kol_test.tscn
## Görsel uzay: ileri -Z (yani +Z = geri), karakterin solu -X.

func _ready() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var vis: Node3D = main.player.get_node("Visual")
	for i in 20:
		await get_tree().physics_frame
	vis.set_physics_process(false)   # yay benzetimini durdur, açıları elle ver
	var sway: ArmSway = vis._sway
	var skel: Skeleton3D = vis.find_child("Skeleton3D", true, false)

	var cases := [["sıfır", Vector2.ZERO], ["geri 0.5", Vector2(0.5, 0)], ["dışa 0.5", Vector2(0, 0.5)]]
	var base := Vector3.ZERO
	for c in cases:
		sway.left = c[1]
		sway.right = c[1]
		for i in 3:
			await get_tree().process_frame
		# Düzenleyicilerin etkisi geçici: eli iskelet güncellendiği anda oku
		await skel.skeleton_updated
		var l := _hand(vis, skel, "hand.L")
		var r := _hand(vis, skel, "hand.R")
		if c[0] == "sıfır":
			base = l
			print("KOLTEST sıfır: sol el ", l, " sağ el ", r)
		else:
			var d := l - base
			print("KOLTEST %s: sol el farkı x=%+.3f (dışa = -x) z=%+.3f (geri = +z)" % [c[0], d.x, d.z])
	get_tree().quit()


func _hand(vis: Node3D, skel: Skeleton3D, bone: String) -> Vector3:
	var g := skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone))
	return vis.global_transform.affine_inverse() * g.origin
