import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'tv_workspace.dart';

abstract class TvAuthenticationFailure implements Exception {}

/// Metadata only, isolated by profile; authentication failures never use cache.
class TvCatalogCache extends ChangeNotifier {
  static final instance = TvCatalogCache();
  final Map<String, DateTime> offlineSources = {};
  int _generation = 0;
  final Map<String, (DateTime, Object)> _search = {};
  int _searchProfile = -1;

  /// Short-lived search responses never serialize the offline catalog or wait
  /// for flash storage. Account/profile changes invalidate this memory cache.
  Future<T> search<T extends Object>(
      {required String source,
      required String key,
      required Future<T> Function() load}) async {
    final profile = TvWorkspace.instance.generation;
    if (_searchProfile != profile) {
      _search.clear();
      _searchProfile = profile;
    }
    final generation = _generation;
    final fullKey = '$source:$key';
    final cached = _search[fullKey];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 2)) {
      return cached.$2 as T;
    }
    final result = await load();
    if (generation == _generation &&
        profile == TvWorkspace.instance.generation) {
      _search.remove(fullKey);
      _search[fullKey] = (DateTime.now(), result);
      while (_search.length > 16) {
        _search.remove(_search.keys.first);
      }
    }
    return result;
  }

  static String keyFor(Object value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();
  Future<T> readThrough<T>(
      {required String source,
      required String key,
      required Future<T> Function() load,
      int maxRecords = 40}) async {
    final workspace = TvWorkspace.instance;
    final generation = _generation;
    final profile = workspace.generation;
    final cache = Map<String, dynamic>.from(workspace['catalog'] as Map? ?? {});
    final fullKey = '$source:$key';
    try {
      final result = await load();
      if (generation == _generation &&
          profile == workspace.generation &&
          workspace.initialized) {
        await workspace.mutate('catalog', (old) async {
          if (generation != _generation) return old;
          final bounded = Map<String, dynamic>.from(old as Map? ?? {});
          bounded.remove(fullKey);
          bounded[fullKey] = {
            'source': source,
            'time': DateTime.now().toUtc().toIso8601String(),
            'value': result
          };
          return compute(_boundCatalog, (bounded, maxRecords));
        }, expectedGeneration: profile);
        offlineSources.remove(source);
        notifyListeners();
      }
      return result;
    } catch (error) {
      if (error is TvAuthenticationFailure ||
          generation != _generation ||
          profile != workspace.generation) rethrow;
      final record = cache[fullKey] as Map?;
      if (record == null) rethrow;
      final time = DateTime.parse(record['time'] as String);
      // Stale catalogs remain browsable, always labelled with their actual age.
      offlineSources[source] = time;
      notifyListeners();
      return record['value'] as T;
    }
  }

  Future<void> clearSource(String source) async {
    _generation++;
    _search.removeWhere((key, _) => key.startsWith('$source:'));
    offlineSources.remove(source);
    final workspace = TvWorkspace.instance;
    if (workspace.initialized) {
      await workspace.mutate(
          'catalog',
          (old) => Map<String, dynamic>.from(old as Map? ?? {})
            ..removeWhere((key, _) => key.startsWith('$source:')));
    }
    notifyListeners();
  }

  void resetSession() {
    _generation++;
    _search.clear();
    offlineSources.clear();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _generation++;
    _search.clear();
    offlineSources.clear();
    if (TvWorkspace.instance.initialized)
      await TvWorkspace.instance.set('catalog', <String, dynamic>{});
    notifyListeners();
  }
}

Map<String, dynamic> _boundCatalog((Map<String, dynamic>, int) input) {
  final (records, maxRecords) = input;
  while (records.length > maxRecords ||
      utf8.encode(jsonEncode(records)).length > 8 * 1024 * 1024) {
    if (records.isEmpty) break;
    records.remove(records.keys.first);
  }
  return records;
}
