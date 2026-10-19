import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:Bloomee/services/db/switchable_database.dart';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:Bloomee/core/models/exported.dart' as models;
import 'package:Bloomee/services/db/global_db.dart';
import 'package:Bloomee/services/db/dao/cache_dao.dart';
import 'package:Bloomee/services/db/dao/history_dao.dart';
import 'package:Bloomee/services/db/legacy/legacy_media_id_mapper.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/search_history_dao.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';

/// Centralised Isar lifecycle manager.
///
/// Owns database open / close / backup-restore responsibilities that were
/// previously scattered across the legacy monolith.
class DBProvider {
  static late String appSuppDir;
  static late String appDocDir;
  static bool _legacyRecovery = true;
  static Timer? _maintenance;
  static int _generation = 0;
  static var _database = SwitchableDatabase();
  static String? _databaseDirectory;
  static Future<Isar> get db => _database;
  static set db(Future<Isar> value) => _database.current = value;

  static Future<void> switchDirectory(String directory) async {
    final previous = await db;
    _maintenance?.cancel();
    _generation++;
    await previous.close();
    _database = SwitchableDatabase();
    _databaseDirectory = directory;
    appSuppDir = directory;
    _legacyRecovery = false;
    await Directory(directory).create(recursive: true);
    db = openDB();
    await db;
    await scheduleMaintenance();
  }

  static final List<CollectionSchema<dynamic>> _schemas = [
    TrackDBSchema,
    SearchHistoryDBSchema,
    PlaylistEntryDBSchema,
    LyricsDBSchema,
    PlaylistDBSchema,
    NotificationsDBSchema,
    PlaybackHistoryDBSchema,
    AppSettingsBoolDBSchema,
    AppSettingsStrDBSchema,
    DownloadDBSchema,
    CacheEntryDBSchema,
    PluginStorageEntitySchema,
  ];

  /// Initialise path state and open the database.
  static Future<Isar> init({
    required String appSupportPath,
    required String appDocumentsPath,
    bool allowLegacyRecovery = true,
  }) async {
    _maintenance?.cancel();
    _generation++;
    _legacyRecovery = allowLegacyRecovery;
    final existing = Isar.getInstance('dbv3');
    if (existing != null && existing.directory != appSupportPath)
      await existing.close();
    if (_databaseDirectory != null && _databaseDirectory != appSupportPath)
      _database = SwitchableDatabase();
    _databaseDirectory = appSupportPath;
    appSuppDir = appSupportPath;
    appDocDir = appDocumentsPath;
    db = openDB();
    return db;
  }

  /// Check for DB backup file and restore when the primary DB is missing.
  static Future<void> checkAndRestoreDB(
      String dbPath, List<String> bPaths) async {
    try {
      final File dbFile = File(dbPath);
      if (_legacyRecovery && !await dbFile.exists()) {
        for (var element in bPaths) {
          final File backUpFile = File(element);
          if (await backUpFile.exists()) {
            await backUpFile.copy(dbFile.path);
            log("DB Restored from $element", name: "DBProvider");
            break;
          }
        }
      }
    } catch (e) {
      log("Failed to restore DB", error: e, name: "DBProvider");
    }
  }

  /// Open (or return existing) Isar instance.
  static Future<Isar> openDB() async {
    if (Isar.getInstance('dbv3') == null) {
      final File dbFile = File(p.join(appSuppDir, 'dbv3.isar'));
      if (!await dbFile.exists()) {
        await checkAndRestoreDB(dbFile.path, [
          p.join(appDocDir, 'dbv3.isar'),
          p.join(appDocDir, 'bloomee_backup_dbv3.isar'),
          p.join(appSuppDir, 'bloomee_backup_dbv3.isar'),
        ]);
      }

      // Migrate DB from documents dir to support dir if needed
      if (_legacyRecovery &&
          !await dbFile.exists() &&
          await File(p.join(appDocDir, 'dbv3.isar')).exists()) {
        final tempDb =
            Isar.openSync(_schemas, directory: appDocDir, name: 'dbv3');
        await tempDb.copyToFile(dbFile.path);
        log("DB Copied to $appSuppDir", name: "DBProvider");
        await tempDb.close();
      }

      log(appSuppDir, name: "DB");
      return Isar.openSync(_schemas, directory: appSuppDir, name: 'dbv3');
    }
    return Future.value(Isar.getInstance('dbv3'));
  }

