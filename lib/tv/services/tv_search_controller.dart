import 'dart:async';
import 'package:Bloomee/core/models/exported.dart';
import 'package:flutter/foundation.dart';
import 'tv_diagnostics.dart';
import 'tv_saved_library.dart';

class TvSearchHit {
  const TvSearchHit(this.reference, this.source, {this.offline = false});
  final TvReference reference;
  final String source;
  final bool offline;
  String get kind => reference.item.when(
      track: (_) => 'Brani',
      album: (_) => 'Album',
      artist: (_) => 'Artisti',
      playlist: (_) => 'Playlist');
  int? get year => reference.item.when(
      track: (t) => t.album?.year,
      album: (a) => a.year,
      artist: (_) => null,
      playlist: (_) => null);
}

typedef TvSearchProvider = Future<List<TvSearchHit>> Function(String query);

/// Sources settle independently. A new search or logout invalidates every older
/// response, including responses for the same query with different filters.
class TvSearchController extends ChangeNotifier {
  TvSearchController({this.timeout = const Duration(seconds: 12)});
  final Duration timeout;
  static List<String> sources({required bool jellyfin, required bool plugin}) =>
      [
        'Tutte',
        'Locale',
        'YouTube',
        if (jellyfin) 'Jellyfin',
        if (plugin) 'Plugin'
      ];
  final List<TvSearchHit> _hits = [];
  final Map<String, String> errors = {};
  final Set<String> loading = {};
  int _generation = 0;
  bool _disposed = false;
  String query = '';
  List<TvSearchHit> get hits => List.unmodifiable(_hits);
  void clear() {
    _generation++;
    _hits.clear();
    errors.clear();
    loading.clear();
    query = '';
    if (!_disposed) notifyListeners();
  }

  Future<void> search(String text, Map<String, TvSearchProvider> providers,
      {Map<String, TvSearchProvider> deferred = const {},
      Duration secondaryDelay = const Duration(seconds: 2)}) async {
    clear();
    query = text.trim();
    if (query.isEmpty) return;
    final generation = _generation;
    final clock = Stopwatch()..start();
    final first = Completer<void>();
    loading.addAll([...providers.keys, ...deferred.keys]);
    notifyListeners();
    Future<void> run(MapEntry<String, TvSearchProvider> entry) async {
      try {
        final result = await entry.value(query).timeout(timeout);
        if (_disposed || generation != _generation) return;
        final ids = _hits.map((h) => '${h.source}:${h.reference.id}').toSet();
        _hits.addAll(
            result.where((h) => ids.add('${h.source}:${h.reference.id}')));
        if (result.isNotEmpty && !first.isCompleted) first.complete();
        TvDiagnostics.instance.record('Ricerca',
            '${entry.key}: ${clock.elapsedMilliseconds} ms, ${result.length} risultati');
        debugPrint(
            'TV_SEARCH ${entry.key} ${clock.elapsedMilliseconds}ms ${result.length} results');
      } catch (e) {
        if (_disposed || generation != _generation) return;
        errors[entry.key] = e is TimeoutException
            ? 'Il servizio non ha risposto in tempo. Riprova.'
            : TvDiagnostics.redact(e.toString());
      } finally {
        if (!_disposed && generation == _generation) {
          loading.remove(entry.key);
          notifyListeners();
        }
      }
    }

    final primary = Future.wait(providers.entries.map(run));
    unawaited(primary.then((_) {
      if (!first.isCompleted) first.complete();
    }));
    final secondary = () async {
      if (deferred.isEmpty) return;
      final deadline = Completer<void>();
      final timer = Timer(secondaryDelay, deadline.complete);
      try {
        await Future.any([first.future, deadline.future]);
      } finally {
        timer.cancel();
      }
      if (_disposed || generation != _generation) return;
      await Future.wait(deferred.entries.map(run));
    }();
    await Future.wait([primary, secondary]);
  }

  Future<void> loadMore(String source, TvSearchProvider provider) async {
    if (loading.contains(source)) return;
    final generation = _generation;
    loading.add(source);
    errors.remove(source);
    notifyListeners();
    try {
      final result = await provider(query).timeout(timeout);
      if (_disposed || generation != _generation) return;
      final ids = _hits.map((h) => '${h.source}:${h.reference.id}').toSet();
      _hits.addAll(
          result.where((h) => ids.add('${h.source}:${h.reference.id}')));
    } catch (e) {
      if (!_disposed && generation == _generation) {
        errors[source] = e is TimeoutException
            ? 'Il servizio non ha risposto in tempo. Riprova.'
            : TvDiagnostics.redact(e.toString());
      }
    } finally {
      if (!_disposed && generation == _generation) {
        loading.remove(source);
        notifyListeners();
      }
    }
  }

  List<TvSearchHit> filtered(
      {String kind = 'Tutto',
      bool offlineOnly = false,
      int? year,
      String version = '',
      bool alphabetical = false}) {
    final result = _hits
        .where((h) =>
            (kind == 'Tutto' || h.kind == kind) &&
            (!offlineOnly || h.offline) &&
            (year == null || h.year == year) &&
            tvNormalize(h.reference.title).contains(tvNormalize(version)))
        .toList();
    if (alphabetical)
      result.sort((a, b) => tvNormalize(a.reference.title)
          .compareTo(tvNormalize(b.reference.title)));
    return result;
  }

  static Map<String, List<TvSearchHit>> variants(List<TvSearchHit> hits) {
    final groups = <String, List<TvSearchHit>>{};
    for (final hit in hits) {
      (groups[hit.reference.identity] ??= []).add(hit);
    }
    return groups;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
