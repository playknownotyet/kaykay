class_name MuzikServisi
extends RefCounted
## Müzik çaların arkasındaki çalar. İki kaynak:
##   "apple" Apple Music (yalnız iPhone; native/apple_muzik GDExtension): telefonun Müzik uygulamasının
##           çaları. Şarkıyı o çalar, oyun yönetir: oynat / durdur / geç / tekrar / karıştır, kütüphaneyi
##           gezip (çalma listeleri, sanatçılar, albümler, şarkılar) seçilen şarkıdan çalma.
##   "radyo" Oyun içi radyo (her yerde): assets/radyo/radyo.json'daki istasyonlar, oyunun kendi sesi.
## Cihazın menüleri buradan gelir (page_*): kök -> Müzik / Radyo / Şimdi çalıyor.
## Durum her yarım saniyede bir okunur (state()): başlık, sanatçı, süre, konum, çalıyor mu, tekrar.

const POLL := 0.5
const ART_SIZE := 176
const CFG := "user://muzik.cfg"
const RADYO_JSON := "res://assets/radyo/radyo.json"
const CHUNK := 40

var kaynak := "radyo"
var _apple: Object = null
var _poll_t := 0.0
var _st := {}
var _art: Texture2D = null
var _art_id := -1
var _shuffle_pref := false
# Kütüphane önbelleği: tür -> koleksiyon listesi; şarkı sayfaları: sayfa kimliği -> {count, parcalar}
var _coll := {}
var _songs := {}
# Radyo
var radio: AudioStreamPlayer = null
var _stations: Array = []
var _st_i := -1
var _tr_i := 0
var _radio_loop := false


func _init() -> void:
	if OS.get_name() == "iOS" and ClassDB.class_exists("AppleMuzik"):
		_apple = ClassDB.instantiate("AppleMuzik")
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(RADYO_JSON)) if FileAccess.file_exists(RADYO_JSON) else null
	if j is Dictionary and j.get("istasyonlar") is Array:
		_stations = j.istasyonlar
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		var k := String(cfg.get_value("muzik", "kaynak", "radyo"))
		if k == "apple" and _apple:
			kaynak = "apple"
		_st_i = int(cfg.get_value("muzik", "istasyon", -1))
	if _st_i >= _stations.size():
		_st_i = -1
	if _apple and kaynak != "apple" and _stations.is_empty():
		kaynak = "apple"


## Radyonun sesi (MuzikCalar verir; oyunun ses düğümü)
func set_radio_player(p: AudioStreamPlayer) -> void:
	radio = p
	radio.finished.connect(_on_radio_finished)


func has_apple() -> bool:
	return _apple != null


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("muzik", "kaynak", kaynak)
	cfg.set_value("muzik", "istasyon", _st_i)
	cfg.save(CFG)


func _use(k: String) -> void:
	if k == kaynak:
		return
	pause()
	kaynak = k
	_st = {}
	_art = null
	_art_id = -1
	_poll_t = 0.0
	_save()


## Cihaz açılınca: Apple Music ilk seferde izin sorar
func ensure_access() -> void:
	if _apple and int(_apple.authorization_status()) == 0:
		_apple.request_access()


func update(delta: float) -> void:
	if kaynak == "apple" and _apple:
		_poll_t -= delta
		if _poll_t <= 0.0:
			_poll_t = POLL
			_st = _apple.get_state()
			var id := int(_st.get("id", -1))
			if id != _art_id:
				_art_id = id
				_art = null
				if bool(_st.get("has_item", false)):
					var png: PackedByteArray = _apple.get_artwork(ART_SIZE)
					if png.size() > 0:
						var img := Image.new()
						if img.load_png_from_buffer(png) == OK:
							_art = ImageTexture.create_from_image(img)
		elif _st.get("playing", false):
			# Konum yoklamalar arasında akar (ekrandaki süre saniye saniye ilerlesin)
			_st["position"] = float(_st.get("position", 0.0)) + delta


