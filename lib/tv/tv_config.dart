import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:Bloomee/tv/connectors/lidarr_client.dart';
import 'package:Bloomee/tv/connectors/ytmusic_account.dart';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Id "plugin" usato per i brani che arrivano da Jellyfin: `jellyfin::<itemId>`.
const String kJellyfinPluginId = 'jellyfin';

/// Configurazione dei connettori TV (Jellyfin, Lidarr), salvata nel DB
/// delle impostazioni dell'app.
class TvConfig {
  TvConfig._();

  static const _kJfUrl = 'tv.jellyfin.url';
  static const _kJfUser = 'tv.jellyfin.user';
  static const _kJfToken = 'tv.jellyfin.token';
  static const _kJfUserId = 'tv.jellyfin.userId';
  static const _kLdUrl = 'tv.lidarr.url';
  static const _kLdKey = 'tv.lidarr.key';

  static const _kYtCookie = 'tv.yt.cookie';
  static const _kYtVisitor = 'tv.yt.visitor';
  static const _kYtDataSync = 'tv.yt.datasync';
  static const _kYtName = 'tv.yt.name';

  static String ytCookie = '';
  static String ytVisitor = '';
  static String ytDataSync = '';
  static String ytName = '';

  static bool get hasYouTube => ytCookie.contains('SAPISID');

  /// Client YouTube Music: con l'account se collegato, altrimenti anonimo
  /// (per i dati pubblici come la pagina artista).
  static YtMusicClient get youtube =>
      YtMusicClient(cookie: ytCookie, visitorData: ytVisitor, dataSyncId: ytDataSync);

  static Future<void> saveYouTube({required String cookie, required String visitor, required String dataSync, required String name}) async {
    final d = _dao;
    await d.putSettingStr(_kYtCookie, cookie);
    await d.putSettingStr(_kYtVisitor, visitor);
    await d.putSettingStr(_kYtDataSync, dataSync);
    await d.putSettingStr(_kYtName, name);
    ytCookie = cookie;
    ytVisitor = visitor;
    ytDataSync = dataSync;
    ytName = name;
    changes.value++;
  }

  static String jellyfinUrl = '';
  static String jellyfinUser = '';
  static String jellyfinToken = '';
  static String jellyfinUserId = '';
  static String lidarrUrl = '';
  static String lidarrKey = '';

  /// Avvisa le schermate quando cambia una configurazione.
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static SettingsDAO get _dao => SettingsDAO(DBProvider.db);

  static Future<void> load() async {
    final d = _dao;
    jellyfinUrl = await d.getSettingStr(_kJfUrl) ?? '';
    jellyfinUser = await d.getSettingStr(_kJfUser) ?? '';
    jellyfinToken = await d.getSettingStr(_kJfToken) ?? '';
    jellyfinUserId = await d.getSettingStr(_kJfUserId) ?? '';
    lidarrUrl = await d.getSettingStr(_kLdUrl) ?? '';
    lidarrKey = await d.getSettingStr(_kLdKey) ?? '';
    ytCookie = await d.getSettingStr(_kYtCookie) ?? '';
    ytVisitor = await d.getSettingStr(_kYtVisitor) ?? '';
    ytDataSync = await d.getSettingStr(_kYtDataSync) ?? '';
    ytName = await d.getSettingStr(_kYtName) ?? '';
  }

