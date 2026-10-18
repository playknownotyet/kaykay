#include "apple_muzik.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cmath>
#include <cstring>

#import <MediaPlayer/MediaPlayer.h>
#import <UIKit/UIKit.h>

// Statik kütüphane: uygulama MediaPlayer çerçevesine kendiliğinden bağlansın (Xcode ayarı gerekmez)
__asm__(".linker_option \"-framework\", \"MediaPlayer\"");

using namespace godot;

static MPMusicPlayerController *muzik_player() {
	return [MPMusicPlayerController systemMusicPlayer];
}

static bool muzik_authorized() {
	return [MPMediaLibrary authorizationStatus] == MPMediaLibraryAuthorizationStatusAuthorized;
}

static String muzik_str(NSString *s) {
	if (s == nil) {
		return String();
	}
	return String::utf8([s UTF8String]);
}

static NSString *ns_str(const String &s) {
	return [NSString stringWithUTF8String:s.utf8().get_data()];
}

// ---------- Kütüphane önbelleği (ilk istekte sorgulanır; refresh_library temizler) ----------

static NSMutableDictionary<NSString *, NSArray<MPMediaItemCollection *> *> *g_collections = nil;
static NSArray<MPMediaItem *> *g_all_songs = nil;

static NSArray<MPMediaItemCollection *> *muzik_collections(NSString *kind) {
	if (!muzik_authorized()) {
		return @[];
	}
	if (g_collections == nil) {
		g_collections = [NSMutableDictionary dictionary];
	}
	NSArray<MPMediaItemCollection *> *c = g_collections[kind];
	if (c != nil) {
		return c;
	}
	MPMediaQuery *q = nil;
	if ([kind isEqualToString:@"playlists"]) {
		q = [MPMediaQuery playlistsQuery];
	} else if ([kind isEqualToString:@"artists"]) {
		q = [MPMediaQuery artistsQuery];
	} else if ([kind isEqualToString:@"albums"]) {
		q = [MPMediaQuery albumsQuery];
	}
	c = q ? q.collections : @[];
	if (c == nil) {
		c = @[];
	}
	g_collections[kind] = c;
	return c;
}

static NSArray<MPMediaItem *> *muzik_items(NSString *kind, int index) {
	if (!muzik_authorized()) {
		return @[];
	}
	if ([kind isEqualToString:@"all"]) {
		if (g_all_songs == nil) {
			g_all_songs = [MPMediaQuery songsQuery].items ?: @[];
		}
		return g_all_songs;
	}
	NSArray<MPMediaItemCollection *> *c = muzik_collections(kind);
	if (index < 0 || index >= (int)c.count) {
		return @[];
	}
	return c[index].items ?: @[];
}

// ---------- Bağlama ----------

void AppleMuzik::_bind_methods() {
	ClassDB::bind_method(D_METHOD("authorization_status"), &AppleMuzik::authorization_status);
	ClassDB::bind_method(D_METHOD("request_access"), &AppleMuzik::request_access);
	ClassDB::bind_method(D_METHOD("play"), &AppleMuzik::play);
	ClassDB::bind_method(D_METHOD("pause"), &AppleMuzik::pause);
	ClassDB::bind_method(D_METHOD("toggle"), &AppleMuzik::toggle);
	ClassDB::bind_method(D_METHOD("next"), &AppleMuzik::next);
	ClassDB::bind_method(D_METHOD("previous"), &AppleMuzik::previous);
	ClassDB::bind_method(D_METHOD("set_repeat", "on"), &AppleMuzik::set_repeat);
	ClassDB::bind_method(D_METHOD("set_shuffle", "on"), &AppleMuzik::set_shuffle);
	ClassDB::bind_method(D_METHOD("get_state"), &AppleMuzik::get_state);
	ClassDB::bind_method(D_METHOD("get_artwork", "size"), &AppleMuzik::get_artwork);
	ClassDB::bind_method(D_METHOD("refresh_library"), &AppleMuzik::refresh_library);
	ClassDB::bind_method(D_METHOD("get_collections", "kind"), &AppleMuzik::get_collections);
	ClassDB::bind_method(D_METHOD("song_count", "kind", "index"), &AppleMuzik::song_count);
	ClassDB::bind_method(D_METHOD("get_songs", "kind", "index", "offset", "limit"), &AppleMuzik::get_songs);
	ClassDB::bind_method(D_METHOD("play_from", "kind", "index", "song", "shuffle"), &AppleMuzik::play_from);
}

// ---------- İzin ve çalma ----------

int AppleMuzik::authorization_status() const {
	return (int)[MPMediaLibrary authorizationStatus];
}

void AppleMuzik::request_access() {
	if ([MPMediaLibrary authorizationStatus] != MPMediaLibraryAuthorizationStatusNotDetermined) {
		return;
	}
	[MPMediaLibrary requestAuthorization:^(MPMediaLibraryAuthorizationStatus status) {
	}];
}

void AppleMuzik::play() {
	if (!muzik_authorized()) {
		return;
	}
	MPMusicPlayerController *p = muzik_player();
	// Müzik uygulamasında sıra yoksa kütüphanedeki şarkılarla başla
	if (p.nowPlayingItem == nil) {
		NSArray<MPMediaItem *> *all = muzik_items(@"all", 0);
		if (all.count == 0) {
			return;
		}
		[p setQueueWithItemCollection:[MPMediaItemCollection collectionWithItems:all]];
	}
	[p play];
}