# ---------- Ekran durumu ----------

## {source, title, artist, playing, loop, shuffle, pos, dur, index, count, art, info, hint}
func state() -> Dictionary:
	if kaynak == "apple" and _apple:
		var has := bool(_st.get("has_item", false))
		var auth := int(_apple.authorization_status())
		var info := "APPLE MUSIC"
		if auth == 1 or auth == 2:
			info = "MÜZİK İZNİ YOK: AYARLAR > KAYKAY"
		elif auth == 0:
			info = "MÜZİK İZNİ BEKLENİYOR"
		elif not has:
			info = "MENU > MÜZİK: ŞARKI SEÇ"
		return {
			"source": "APPLE MUSIC",
			"title": String(_st.get("title", "")) if has else "ŞARKI YOK",
			"artist": String(_st.get("artist", "")) if has else "MÜZİK UYGULAMASI",
			"playing": bool(_st.get("playing", false)),
			"loop": bool(_st.get("repeat", false)),
			"shuffle": bool(_st.get("shuffle", false)),
			"pos": float(_st.get("position", 0.0)),
			"dur": maxf(float(_st.get("duration", 0.0)), 0.0),
			"index": int(_st.get("index", 0)),
			"count": 0,
			"art": _art,
			"info": info,
			"hint": "MENU: ŞARKI / RADYO SEÇ",
		}
	# Radyo
	var tr := _radio_track()
	var st_name := String(_stations[_st_i].get("ad", "RADYO")) if _st_i >= 0 and _st_i < _stations.size() else "RADYO"
	var playing := radio != null and radio.playing and not radio.stream_paused
	var info := st_name
	if _stations.is_empty():
		info = "HENÜZ İSTASYON YOK"
	elif _st_i < 0:
		info = "MENU > RADYO: İSTASYON SEÇ"
	elif tr.is_empty():
		info = st_name + ": ŞARKI YOK"
	return {
		"source": "RADYO",
		"title": String(tr.get("ad", "")) if not tr.is_empty() else "RADYO",
		"artist": String(tr.get("sanatci", "")) if not tr.is_empty() else st_name,
		"playing": playing,
		"loop": _radio_loop,
		"shuffle": false,
		"pos": radio.get_playback_position() if radio and radio.playing else 0.0,
		"dur": radio.stream.get_length() if radio and radio.stream else 0.0,
		"index": _tr_i,
		"count": _station_tracks().size(),
		"art": null,
		"info": info,
		"hint": "MENU: ŞARKI / RADYO SEÇ",
	}


# ---------- Tuşlar ----------

func play_pause() -> void:
	if kaynak == "apple" and _apple:
		_apple.toggle()
		_poll_t = 0.15
		return
	if radio and radio.playing and not radio.stream_paused:
		radio.stream_paused = true
	else:
		play()


func play() -> void:
	if kaynak == "apple" and _apple:
		_apple.play()
		_poll_t = 0.15
		return
	if radio == null:
		return
	if radio.stream_paused:
		radio.stream_paused = false
	elif not radio.playing:
		if _st_i < 0 and not _stations.is_empty():
			_st_i = 0
		_start_track()


func pause() -> void:
	if kaynak == "apple" and _apple:
		_apple.pause()
		_poll_t = 0.15
		return
	if radio and radio.playing:
		radio.stream_paused = true


func next() -> void:
	if kaynak == "apple" and _apple:
		_apple.next()
		_poll_t = 0.15
		return
	var n := _station_tracks().size()
	if n > 0:
		_tr_i = (_tr_i + 1) % n
		_start_track()


func prev() -> void:
	if kaynak == "apple" and _apple:
		_apple.previous()
		_poll_t = 0.15
		return
	var n := _station_tracks().size()
	if n == 0:
		return
	if radio and radio.get_playback_position() > 3.0:
		_start_track()
	else:
		_tr_i = (_tr_i - 1 + n) % n
		_start_track()


