class_name SurfaceFeedback
extends Node
## Yüzey ve olay geri bildirimi: cihaz titreşimi + kameranın mikro titremesi.
## İkisi de aynı kaynaktan beslenir, böylece his ve görüntü birbirini tutar.
##
## Yuvarlanma: titreşim zamanla değil, KATEDİLEN MESAFEYLE üretilir. Arnavut
## kaldırımında her taş bir "tık"tır: yavaşken tek tek hissedilir, hızlanınca
## yoğun bir gürültüye dönüşür. Grind'de ise ray türüne göre sürekli vızıltı.

## Yerde yuvarlanma profilleri.
##  spacing: tıklar arası mesafe (m, 0 = tık yok), amp: titreşim şiddeti,
##  vary: rastgelelik, cam: kamera titremesi (bakış noktasında m), bump: kamera sekmesi (m)
const ROLL := {
	"asfalt": {"spacing": 0.0, "amp": 0.0, "vary": 0.0, "cam": 0.002, "bump": 0.0},
	"arnavut": {"spacing": 0.13, "amp": 0.42, "vary": 0.45, "cam": 0.011, "bump": 0.004},
	"beton": {"spacing": 1.2, "amp": 0.2, "vary": 0.2, "cam": 0.004, "bump": 0.002},   # derz araları
	"tahta": {"spacing": 0.61, "amp": 0.14, "vary": 0.3, "cam": 0.003, "bump": 0.0015}, # kontrplak ekleri
	"metal": {"spacing": 0.0, "amp": 0.0, "vary": 0.0, "cam": 0.003, "bump": 0.0},
	"cim": {"spacing": 0.3, "amp": 0.16, "vary": 0.7, "cam": 0.006, "bump": 0.002},
}
## Grind profilleri. hz: vızıltı sıklığı, start: ilk temas ("klank") şiddeti
const GRIND := {
	"metal": {"hz": 34.0, "amp": 0.3, "vary": 0.25, "cam": 0.007, "start": 0.85},
	"beton": {"hz": 17.0, "amp": 0.48, "vary": 0.55, "cam": 0.011, "start": 0.7},
}

## Kamera titremesi genel çarpanı (panelden)
@export var camera_strength := 1.4
## Yürürken / koşarken adım titreşimi (varsayılan kapalı)
@export var footstep_amp := 0.0

## Kameranın okuyacağı değerler
var camera_rumble := 0.0            # sürekli titreme genliği (m)
signal bump(strength: float)        # tek bir sekme (taş, iniş, çarpma)

var controller: SkateController
var _dist := 0.0
var _next_bump := 0.1
var _buzz_t := 0.0
var _brake_t := 0.0
var _prev_contact := false
var _wall_cooldown := 0.0
var _step_dist := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	controller = get_parent() as SkateController
	controller.ollied.connect(func(): Haptics.pulse(14, 0.55))
	controller.double_jumped.connect(func(): Haptics.pulse(10, 0.3))
	controller.landed.connect(_on_landed)
	controller.grind_started.connect(func():
		var g: Dictionary = GRIND.get(controller.grind_surface(), GRIND["metal"])
		Haptics.pulse(30, g.start)
		bump.emit(0.006))
	controller.grind_ended.connect(func(): Haptics.pulse(12, 0.25))
	controller.wall_hit.connect(_on_wall_hit)
	controller.stumbled.connect(func():
		Haptics.pulse(45, 0.85)
		bump.emit(0.012))
	controller.mode_changed.connect(func(_on_foot: bool): Haptics.pulse(16, 0.35))


func _physics_process(delta: float) -> void:
	_wall_cooldown = maxf(_wall_cooldown - delta, 0.0)
	var speed := absf(controller.speed)
	var sf := clampf(speed / 6.0, 0.0, 1.3)   # hız etkisi
	var rumble := 0.0

	if controller.on_foot or controller.board_anim != SkateController.BoardAnim.NONE:
		_footsteps(speed, delta)
	elif controller.grinding:
		var g: Dictionary = GRIND.get(controller.grind_surface(), GRIND["metal"])
		_buzz_t += delta
		var period: float = 1.0 / g.hz
		if _buzz_t >= period:
			_buzz_t = fmod(_buzz_t, period)
			var a: float = g.amp * clampf(speed / 5.0, 0.5, 1.3) * _rng.randf_range(1.0 - g.vary, 1.0)
			Haptics.pulse(period * 1000.0 * 0.9, a)
		rumble = g.cam * clampf(speed / 5.0, 0.5, 1.3)
	elif controller.grounded:
		var r: Dictionary = ROLL.get(controller.floor_surface, ROLL["asfalt"])
		if r.spacing > 0.0 and speed > 0.3:
			_dist += speed * delta
			if _dist >= _next_bump:
				_dist = 0.0
				_next_bump = r.spacing * _rng.randf_range(0.7, 1.3)
				var k := _rng.randf_range(1.0 - r.vary, 1.0)
				Haptics.pulse(14, r.amp * maxf(sf, 0.3) * k)
				if r.bump > 0.0:
					bump.emit(r.bump * maxf(sf, 0.3) * k)
		rumble = r.cam * sf
		_brake_and_push(speed, delta)
	camera_rumble = lerpf(camera_rumble, rumble * camera_strength, 1.0 - exp(-12.0 * delta))


func _brake_and_push(speed: float, delta: float) -> void:
	var inp := SkateInput
	# Fren: ayak yerde sürtüyor -> hızla artan sürekli hırıltı
	if inp.gesture == SkateInput.Gesture.BRAKE and speed > 0.4:
		_brake_t += delta
		if _brake_t >= 0.045:
			_brake_t = 0.0
			Haptics.pulse(40, 0.12 + 0.28 * minf(speed / 6.0, 1.0) * _rng.randf_range(0.7, 1.0))
	# İtme: ayak yere değdiği an hafif tık
	var contact: bool = inp.foot_contact and (inp.gesture == SkateInput.Gesture.PUSH or inp.gesture == SkateInput.Gesture.REVERSE)
	if contact and not _prev_contact:
		Haptics.pulse(10, 0.2)
	_prev_contact = contact


func _footsteps(speed: float, delta: float) -> void:
	if footstep_amp <= 0.0 or speed < 0.3 or not controller.grounded:
		return
	_step_dist += speed * delta
	var stride := 0.55 if speed < 2.6 else 1.1
	if _step_dist >= stride:
		_step_dist = 0.0
		Haptics.pulse(10, footstep_amp * (1.0 if speed < 2.6 else 1.6))


func _on_landed(impact: float) -> void:
	# Darbenin şiddetine göre: hafif iniş kısa tık, sert iniş uzun güm
	var a := clampf(0.25 + impact * 0.12, 0.25, 1.0)
	Haptics.pulse(18.0 + impact * 5.0, a)
	bump.emit(0.004 + clampf(impact, 0.0, 8.0) * 0.0015)


func _on_wall_hit(strength: float) -> void:
	if strength < 1.0 or _wall_cooldown > 0.0:
		return
	_wall_cooldown = 0.25
	Haptics.pulse(35, clampf(strength / 5.0, 0.35, 1.0))
	bump.emit(clampf(strength * 0.002, 0.003, 0.012))
