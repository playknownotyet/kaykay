class_name KaykaySes
extends Node3D
## Kaykay ve çevre sesleri (hepsi "Ortam" yolunda; kulaklık takılıyken bastırılmış duyulur, SesAyar):
##   rüzgâr       hızlandıkça artar (havadayken de)
##   tekerlek     kaykay giderken: düz zeminde yumuşak, Arnavut kaldırımı / çimde kaba; hızla perdesi artar
##   sürtünme 1   fren (ayak / tekerlek yerde kayar)
##   sürtünme 2   sert dönüşte yana kayma
##   grind        ray / kenar kayışı
##   tık          titreşimle birlikte (taş, derz, itiş: SurfaceFeedback.tick)
##   pop          ollie (kuyruk vurur, kaykay kalkar) · iniş: güm + şık şık · şık: binme / inme / çarpma
##   çarpma       araba çarpınca: gövde gümü, sac çatırtısı, kaykayın yerde takırdaması
##   şehir        uzak trafik ve kalabalık uğultusu (meydandan uzaklaştıkça azalır) + yakındaki
##                arabalardan ara sıra korna (konumlu)
## Dükkân içindeyken dış sesler susar.

const MEYDAN := Vector3(195.0, 0.0, 10.0)

var player: SkateController
var feedback: SurfaceFeedback
var traffic: Node

var _loops := {}                # ad -> AudioStreamPlayer
var _shots := {}                # ad -> AudioStreamPlayer (çok sesli)
var _horn: AudioStreamPlayer3D
var _horn_streams: Array[AudioStream] = []
var _horn_t := 8.0
var _ear := 0.0
var _v_s := 0.0                 # yumuşatılmış yatay hız (rüzgâr titremesin)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	SesAyar.setup()
	for ad in ["ruzgar", "tekerlek_asfalt", "tekerlek_kaba", "surtunme_1", "surtunme_2", "grind", "sehir"]:
		var s := SesAyar.load_sound(ad, true)
		if s == null:
			continue
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = SesAyar.ORTAM
		p.volume_db = -80.0
		add_child(p)
		_loops[ad] = p
	for ad in ["tik", "pop", "inis", "sik", "carpma"]:
		var s := SesAyar.load_sound(ad)
		if s == null:
			continue
		var p := AudioStreamPlayer.new()
		p.stream = s
		p.bus = SesAyar.ORTAM
		p.max_polyphony = 6 if ad == "tik" else 3
		add_child(p)
		_shots[ad] = p
	for ad in ["korna_1", "korna_2"]:
		var s := SesAyar.load_sound(ad)
		if s:
			_horn_streams.append(s)
	_horn = AudioStreamPlayer3D.new()
	_horn.bus = SesAyar.ORTAM
	_horn.unit_size = 12.0
	_horn.max_distance = 90.0
	_horn.top_level = true
	add_child(_horn)
	if player:
		player.ollied.connect(func(): _shot("pop", -2.0, _rng.randf_range(0.95, 1.08)))
		player.auto_hopped.connect(func(): _shot("pop", -9.0, 1.1))
		player.landed.connect(_on_landed)
		player.knocked_down.connect(func(): _shot("carpma", 0.0, _rng.randf_range(0.94, 1.04)))
		player.grind_started.connect(func(): _shot("sik", -3.0, 0.8))
		player.mode_changed.connect(func(_f: bool): _shot("sik", -6.0, 1.0))
		player.wall_hit.connect(func(s: float):
			if s > 1.5:
				_shot("sik", linear_to_db(clampf(s / 6.0, 0.25, 1.0)), 0.75))
	if feedback:
		feedback.tick.connect(func(k: float): _shot("tik", linear_to_db(clampf(k, 0.05, 1.0)) - 4.0, _rng.randf_range(0.85, 1.2)))


func _shot(ad: String, db: float, pitch: float) -> void:
	var p: AudioStreamPlayer = _shots.get(ad)
	if p == null or _inside():
		return
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _on_landed(impact: float) -> void:
	if player.on_foot:
		_shot("sik", -14.0 + clampf(impact, 0.0, 6.0), 0.6)
		return
	var k := clampf(0.3 + impact * 0.12, 0.3, 1.0)
	_shot("inis", linear_to_db(k), _rng.randf_range(0.92, 1.05))


func _inside() -> bool:
	return IcMekan.instance != null and IcMekan.instance.is_inside()