  /// Schedule periodic maintenance tasks (called once during bootstrap).
  ///
  /// - Ensures the "Liked" and "_DOWNLOADS" system playlists exist.
  /// - After a 30-second delay: purges old history, orphan tracks, expired
  ///   cache, and limits search history.
  static Future<void> scheduleMaintenance() async {
    final trackDAO = TrackDAO(db);
    final playlistDAO = PlaylistDAO(db, trackDAO);
    final historyDAO = HistoryDAO(db, trackDAO);
    final settingsDAO = SettingsDAO(db);
    final cacheDAO = CacheDAO(db);
    final searchHistoryDAO = SearchHistoryDAO(db);

    // Ensure standard playlists exist during startup.
    await Future.wait([
      playlistDAO.ensurePlaylist(likedPlaylist),
      playlistDAO.ensurePlaylist(downloadPlaylist),
      playlistDAO.ensurePlaylist(localMusicPlaylist)
    ]);

    _maintenance?.cancel();
    final generation = _generation;
    _maintenance = Timer(const Duration(seconds: 30), () async {
      if (generation != _generation) return;
      final current = await db;
      if (!current.isOpen) return;
      try {
        // Read configured history retention days.
        final daysStr = await settingsDAO.getSettingStr(
              'historyClearTime',
              defaultValue: '7',
            ) ??
            '7';
        final days = int.tryParse(daysStr) ?? 7;

        await historyDAO.purgeOldHistory(days);
        await trackDAO.purgeOrphanTracks();
        await cacheDAO.purgeExpiredCache();
        await searchHistoryDAO.limitSearchHistory();
        log('Scheduled maintenance complete', name: 'DBProvider');
      } catch (e) {
        log('Maintenance postponed', name: 'DBProvider');
      }
    });
  }

  /// Reset (clear) all collections in the database.
  static Future<void> resetDB() async {
    Isar isarDB = await db;
    await isarDB.writeTxn(() async {
      await isarDB.playlistEntryDBs.clear();
      await isarDB.playlistDBs.clear();
      await isarDB.appSettingsBoolDBs.clear();
      await isarDB.appSettingsStrDBs.clear();
      await isarDB.lyricsDBs.clear();
      await isarDB.trackDBs.clear();
      await isarDB.playbackHistoryDBs.clear();
      await isarDB.searchHistoryDBs.clear();
      await isarDB.cacheEntryDBs.clear();
      await isarDB.notificationsDBs.clear();
      await isarDB.downloadDBs.clear();
      await isarDB.pluginStorageEntitys.clear();
      log("DB reset successfully", name: "DBProvider");
    });
  }

  // ── Standard playlists (excluded from backup restore) ─────────────────────
  static const downloadPlaylist = '_DOWNLOADS';
  static const recentlyPlayedPlaylist = 'recently_played';
  static const likedPlaylist = 'Liked';
  static const localMusicPlaylist = '_LOCAL_MUSIC';
  static final standardPlaylists = [
    downloadPlaylist,
    recentlyPlayedPlaylist,
    likedPlaylist,
    localMusicPlaylist,
  ];

  /// Get the database backup file path.
  static Future<String> getDbBackupFilePath() async {
    String backupPath = (await getDownloadsDirectory())?.path ?? appDocDir;
    backupPath =
        p.join(backupPath, 'bloomeeBackup', 'bloomee_backup_dbv3.json');
    return backupPath;
  }

