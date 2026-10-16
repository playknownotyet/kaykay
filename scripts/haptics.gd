class_name Haptics
extends Node
## Cihaz titreşimi. Oyundaki tüm titreşimler Haptics.pulse() ile buradan geçer.
##
## - Telefonda: Input.vibrate_handheld (süre + şiddet; Android 8+, iOS 13+).
##   Bilgisayarda titreşim yok (test telefonda yapılır).
## - Hız sınırı: titreşim motoru saniyede sınırlı sayıda darbe verebilir. Sınırı aşan
##   zayıf darbeler atlanır; daha güçlü bir olay (iniş, çarpma) her zaman araya girer.
## - En kısa darbe: ucuz (ERM) motorlar çok kısa darbeleri hissettiremez.

static var instance: Haptics

@export var enabled := true
## Genel titreşim gücü çarpanı
@export var strength := 2.0
## En kısa darbe süresi (ms)
@export var min_pulse_ms := 12.0
## Saniyedeki en fazla darbe
@export var max_rate_hz := 28.0

## Gönderilen darbe sayısı (otomatik testler için)
var pulse_count := 0

var _last_time := -10.0
var _last_amp := 0.0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


static func pulse(duration_ms: float, amplitude: float) -> void:
	if instance:
		instance._pulse(duration_ms, amplitude)


func _pulse(duration_ms: float, amplitude: float) -> void:
	if not enabled:
		return
	var amp := clampf(amplitude * strength, 0.0, 1.0)
	if amp < 0.02:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var since := now - _last_time
	# Son darbenin etkisi zamanla söner; yeni darbe ancak sınır aşılmadıysa ya da
	# belirgin şekilde daha güçlüyse gönderilir.
	var decayed := _last_amp * exp(-since * 20.0)
	if since < 1.0 / max_rate_hz and amp <= decayed * 1.25:
		return
	var ms := maxf(duration_ms, min_pulse_ms)
	_last_time = now
	_last_amp = amp
	pulse_count += 1
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(int(ms), amp)