func toggle_loop() -> void:
	if kaynak == "apple" and _apple:
		_apple.set_repeat(not bool(_st.get("repeat", false)))
		_poll_t = 0.1
		return
	_radio_loop = not _radio_loop


# ---------- Radyo ----------

func _station_tracks() -> Array:
	if _st_i < 0 or _st_i >= _stations.size():
		return []
	var t: Variant = _stations[_st_i].get("sarkilar", [])
	return t if t is Array else []


func _radio_track() -> Dictionary:
	var t := _station_tracks()
	if t.is_empty():
		return {}
	return t[clampi(_tr_i, 0, t.size() - 1)]


func _start_track() -> void:
	if radio == null:
		return
	var tr := _radio_track()
	var path := String(tr.get("dosya", ""))
	if path == "" or not ResourceLoader.exists(path):
		radio.stop()
		return
	radio.stream = load(path)
	radio.stream_paused = false
	radio.play()


func _on_radio_finished() -> void:
	if kaynak != "radyo":
		return
	if not _radio_loop:
		var n := _station_tracks().size()
		if n > 0:
			_tr_i = (_tr_i + 1) % n
	_start_track()


# ---------- Menüler (cihazın MENU'sü) ----------
# Sayfa kimlikleri: "kok", "muzik", "liste:<tür>" (playlists / artists / albums),
# "sarki:<tür>:<sıra>" (tür "all" ise tüm şarkılar), "radyo".
# Satır: {label, sub, enabled, go (alt sayfa) ya da act (eylem)}

func page_title(id: String) -> String:
	if id == "kok":
		return "MENÜ"
	if id == "muzik":
		return "MÜZİK"
	if id == "radyo":
		return "RADYO"
	if id.begins_with("liste:"):
		return String({"playlists": "ÇALMA LİSTELERİ", "artists": "SANATÇILAR", "albums": "ALBÜMLER"}.get(id.substr(6), "MÜZİK"))
	if id.begins_with("sarki:"):
		var p := id.split(":")
		if p[1] == "all":
			return "ŞARKILAR"
		var c: Array = _collections(p[1])
		var i := int(p[2])
		return String(c[i].title) if i < c.size() else "ŞARKILAR"
	return ""


func page_len(id: String) -> int:
	match id:
		"kok":
			return 3
		"muzik":
			return 6
		"radyo":
			return maxi(_stations.size(), 1)
	if id.begins_with("liste:"):
		return maxi(_collections(id.substr(6)).size(), 1)
	if id.begins_with("sarki:"):
		return int(_song_page(id).count) + 1
	return 0