  /// Check whether a backup file exists.
  static Future<bool> backupExists() async {
    try {
      String backupFile =
          (await getDbBackupFilePath()).replaceAll('.json', '.isar');
      final dbFile = File(backupFile);
      if (dbFile.existsSync()) {
        return true;
      }
    } catch (e) {
      log("No backup exists", error: e, name: "DBProvider");
    }
    return false;
  }

  /// Create a binary backup of the database using Isar's built-in copy.
  ///
  /// Returns the backup file path on success, or null on failure.
  static Future<String?> createBackUp({String? destination}) async {
    Directory? staging;
    Isar? snapshot;
    try {
      final isar = await db;
      final target = destination ??
          (await getDbBackupFilePath()).replaceAll('.json', '.isar');
      await File(target).parent.create(recursive: true);
      staging = await Directory.systemTemp.createTemp('bloomee-backup-');
      await isar.copyToFile(p.join(staging.path, 'backup_export.isar'));
      snapshot = await Isar.open(_schemas,
          directory: staging.path, name: 'backup_export');
      final secretKey = RegExp(
          r'(token|cookie|password|secret|session|api.?key|lastfmkey|tv\..*(key|visitor|datasync))',
          caseSensitive: false);
      await snapshot.writeTxn(() async {
        final settings = await snapshot!.appSettingsStrDBs.where().findAll();
        await snapshot.appSettingsStrDBs.deleteAll(settings
            .where((s) => secretKey.hasMatch(s.settingName))
            .map((s) => s.id)
            .toList());
        await snapshot.pluginStorageEntitys.clear();
        await snapshot.cacheEntryDBs.clear();
      });
      // A second compacted copy excludes deleted pages containing secrets.
      final safe = p.join(staging.path, 'sanitized.isar');
      await snapshot.copyToFile(safe);
      final temporary = '$target.tmp';
      await File(safe).copy(temporary);
      await File(temporary).rename(target);
      return target;
    } catch (e) {
      log('Failed to create backup', error: e, name: 'DBProvider');
      return null;
    } finally {
      await snapshot?.close();
      if (staging != null && await staging.exists())
        await staging.delete(recursive: true);
    }
  }

