// Apple Music denetimi (yalnız iOS): telefonun Müzik uygulamasının çaları (MPMusicPlayerController
// systemMusicPlayer). Oyun kendi sesini çalmaz; Müzik uygulaması çalar, biz yönetiriz:
//   oynat / durdur / geç / tekrarla / karıştır, çalan şarkının adı, sanatçısı, süresi, kapağı;
//   kütüphaneyi gezme (çalma listeleri, sanatçılar, albümler, tüm şarkılar) ve seçilen şarkıdan çalma.
// Godot'ta: ClassDB.instantiate("AppleMuzik") (scripts/ui/muzik_servisi.gd).
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/string.hpp>

namespace godot {

class AppleMuzik : public RefCounted {
	GDCLASS(AppleMuzik, RefCounted)

protected:
	static void _bind_methods();

public:
	// 0 sorulmadı, 1 reddedildi, 2 kısıtlı, 3 izin verildi
	int authorization_status() const;
	void request_access();

	void play();
	void pause();
	void toggle();
	void next();
	void previous();
	void set_repeat(bool p_on);
	void set_shuffle(bool p_on);

	// {authorized, playing, repeat, shuffle, has_item, title, artist, album, duration, position, id, index}
	Dictionary get_state() const;
	// Çalan şarkının kapağı (PNG); yoksa boş
	PackedByteArray get_artwork(int p_size) const;

	// Kütüphane. kind: "playlists", "artists", "albums" (koleksiyonlar) ya da "all" (tüm şarkılar)
	void refresh_library();
	// [{title, subtitle, count}]
	Array get_collections(const String &p_kind);
	int song_count(const String &p_kind, int p_index);
	// [{title, artist, duration}] (offset'ten limit kadar)
	Array get_songs(const String &p_kind, int p_index, int p_offset, int p_limit);
	// Koleksiyonu (ya da tüm şarkıları) sıraya koyar, song'dan (-1: baştan) çalar
	void play_from(const String &p_kind, int p_index, int p_song, bool p_shuffle);
};

} // namespace godot