func page_item(id: String, i: int) -> Dictionary:
	match id:
		"kok":
			var root := [
				{"label": "MÜZİK", "sub": "" if _apple else "APPLE MUSIC: YALNIZ İPHONE", "enabled": _apple != null, "go": "muzik"},
				{"label": "RADYO", "sub": "" if not _stations.is_empty() else "YAKINDA", "enabled": true, "go": "radyo"},
				{"label": "ŞİMDİ ÇALIYOR", "sub": "", "enabled": true, "act": "simdi"},
			]
			return root[i]
		"muzik":
			var shuf := _shuffle_on()
			var items := [
				{"label": "ÇALMA LİSTELERİ", "sub": "", "enabled": true, "go": "liste:playlists"},
				{"label": "SANATÇILAR", "sub": "", "enabled": true, "go": "liste:artists"},
				{"label": "ALBÜMLER", "sub": "", "enabled": true, "go": "liste:albums"},
				{"label": "ŞARKILAR", "sub": "", "enabled": true, "go": "sarki:all:0"},
				{"label": "HEPSİNİ KARIŞIK ÇAL", "sub": "", "enabled": true, "act": "cal:all:0:-1:1"},
				{"label": "KARIŞIK: " + ("AÇIK" if shuf else "KAPALI"), "sub": "", "enabled": true, "act": "karisik"},
			]
			return items[i]
		"radyo":
			if _stations.is_empty():
				return {"label": "HENÜZ İSTASYON YOK", "sub": "YAKINDA EKLENECEK", "enabled": false}
			var s: Dictionary = _stations[i]
			var n := (s.get("sarkilar", []) as Array).size()
			return {"label": String(s.get("ad", "İSTASYON")), "sub": "%d ŞARKI" % n, "enabled": n > 0, "act": "istasyon:%d" % i}
	if id.begins_with("liste:"):
		var kind := id.substr(6)
		var c: Array = _collections(kind)
		if c.is_empty():
			return {"label": "BOŞ", "sub": "KÜTÜPHANEDE YOK", "enabled": false}
		var e: Dictionary = c[i]
		var sub := String(e.get("subtitle", ""))
		if sub == "":
			sub = "%d ŞARKI" % int(e.get("count", 0))
		var title := String(e.get("title", ""))
		return {"label": title if title != "" else "(ADSIZ)", "sub": sub, "enabled": true, "go": "sarki:%s:%d" % [kind, i]}
	if id.begins_with("sarki:"):
		var p := id.split(":")
		if i == 0:
			return {"label": "KARIŞIK ÇAL", "sub": "", "enabled": int(_song_page(id).count) > 0, "act": "cal:%s:%s:-1:1" % [p[1], p[2]]}
		var s := _song_at(id, i - 1)
		return {"label": String(s.get("title", "")), "sub": String(s.get("artist", "")), "enabled": true,
			"act": "cal:%s:%s:%d:0" % [p[1], p[2], i - 1]}
	return {"label": "", "sub": "", "enabled": false}


func _shuffle_on() -> bool:
	if kaynak == "apple" and _st.has("shuffle"):
		return bool(_st.shuffle)
	return _shuffle_pref


## Eylem: "simdi", "karisik", "cal:<tür>:<sıra>:<şarkı>:<karışık>", "istasyon:<i>".
## true dönerse menü kapanır (şimdi çalıyor ekranına)
func do_action(act: String) -> bool:
	var p := act.split(":")
	match p[0]:
		"simdi":
			return true
		"karisik":
			_shuffle_pref = not _shuffle_on()
			if _apple:
				_apple.set_shuffle(_shuffle_pref)
				_st["shuffle"] = _shuffle_pref
			return false
		"cal":
			if _apple == null:
				return false
			_use("apple")
			var shuffle := p[4] == "1" or _shuffle_pref
			_apple.play_from(p[1], int(p[2]), int(p[3]), shuffle)
			_poll_t = 0.2
			return true
		"istasyon":
			_use("radyo")
			_st_i = int(p[1])
			_tr_i = 0
			_save()
			_start_track()
			return true
	return false


func _collections(kind: String) -> Array:
	if _apple == null:
		return []
	if not _coll.has(kind):
		_coll[kind] = _apple.get_collections(kind)
	return _coll[kind]


func _song_page(id: String) -> Dictionary:
	if not _songs.has(id):
		var p := id.split(":")
		var n := int(_apple.song_count(p[1], int(p[2]))) if _apple else 0
		_songs[id] = {"count": n, "parcalar": {}}
	return _songs[id]


func _song_at(id: String, j: int) -> Dictionary:
	var pg := _song_page(id)
	var ci := j / CHUNK
	var parts: Dictionary = pg.parcalar
	if not parts.has(ci):
		var p := id.split(":")
		parts[ci] = _apple.get_songs(p[1], int(p[2]), ci * CHUNK, CHUNK) if _apple else []
	var arr: Array = parts[ci]
	var k := j - ci * CHUNK
	return arr[k] if k < arr.size() else {}


## Menü açılınca kütüphane yeniden okunur (yeni eklenen şarkılar görünsün)
func refresh_library() -> void:
	_coll.clear()
	_songs.clear()
	if _apple:
		_apple.refresh_library()