  /// Create a legacy full JSON backup with playlists and media_items sections.
  ///
  /// This is intentionally shaped to be compatible with
  /// [restoreLegacyJsonBackup].
  static Future<String?> createLegacyJsonBackup() async {
    try {
      final trackDao = TrackDAO(db);
      final playlistDao = PlaylistDAO(db, trackDao);

      final allPlaylists = await playlistDao.getAllPlaylists();
      final userPlaylists = allPlaylists.where((playlist) {
        final name = playlist.name.trim();
        return name.isNotEmpty && !standardPlaylists.contains(name);
      }).toList(growable: false);

      final playlistRows = <Map<String, dynamic>>[];
      final mediaById = <String, Map<String, dynamic>>{};
      final membershipsById = <String, Set<String>>{};

      for (final playlist in userPlaylists) {
        playlistRows.add({
          'playlistName': playlist.name,
          'createdAt': playlist.createdAt.toIso8601String(),
        });

        final tracks = await playlistDao.getPlaylistTracks(playlist.id);
        for (final track in tracks) {
          final trackId = track.mediaId.trim();
          if (trackId.isEmpty) continue;

          mediaById.putIfAbsent(trackId, () {
            final artists = (track.artists ?? const <ArtistSummaryDB>[])
                .map((artist) => (artist.name ?? '').trim())
                .where((name) => name.isNotEmpty)
                .join(', ');
            final durationMs = track.durationMs?.toInt();
            final durationSeconds =
                durationMs != null && durationMs > 0 ? durationMs ~/ 1000 : 0;

            return {
              'mediaID': track.mediaId,
              'title': track.title,
              'artist': artists,
              'album': track.album?.name ?? '',
              'artURL': track.thumbnail?.url ?? '',
              'duration': durationSeconds,
              'permaURL': '',
              'mediaInPlaylists': <Map<String, dynamic>>[],
            };
          });

          membershipsById.putIfAbsent(trackId, () => <String>{});
          membershipsById[trackId]!.add(playlist.name);
        }
      }

      final mediaRows = <Map<String, dynamic>>[];
      for (final entry in mediaById.entries) {
        final mediaRow = entry.value;
        final memberships = membershipsById[entry.key] ?? const <String>{};
        mediaRow['mediaInPlaylists'] = memberships
            .map((name) => <String, dynamic>{'playlistName': name})
            .toList(growable: false);
        mediaRows.add(mediaRow);
      }

      final backupFilePath = await getDbBackupFilePath();
      final backupDir = File(backupFilePath).parent;
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final backupPayload = <String, dynamic>{
        '_meta': {
          'format': 'legacy-v2-full',
          'exportedAt': DateTime.now().toIso8601String(),
          'generatedBy': 'Bloomee DBProvider',
          'playlistsCount': playlistRows.length,
          'mediaItemsCount': mediaRows.length,
        },
        'playlists': playlistRows,
        'media_items': mediaRows,
      };

      final encoder = const JsonEncoder.withIndent('  ');
      final file = File(backupFilePath);
      await file.writeAsString(encoder.convert(backupPayload), flush: true);

      log('Legacy JSON backup created: $backupFilePath', name: 'DBProvider');
      return backupFilePath;
    } catch (e) {
      log('Failed to create legacy JSON backup', error: e, name: 'DBProvider');
      return null;
    }
  }