## Döngünün sesi (doğrusal 0..1) ve perdesi; neredeyse sessizken durur (işlemci harcamasın)
func _loop(ad: String, target: float, pitch: float, delta: float, rate := 6.0) -> void:
	var p: AudioStreamPlayer = _loops.get(ad)
	if p == null:
		return
	var cur := db_to_linear(p.volume_db) if p.playing else 0.0
	var v := lerpf(cur, target, 1.0 - exp(-rate * delta))
	if v < 0.003 and target <= 0.0:
		if p.playing:
			p.stop()
		p.volume_db = -80.0
		return
	if not p.playing:
		p.play(_rng.randf_range(0.0, maxf(p.stream.get_length() - 0.1, 0.0)))
	p.volume_db = linear_to_db(maxf(v, 0.0001))
	p.pitch_scale = lerpf(p.pitch_scale, pitch, 1.0 - exp(-8.0 * delta))


func _process(delta: float) -> void:
	if player == null:
		return
	# Kulaklık: dış ses bastırılır (yumuşak geçiş)
	_ear = move_toward(_ear, 1.0 if player.earbuds_in else 0.0, delta * 2.5)
	SesAyar.set_earbuds(_ear)
	var inside := _inside()
	var hv := Vector2(player.velocity.x, player.velocity.z).length()
	_v_s = lerpf(_v_s, hv, 1.0 - exp(-3.0 * delta))
	var v := _v_s
	var speed := absf(player.speed)
	var skating := not player.on_foot and player.board_anim == SkateController.BoardAnim.NONE and player.fall_time <= 0.0
	var rolling := skating and player.grounded and not player.grinding and speed > 0.3
	# Rüzgâr
	# Rüzgâr: yürüme hızının altında hiç yok, hızlandıkça artar
	var wind := 0.0 if inside else smoothstep(4.0, 16.0, v) * 0.85 + (0.12 if not player.grounded and v > 5.0 else 0.0)
	_loop("ruzgar", wind, 0.85 + 0.35 * clampf(v / 16.0, 0.0, 1.0), delta, 3.0)
	# Tekerlek (zemin türüne göre)
	var rough := player.floor_surface in ["arnavut", "cim"]
	var roll_k := clampf(speed / 7.0, 0.0, 1.0) * 0.8 if rolling else 0.0
	var roll_pitch := 0.65 + 0.7 * clampf(speed / 13.0, 0.0, 1.0)
	_loop("tekerlek_asfalt", 0.0 if rough else roll_k, roll_pitch, delta, 10.0)
	_loop("tekerlek_kaba", roll_k * 1.05 if rough else 0.0, roll_pitch, delta, 10.0)
	# Fren ve yana kayma
	var braking := rolling and SkateInput.gesture == SkateInput.Gesture.BRAKE and speed > 0.5
	_loop("surtunme_1", clampf(speed / 6.0, 0.25, 1.0) * 0.85 if braking else 0.0, 0.85 + 0.3 * clampf(speed / 8.0, 0.0, 1.0), delta, 14.0)
	var skid := rolling and not braking and speed > 6.0 and absf(SkateInput.steer_target) > 0.8
	_loop("surtunme_2", clampf((speed - 6.0) / 6.0, 0.15, 0.6) if skid else 0.0, 1.0, delta, 8.0)
	# Grind
	var grind_k := clampf(speed / 6.0, 0.35, 1.0) * 0.8 if (skating and player.grinding) else 0.0
	_loop("grind", grind_k, 0.8 + 0.4 * clampf(speed / 9.0, 0.0, 1.0), delta, 16.0)
	# Şehir: meydandan uzaklaştıkça ve tepeye çıktıkça azalır
	var p := player.global_position
	var far := clampf((Vector2(p.x - MEYDAN.x, p.z - MEYDAN.z).length() - 260.0) / 380.0, 0.0, 1.0)
	var high := clampf((p.y - 25.0) / 50.0, 0.0, 1.0)
	var city := 0.0 if inside else 0.32 * (1.0 - 0.75 * far) * (1.0 - 0.7 * high)
	_loop("sehir", city, 1.0, delta, 1.5)
	_update_horns(delta, inside, city)


## Ara sıra yakındaki bir arabadan korna (konumlu, 15-60 m)
func _update_horns(delta: float, inside: bool, city: float) -> void:
	if _horn_streams.is_empty() or inside or city < 0.15:
		return
	_horn_t -= delta
	if _horn_t > 0.0:
		return
	_horn_t = _rng.randf_range(7.0, 20.0)
	var cars: Array = []
	if traffic and "_cars" in traffic:
		cars = traffic._cars
	var pp := player.global_position
	var picks := []
	for c in cars:
		if c is Node3D and is_instance_valid(c):
			var d := (c as Node3D).global_position.distance_to(pp)
			if d > 12.0 and d < 60.0:
				picks.append(c)
	if picks.is_empty():
		return
	var car: Node3D = picks[_rng.randi() % picks.size()]
	_horn.global_position = car.global_position + Vector3.UP * 0.8
	_horn.stream = _horn_streams[_rng.randi() % _horn_streams.size()]
	_horn.pitch_scale = _rng.randf_range(0.92, 1.08)
	_horn.volume_db = -4.0
	_horn.play()
