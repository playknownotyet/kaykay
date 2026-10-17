extends Control
## Dükkânın ekran arayüzü (liste, keşif yazıları, raf kamerası butonları). Ana ekranın katmanında
## durur: oyun dünyası ayrı bir görüntüde (SubViewport) çizildiği için oraya dokunuş / tuş gitmez.
## Çizim ve girdi dükkâna devredilir.

var shop: Node


func _draw() -> void:
	if shop:
		shop._draw_ui()


func _gui_input(event: InputEvent) -> void:
	if shop:
		shop._on_ui_input(event)


func _input(event: InputEvent) -> void:
	if shop:
		shop._on_key(event)
