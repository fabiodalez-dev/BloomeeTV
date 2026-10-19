import 'dart:async';
import 'package:Bloomee/core/models/exported.dart';
import 'package:Bloomee/services/plugin_cache_codec.dart';
import 'tv_workspace.dart';

String tvNormalize(String text) => text
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

class TvReference {
  TvReference(this.payload, {MediaItem? item}) : _original = item;
  factory TvReference.item(MediaItem item) =>
      TvReference(tvMediaToJson(item), item: item);
  final Map<String, dynamic> payload;
  final MediaItem? _original;
  late final MediaItem item = _original ?? tvMediaFromJson(payload);
  late final String id = item.when(
      track: (t) => t.id,
      album: (a) => a.id,
      artist: (a) => a.id,
      playlist: (p) => p.id);
  late final String title = item.when(
      track: (t) => t.title,
      album: (a) => a.title,
      artist: (a) => a.name,
      playlist: (p) => p.title);
  late final String subtitle = item.when(
      track: (t) => t.artists.map((a) => a.name).join(', '),
      album: (a) => a.artists.map((a) => a.name).join(', '),
      artist: (_) => 'Artista',
      playlist: (p) => p.owner ?? 'Playlist');
  late final String? image = item.when(
      track: (t) => t.thumbnail.url,
      album: (a) => a.thumbnail?.url,
      artist: (a) => a.thumbnail?.url,
      playlist: (p) => p.thumbnail.url);
  late final String identity = item.when(
      track: (t) =>
          'track|${tvNormalize(title)}|${tvNormalize(subtitle)}|${(t.durationMs?.toInt() ?? 0) ~/ 1000}',
      album: (a) =>
          'album|${tvNormalize(title)}|${tvNormalize(subtitle)}|${a.year}',
      artist: (_) => 'artist|$id',
      playlist: (_) => 'playlist|$id');
}

class TvSavedLibrary {
  TvSavedLibrary(this.workspace);
  final TvWorkspace workspace;
  Future<void> _writes = Future.value();
  Future<void> _serialize(Future<void> Function() work) {
    final generation = workspace.generation;
    final task = _writes.then((_) async {
      if (generation == workspace.generation) await work();
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  static final instance = TvSavedLibrary(TvWorkspace.instance);
  List<TvReference> get pins => [
        for (final p in workspace['pins'] as List? ?? [])
          TvReference(Map<String, dynamic>.from(p as Map))
      ];
  List<Map<String, dynamic>> get favorites => [
        for (final g in workspace['favorites'] as List? ?? [])
          Map<String, dynamic>.from(g as Map)
      ];
  Future<void> togglePin(TvReference item) => _serialize(() async {
        final next = pins;
        if (next.any((p) => p.id == item.id)) {
          next.removeWhere((p) => p.id == item.id);
        } else {
          next.add(item);
        }
        await workspace.set('pins', [for (final p in next) p.payload]);
      });
  Future<void> movePin(int index, int delta) => _serialize(() async {
        final next = pins;
        final to = index + delta;
        if (index < 0 || index >= next.length || to < 0 || to >= next.length)
          return;
        next.insert(to, next.removeAt(index));
        await workspace.set('pins', [for (final p in next) p.payload]);
      });
  Future<void> addFavorite(TvReference item) => _serialize(() async {
        final groups = favorites;
        final existing =
            groups.where((g) => g['identity'] == item.identity).firstOrNull;
        if (existing == null) {
          groups.add({
            'identity': item.identity,
            'preferred': item.id,
            'variants': [item.payload]
          });
        } else {
          final variants = List<dynamic>.from(existing['variants'] as List);
          if (!variants.any((p) =>
              TvReference(Map<String, dynamic>.from(p as Map)).id == item.id))
            variants.add(item.payload);
          existing['variants'] = variants;
        }
        await workspace.set('favorites', groups);
      });
  Future<void> removeFavorite(String identity) =>
      _serialize(() => workspace.set('favorites',
          favorites.where((g) => g['identity'] != identity).toList()));
  Future<void> prefer(String identity, String id) => _serialize(() async {
        final groups = favorites;
        final group = groups.firstWhere((g) => g['identity'] == identity);
        if (!(group['variants'] as List).any(
            (p) => TvReference(Map<String, dynamic>.from(p as Map)).id == id))
          throw ArgumentError('Versione non presente');
        group['preferred'] = id;
        await workspace.set('favorites', groups);
      });
  Future<void> merge(String from, String into) => _serialize(() async {
        if (from == into) return;
        final groups = favorites;
        final source = groups.firstWhere((g) => g['identity'] == from);
        final target = groups.firstWhere((g) => g['identity'] == into);
        final variants = List<dynamic>.from(target['variants'] as List);
        final ids = variants
            .map((p) => TvReference(Map<String, dynamic>.from(p as Map)).id)
            .toSet();
        variants.addAll((source['variants'] as List).where((p) =>
            ids.add(TvReference(Map<String, dynamic>.from(p as Map)).id)));
        target['variants'] = variants;
        groups.remove(source);
        await workspace.set('favorites', groups);
      });
  Future<void> split(String identity, String id) => _serialize(() async {
        final groups = favorites;
        final group = groups.firstWhere((g) => g['identity'] == identity);
        final variants = List<dynamic>.from(group['variants'] as List);
        if (variants.length < 2) return;
        final selected = variants.firstWhere(
            (p) => TvReference(Map<String, dynamic>.from(p as Map)).id == id);
        variants.remove(selected);
        group['variants'] = variants;
        if (group['preferred'] == id)
          group['preferred'] =
              TvReference(Map<String, dynamic>.from(variants.first as Map)).id;
        groups.add({
          'identity': '$identity|$id',
          'preferred': id,
          'variants': [selected]
        });
        await workspace.set('favorites', groups);
      });
}
