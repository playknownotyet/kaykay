class_name SesAyar
## Ses düzeni. Oyunun bütün çevre ve kaykay sesleri "Ortam" yolundan geçer; radyo "Radyo" yolundan
## (süzülmez). Kulaklık takılıyken (müzik çalar açık) Ortam yolunun tizleri kısılır ve sesi biraz
## düşer: dış ses kulaklığın arkasından, bastırılmış gibi duyulur.
##
## Sesler assets/ses/ altında; aynı adla .ogg ya da .wav koyunca o çalar (önce .ogg aranır).
## Geçici sentez sesler: tools/ses/gecici_sesler.py

const ORTAM := "Ortam"
const RADYO := "Radyo"
const SES_DIR := "res://assets/ses/"
## Kulaklık takılıyken: alçak geçiren kesim (Hz) ve ses düşüşü (dB)
const KULAKLIK_HZ := 650.0
const KULAKLIK_DB := -7.0

static var _lp: AudioEffectLowPassFilter
static var _amp: AudioEffectAmplify


## Yolları kur (bir kez): Ortam (alçak geçiren + kazanç) ve Radyo, ikisi de Master'a
static func setup() -> void:
	if AudioServer.get_bus_index(ORTAM) < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, ORTAM)
		AudioServer.set_bus_send(i, "Master")
		_lp = AudioEffectLowPassFilter.new()
		_lp.cutoff_hz = 20000.0
		_lp.resonance = 0.4
		_lp.db = AudioEffectFilter.FILTER_24DB
		AudioServer.add_bus_effect(i, _lp)
		_amp = AudioEffectAmplify.new()
		AudioServer.add_bus_effect(i, _amp)
	if AudioServer.get_bus_index(RADYO) < 0:
		AudioServer.add_bus()
		var j := AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, RADYO)
		AudioServer.set_bus_send(j, "Master")


## 0 = kulaklık yok, 1 = kulaklık takılı (arası geçiş). Kesim logaritmik kayar (kulağa düzgün gelsin)
static func set_earbuds(k: float) -> void:
	if _lp == null:
		return
	k = clampf(k, 0.0, 1.0)
	_lp.cutoff_hz = exp(lerpf(log(20000.0), log(KULAKLIK_HZ), k))
	_amp.volume_db = KULAKLIK_DB * k
	# Tam açıkken süzgeci kapat (işlemci harcamasın)
	var i := AudioServer.get_bus_index(ORTAM)
	AudioServer.set_bus_effect_enabled(i, 0, k > 0.001)


## Ses dosyası (önce .ogg, sonra .wav); loop: baştan sona döngü
static func load_sound(ad: String, loop := false) -> AudioStream:
	var s: AudioStream = null
	for ext: String in [".ogg", ".mp3", ".wav"]:
		var p := SES_DIR + ad + ext
		if ResourceLoader.exists(p):
			s = load(p)
			break
	if s == null:
		return null
	if loop:
		if s is AudioStreamWAV:
			var w := s as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			# Örnek sayısı (içe aktarım sıkıştırsa da süre x örnekleme hızı)
			w.loop_end = int(w.get_length() * w.mix_rate)
		elif s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		elif s is AudioStreamMP3:
			(s as AudioStreamMP3).loop = true
	return s