  /// Configurazione da file: `tv-config.json` nella cartella esterna
  /// dell'app (Android/data/<id>/files), caricabile con adb. Viene applicata
  /// all'avvio e poi cancellata, così le chiavi non restano in chiaro.
  /// Campi: jellyfinUrl, jellyfinUser, jellyfinToken (chiave API), lidarrUrl, lidarrKey.
  static Future<void> importFromFile() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return;
      final f = File('${dir.path}/tv-config.json');
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      await f.delete();
      if (m['lidarrKey'] != null) {
        await saveLidarr(url: (m['lidarrUrl'] ?? lidarrUrl) as String, key: m['lidarrKey'] as String);
      }
      if (m['jellyfinToken'] != null) {
        final url = (m['jellyfinUrl'] ?? jellyfinUrl) as String;
        final user = (m['jellyfinUser'] ?? '') as String;
        final c = JellyfinClient(baseUrl: url, token: m['jellyfinToken'] as String);
        final id = await c.userIdByName(user);
        if (id != null) {
          await saveJellyfin(url: url, user: user, token: c.token!, userId: id);
        }
      }
    } catch (e) {
      debugPrint('tv-config.json: $e');
    }
  }

  static bool get hasJellyfin =>
      jellyfinUrl.isNotEmpty && jellyfinToken.isNotEmpty && jellyfinUserId.isNotEmpty;
  static bool get hasLidarr => lidarrUrl.isNotEmpty && lidarrKey.isNotEmpty;

  static JellyfinClient? get jellyfin => hasJellyfin
      ? JellyfinClient(baseUrl: jellyfinUrl, token: jellyfinToken, userId: jellyfinUserId)
      : null;

  static LidarrClient? get lidarr => hasLidarr ? LidarrClient(baseUrl: lidarrUrl, apiKey: lidarrKey) : null;

  static Future<void> saveJellyfin({
    required String url,
    required String user,
    required String token,
    required String userId,
  }) async {
    final d = _dao;
    await d.putSettingStr(_kJfUrl, url);
    await d.putSettingStr(_kJfUser, user);
    await d.putSettingStr(_kJfToken, token);
    await d.putSettingStr(_kJfUserId, userId);
    jellyfinUrl = url;
    jellyfinUser = user;
    jellyfinToken = token;
    jellyfinUserId = userId;
    changes.value++;
  }

  static Future<void> saveLidarr({required String url, required String key}) async {
    final d = _dao;
    await d.putSettingStr(_kLdUrl, url);
    await d.putSettingStr(_kLdKey, key);
    lidarrUrl = url;
    lidarrKey = key;
    changes.value++;
  }

  /// Scollega Jellyfin: tiene indirizzo e utente, cancella le credenziali.
  static Future<void> clearJellyfin() =>
      saveJellyfin(url: jellyfinUrl, user: jellyfinUser, token: '', userId: '');

  /// Scollega Lidarr: tiene l'indirizzo, cancella la chiave.
  static Future<void> clearLidarr() => saveLidarr(url: lidarrUrl, key: '');
}


/// Conversioni da elementi Jellyfin ai modelli dell'app, così i brani
/// Jellyfin passano dallo stesso player, coda, testi e cronologia.
extension JfItemToTrack on JfItem {
  Artwork artwork(JellyfinClient c) {
    final img = imageItemId;
    final url = img == null ? '' : c.imageUrl(img, maxSize: 400);
    return Artwork(
      url: url,
      urlLow: img == null ? null : c.imageUrl(img, maxSize: 200),
      urlHigh: img == null ? null : c.imageUrl(img, maxSize: 900),
      layout: ImageLayout.square,
    );
  }

  Track toTrack(JellyfinClient c) => Track(
        id: '$kJellyfinPluginId::$id',
        title: name,
        artists: [ArtistSummary(id: '$kJellyfinPluginId::artist:$albumArtist', name: albumArtist)],
        album: albumId == null
            ? null
            : AlbumSummary(
                id: '$kJellyfinPluginId::$albumId',
                title: album,
                artists: [ArtistSummary(id: '$kJellyfinPluginId::artist:$albumArtist', name: albumArtist)],
                year: year,
              ),
        durationMs: BigInt.from(duration.inMilliseconds),
        thumbnail: artwork(c),
        isExplicit: false,
      );
}

/// Conversioni da YouTube Music ai modelli dell'app (riproduzione col plugin
/// ytmusic già installato).
extension YtItemToModels on YtItem {
  Artwork get artwork => Artwork(
        url: thumbnail ?? '',
        urlHigh: thumbnail,
        urlLow: thumbnail?.replaceAll(RegExp(r'=w544-h544'), '=w226-h226'),
        layout: ImageLayout.square,
      );

  List<ArtistSummary> get artistSummaries => [
        for (final a in artists)
          ArtistSummary(id: '$kYtMusicPluginId::${a.id ?? a.name}', name: a.name),
      ];

  Track toTrack() => Track(
        id: '$kYtMusicPluginId::$videoId',
        title: title,
        artists: artistSummaries,
        album: album == null
            ? null
            : AlbumSummary(id: '$kYtMusicPluginId::${album!.id ?? album!.name}', title: album!.name, artists: artistSummaries),
        durationMs: duration == null ? null : BigInt.from(duration!.inMilliseconds),
        thumbnail: artwork,
        isExplicit: false,
      );

  ArtistSummary toArtist() => ArtistSummary(id: '$kYtMusicPluginId::$browseId', name: title, thumbnail: artwork);
}