void AppleMuzik::pause() {
	[muzik_player() pause];
}

void AppleMuzik::toggle() {
	if (muzik_player().playbackState == MPMusicPlaybackStatePlaying) {
		pause();
	} else {
		play();
	}
}

void AppleMuzik::next() {
	[muzik_player() skipToNextItem];
}

void AppleMuzik::previous() {
	MPMusicPlayerController *p = muzik_player();
	NSTimeInterval t = p.currentPlaybackTime;
	// 3 sn'den sonra başa sarar, başındaysa önceki şarkı
	if (!std::isnan(t) && t > 3.0) {
		[p skipToBeginning];
	} else {
		[p skipToPreviousItem];
	}
}

void AppleMuzik::set_repeat(bool p_on) {
	muzik_player().repeatMode = p_on ? MPMusicRepeatModeOne : MPMusicRepeatModeNone;
}

void AppleMuzik::set_shuffle(bool p_on) {
	muzik_player().shuffleMode = p_on ? MPMusicShuffleModeSongs : MPMusicShuffleModeOff;
}

Dictionary AppleMuzik::get_state() const {
	Dictionary d;
	MPMusicPlayerController *p = muzik_player();
	d["authorized"] = muzik_authorized();
	d["playing"] = p.playbackState == MPMusicPlaybackStatePlaying;
	d["repeat"] = p.repeatMode == MPMusicRepeatModeOne;
	d["shuffle"] = p.shuffleMode == MPMusicShuffleModeSongs || p.shuffleMode == MPMusicShuffleModeAlbums;
	MPMediaItem *it = muzik_authorized() ? p.nowPlayingItem : nil;
	d["has_item"] = it != nil;
	if (it != nil) {
		d["title"] = muzik_str(it.title);
		d["artist"] = muzik_str(it.artist);
		d["album"] = muzik_str(it.albumTitle);
		d["duration"] = (double)it.playbackDuration;
		NSTimeInterval t = p.currentPlaybackTime;
		d["position"] = std::isnan(t) ? 0.0 : (double)t;
		d["id"] = (int64_t)it.persistentID;
		d["index"] = (int64_t)p.indexOfNowPlayingItem;
	}
	return d;
}

PackedByteArray AppleMuzik::get_artwork(int p_size) const {
	PackedByteArray out;
	if (!muzik_authorized()) {
		return out;
	}
	MPMediaItem *it = muzik_player().nowPlayingItem;
	if (it == nil || it.artwork == nil) {
		return out;
	}
	UIImage *img = [it.artwork imageWithSize:CGSizeMake(p_size, p_size)];
	if (img == nil) {
		return out;
	}
	NSData *png = UIImagePNGRepresentation(img);
	if (png == nil || png.length == 0) {
		return out;
	}
	out.resize((int64_t)png.length);
	memcpy(out.ptrw(), png.bytes, png.length);
	return out;
}

// ---------- Kütüphane ----------

void AppleMuzik::refresh_library() {
	g_collections = nil;
	g_all_songs = nil;
}

Array AppleMuzik::get_collections(const String &p_kind) {
	Array out;
	NSString *kind = ns_str(p_kind);
	for (MPMediaItemCollection *c in muzik_collections(kind)) {
		Dictionary e;
		MPMediaItem *rep = c.representativeItem;
		if ([kind isEqualToString:@"playlists"]) {
			e["title"] = muzik_str([c valueForProperty:MPMediaPlaylistPropertyName]);
			e["subtitle"] = String();
		} else if ([kind isEqualToString:@"artists"]) {
			e["title"] = muzik_str(rep.artist);
			e["subtitle"] = String();
		} else {
			e["title"] = muzik_str(rep.albumTitle);
			e["subtitle"] = muzik_str(rep.albumArtist.length > 0 ? rep.albumArtist : rep.artist);
		}
		e["count"] = (int64_t)c.count;
		out.push_back(e);
	}
	return out;
}

int AppleMuzik::song_count(const String &p_kind, int p_index) {
	return (int)muzik_items(ns_str(p_kind), p_index).count;
}

Array AppleMuzik::get_songs(const String &p_kind, int p_index, int p_offset, int p_limit) {
	Array out;
	NSArray<MPMediaItem *> *items = muzik_items(ns_str(p_kind), p_index);
	int n = (int)items.count;
	int start = p_offset < 0 ? 0 : p_offset;
	int end = p_limit < 0 ? n : start + p_limit;
	if (end > n) {
		end = n;
	}
	for (int i = start; i < end; i++) {
		MPMediaItem *it = items[i];
		Dictionary e;
		e["title"] = muzik_str(it.title);
		e["artist"] = muzik_str(it.artist);
		e["duration"] = (double)it.playbackDuration;
		out.push_back(e);
	}
	return out;
}

void AppleMuzik::play_from(const String &p_kind, int p_index, int p_song, bool p_shuffle) {
	if (!muzik_authorized()) {
		return;
	}
	NSArray<MPMediaItem *> *items = muzik_items(ns_str(p_kind), p_index);
	if (items.count == 0) {
		return;
	}
	MPMusicPlayerController *p = muzik_player();
	p.shuffleMode = p_shuffle ? MPMusicShuffleModeSongs : MPMusicShuffleModeOff;
	[p setQueueWithItemCollection:[MPMediaItemCollection collectionWithItems:items]];
	if (p_song >= 0 && p_song < (int)items.count) {
		p.nowPlayingItem = items[p_song];
	}
	[p play];
}