  /// Restore the database from a binary backup .isar file.
  ///
  /// Closes the live DB, replaces the primary file, and re-opens.
  ///
  /// A rollback copy is kept during restore so failed restores can recover
  /// without leaving the app in a broken state.
  static bool _restoring = false;
  static Future<Map<String, dynamic>> restoreDB(String? path,
      {Future<void> Function(String stage)? checkpoint}) async {
    if (_restoring)
      return {'success': false, 'error': 'Ripristino già in corso'};
    _restoring = true;
    Directory? validationDirectory;
    Isar? validation;
    final primaryFile = File(p.join(appSuppDir, 'dbv3.isar'));
    final rollbackFile = File(p.join(appSuppDir, 'dbv3.restore_rollback.isar'));
    var recovered = false;
    var replacing = false;

    try {
      String backupFilePath =
          path ?? (await getDbBackupFilePath()).replaceAll('.json', '.isar');
      final backupFile = File(backupFilePath);
      if (!backupFile.existsSync()) {
        return {
          'success': false,
          'error': 'Backup file not found: $backupFilePath'
        };
      }

      if (await backupFile.length() < 8192)
        throw const FormatException('Backup incompleto');
      validationDirectory =
          await Directory.systemTemp.createTemp('bloomee-restore-');
      await backupFile
          .copy(p.join(validationDirectory.path, 'restore_validation.isar'));
      validation = await Isar.open(_schemas,
          directory: validationDirectory.path, name: 'restore_validation');
      await validation.playlistDBs.count();
      await validation.close();
      validation = null;
      _maintenance?.cancel();
      _generation++;
      // Close live DB before overwriting the file.
      final isar = await db;
      await isar.close();
      replacing = true;

      if (rollbackFile.existsSync()) {
        rollbackFile.deleteSync();
      }

      if (primaryFile.existsSync()) {
        primaryFile.copySync(rollbackFile.path);
        primaryFile.deleteSync();
      }

      backupFile.copySync(primaryFile.path);

      // Re-open the DB and reassign the static future.
      await checkpoint?.call('beforeOpen');
      db = openDB();
      await db;

      if (rollbackFile.existsSync()) {
        rollbackFile.deleteSync();
      }

      recovered = true;
      log('DB restored from $backupFilePath', name: 'DBProvider');
      return {'success': true};
    } catch (e) {
      log('Failed to restore DB, attempting rollback',
          error: e, name: 'DBProvider');

      try {
        if (!replacing)
          return {'success': false, 'error': 'Backup non valido: $e'};
        if (rollbackFile.existsSync()) {
          if (primaryFile.existsSync()) {
            primaryFile.deleteSync();
          }
          rollbackFile.copySync(primaryFile.path);
        }

        await checkpoint?.call('beforeRollbackOpen');
        db = openDB();
        await db;
        recovered = true;
      } catch (rollbackError) {
        log(
          'Rollback after restore failure failed',
          error: rollbackError,
          name: 'DBProvider',
        );
      }

      return {
        'success': false,
        'error': 'Failed to restore binary backup: $e',
      };
    } finally {
      _restoring = false;
      await validation?.close();
      if (validationDirectory != null && await validationDirectory.exists())
        await validationDirectory.delete(recursive: true);
      if (recovered && rollbackFile.existsSync()) {
        try {
          rollbackFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Restore user playlists from a legacy v2 full JSON backup.
  ///
  /// By policy we restore playlists only from this format.
  static Future<Map<String, dynamic>> restoreLegacyJsonBackup(String? path,
      {bool restoreMediaItems = true}) async {
    try {
      if (path == null || path.trim().isEmpty) {
        return {'success': false, 'error': 'No backup path provided.'};
      }

      final backupFile = File(path);
      if (!backupFile.existsSync()) {
        return {'success': false, 'error': 'Backup file not found: $path'};
      }

      if (!restoreMediaItems) {
        return {
          'success': true,
          'warning':
              'Legacy restore skipped because playlists restore is disabled.',
        };
      }

      final decoded = jsonDecode(await backupFile.readAsString());
      if (decoded is! Map<String, dynamic>) {
        return {
          'success': false,
          'error': 'Invalid backup format: root JSON object expected.',
        };
      }

      if (!_isLegacyFullBackupMap(decoded)) {
        return {
          'success': false,
          'error':
              'Invalid legacy backup format: expected v2 full backup sections.',
        };
      }

      final trackDao = TrackDAO(db);
      final playlistDao = PlaylistDAO(db, trackDao);

      final playlistNames = _extractDeclaredLegacyPlaylistNames(decoded);
      for (final name in playlistNames) {
        if (name.isEmpty || standardPlaylists.contains(name)) continue;
        await playlistDao.ensurePlaylist(name);
      }

      final tracksByPlaylist = <String, List<models.Track>>{};
      final seenTrackIdsByPlaylist = <String, Set<String>>{};
      var skippedTracks = 0;

      for (final rawMediaItem in _decodeLegacySection(decoded['media_items'])) {
        final track = _legacyBackupItemToTrack(rawMediaItem);
        if (track == null) {
          skippedTracks++;
          continue;
        }

        final memberships = _extractLegacyMembershipPlaylists(rawMediaItem);
        if (memberships.isEmpty) continue;

        for (final playlistName in memberships) {
          if (playlistName.isEmpty ||
              standardPlaylists.contains(playlistName)) {
            continue;
          }

          final seen = seenTrackIdsByPlaylist.putIfAbsent(
            playlistName,
            () => <String>{},
          );
          if (!seen.add(track.id)) continue;

          tracksByPlaylist.putIfAbsent(playlistName, () => <models.Track>[]);
          tracksByPlaylist[playlistName]!.add(track);
        }
      }

      var importedPlaylists = 0;
      var importedTracks = 0;

      for (final entry in tracksByPlaylist.entries) {
        final playlistId = await playlistDao.ensurePlaylist(entry.key);
        importedPlaylists++;
        await playlistDao.addTracksToPlaylist(playlistId, entry.value);
        importedTracks += entry.value.length;
      }

      return {
        'success': true,
        'importedPlaylists': importedPlaylists,
        'importedTracks': importedTracks,
        'skippedTracks': skippedTracks,
      };
    } catch (e) {
      log('Failed to restore legacy JSON backup', error: e, name: 'DBProvider');
      return {
        'success': false,
        'error': 'Failed to restore legacy JSON backup: $e',
      };
    }
  }

  static bool _isLegacyFullBackupMap(Map<String, dynamic> map) {
    return map.containsKey('playlists') && map.containsKey('media_items');
  }

  static List<Map<String, dynamic>> _decodeLegacySection(dynamic section) {
    if (section is! List) return const [];

    final decoded = <Map<String, dynamic>>[];
    for (final entry in section) {
      if (entry is Map<String, dynamic>) {
        decoded.add(entry);
        continue;
      }
      if (entry is String) {
        try {
          final parsed = jsonDecode(entry);
          if (parsed is Map<String, dynamic>) {
            decoded.add(parsed);
          }
        } catch (_) {}
      }
    }
    return decoded;
  }

  static Set<String> _extractDeclaredLegacyPlaylistNames(
    Map<String, dynamic> payload,
  ) {
    final names = <String>{};
    for (final map in _decodeLegacySection(payload['playlists'])) {
      final name = (map['playlistName'] ?? '').toString().trim();
      if (name.isNotEmpty) {
        names.add(name);
      }
    }
    return names;
  }

  static Set<String> _extractLegacyMembershipPlaylists(
    Map<String, dynamic> mediaItem,
  ) {
    final names = <String>{};
    final raw = mediaItem['mediaInPlaylists'];
    if (raw is! List) return names;

    for (final entry in raw) {
      if (entry is Map<String, dynamic>) {
        final name = (entry['playlistName'] ?? '').toString().trim();
        if (name.isNotEmpty) names.add(name);
        continue;
      }

      if (entry is String) {
        try {
          final parsed = jsonDecode(entry);
          if (parsed is Map<String, dynamic>) {
            final name = (parsed['playlistName'] ?? '').toString().trim();
            if (name.isNotEmpty) names.add(name);
          }
        } catch (_) {}
      }
    }

    return names;
  }

  static models.Track? _legacyBackupItemToTrack(Map<String, dynamic> map) {
    final scopedId = buildPluginScopedMediaIdFromLegacyMap(map);
    if (scopedId == null || scopedId.isEmpty) {
      return null;
    }

    final title = (map['title'] ?? '').toString().trim();
    final artistRaw = (map['artist'] ?? '').toString();
    final artists = artistRaw
        .split(',')
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && name.toLowerCase() != 'unknown')
        .map((name) => models.ArtistSummary(id: '', name: name))
        .toList(growable: false);

    final albumTitle = (map['album'] ?? '').toString().trim();
    final album = albumTitle.isNotEmpty && albumTitle.toLowerCase() != 'unknown'
        ? models.AlbumSummary(
            id: '',
            title: albumTitle,
            artists: const [],
          )
        : null;

    int? durationSec;
    final rawDuration = map['duration'];
    if (rawDuration is int) {
      durationSec = rawDuration;
    } else if (rawDuration is num) {
      durationSec = rawDuration.toInt();
    }

    final artUrl = (map['artURL'] ?? '').toString();
    final permaUrl = (map['permaURL'] ?? '').toString();

    return models.Track(
      id: scopedId,
      title: title.isEmpty ? scopedId : title,
      artists: artists,
      album: album,
      durationMs: durationSec != null && durationSec > 0
          ? BigInt.from(durationSec * 1000)
          : null,
      thumbnail: models.Artwork(
        url: artUrl,
        layout: models.ImageLayout.square,
      ),
      url: permaUrl.isEmpty ? null : permaUrl,
      isExplicit: false,
    );
  }
}
