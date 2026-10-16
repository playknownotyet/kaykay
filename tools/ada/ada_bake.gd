extends SceneTree
## Adayı kurup hazır sahne olarak kaydeder (oyun açılışta beklemesin):
##   Godot --headless --path . --script tools/ada/ada_bake.gd
## Önce: node tools/ada/ada_export.js  (plan -> assets/ada)

const OUT := "res://scenes/ada.scn"


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var ada := AdaBuilder.new()
	ada.name = "Ada"
	root.add_child(ada)
	ada.build()
	_own(ada, ada)
	var scene := PackedScene.new()
	var err := scene.pack(ada)
	if err == OK:
		err = ResourceSaver.save(scene, OUT, ResourceSaver.FLAG_COMPRESS)
	print("ADA: kaydedildi %s (%d düğüm) hata=%d, %d ms" % [OUT, _count(ada), err, Time.get_ticks_msec() - t0])
	quit()


func _own(node: Node, owner_node: Node) -> void:
	for c in node.get_children():
		c.owner = owner_node
		_own(c, owner_node)


func _count(node: Node) -> int:
	var c := 1
	for ch in node.get_children():
		c += _count(ch)
	return c
