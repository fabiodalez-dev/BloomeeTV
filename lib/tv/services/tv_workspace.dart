import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

/// Small, versioned, profile-scoped preferences. Writes are serialized and atomic.
class TvWorkspace extends ChangeNotifier {
  static final instance = TvWorkspace();
  Directory? _directory;
  Map<String, dynamic> _data = {};
  Future<void> _writes = Future.value();
  int generation = 0;
  bool get initialized => _directory != null;
  dynamic operator [](String key) => _data[key];
  Future<void> open(Directory directory) async {
    await _writes;
    _directory = directory;
    await directory.create(recursive: true);
    final f = File('${directory.path}/tv-workspace.json');
    _data = await f.exists() ? await _read(f) : {};
    final catalog = File('${directory.path}/tv-catalog.json');
    if (await catalog.exists()) _data['catalog'] = await _read(catalog);
    generation++;
    notifyListeners();
  }

  Future<void> set(String key, dynamic value) => mutate(key, (_) => value);
  Future<void> mergeMap(String key, Map<String, dynamic> values) =>
      mutate(key, (old) => {...?(old as Map?), ...values});
  Future<void> mutate(
      String key, FutureOr<dynamic> Function(dynamic value) change,
      {int? expectedGeneration}) {
    final directory = _directory;
    final generationAtCall = generation;
    if (directory == null) throw StateError('Profilo non inizializzato');
    final task = _writes.then((_) async {
      if (generation != generationAtCall ||
          (expectedGeneration != null && generation != expectedGeneration))
        return;
      final next = {..._data, key: await change(_data[key]), 'version': 1};
      // Catalog responses can be megabytes. Preferences never rewrite them;
      // their encoding runs outside the UI isolate and does not rebuild Home.
      final isCatalog = key == 'catalog';
      final payload = isCatalog
          ? next['catalog']
          : (Map<String, dynamic>.from(next)..remove('catalog'));
      // Preserve a legacy embedded catalog before dropping it from preferences.
      final catalog = File('${directory.path}/tv-catalog.json');
      if (!isCatalog && next['catalog'] != null && !await catalog.exists()) {
        await _write(catalog, await compute(jsonEncode, next['catalog']));
      }
      final target = File(
          '${directory.path}/${isCatalog ? 'tv-catalog' : 'tv-workspace'}.json');
      await _write(target,
          isCatalog ? await compute(jsonEncode, payload) : jsonEncode(payload));
      _data = next;
      if (!isCatalog) notifyListeners();
    });
    _writes = task.catchError((Object _) {});
    return task;
  }

  Future<void> flush() => _writes;

  static Future<Map<String, dynamic>> _read(File file) async {
    final text = await file.readAsString();
    final value = text.length > 65536
        ? await compute(jsonDecode, text)
        : jsonDecode(text);
    return Map<String, dynamic>.from(value as Map);
  }

  static Future<void> _write(File target, String text) async {
    final stage = File('${target.path}.tmp');
    await stage.writeAsString(text, flush: true);
    await stage.rename(target.path);
  }

  Future<bool> claimGuidePrompt({required bool configured}) async {
    var show = false;
    await mutate('introShownTv', (old) {
      show = old != true && _data['onboardedTv'] != true && !configured;
      return true;
    });
    return show;
  }
}

class TvProfile {
  const TvProfile(this.id, this.name, {this.guest = false});
  final String id;
  final String name;
  final bool guest;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'guest': guest};
}

class TvProfiles extends ChangeNotifier {
  static final instance = TvProfiles();
  late Directory root;
  List<TvProfile> _profiles = [const TvProfile('default', 'Casa')];
  String selectedId = 'default';
  bool switching = false;
  Future<void> Function(TvProfile profile)? onSwitch;
  Future<void> Function(String profileId)? onDiscardGuest;
  List<TvProfile> get profiles => List.unmodifiable(_profiles);
  TvProfile get selected => _profiles.firstWhere((p) => p.id == selectedId);
  Directory directoryFor(String id) =>
      id == 'default' ? root : Directory('${root.path}/profiles/$id');
  Future<void> open(Directory directory) async {
    root = directory;
    await root.create(recursive: true);
    final f = File('${root.path}/tv-profiles.json');
    _profiles = [const TvProfile('default', 'Casa')];
    selectedId = 'default';
    if (await f.exists()) {
      final m = jsonDecode(await f.readAsString()) as Map;
      _profiles = [
        for (final p in m['profiles'] as List)
          TvProfile(p['id'] as String, p['name'] as String)
      ];
      if (_profiles.any((p) =>
              p.id != 'default' && !RegExp(r'^[0-9a-f]{32}$').hasMatch(p.id)) ||
          !_profiles.any((p) => p.id == 'default'))
        throw const FormatException('Registro profili non valido');
      selectedId = m['selected'] as String;
      if (!_profiles.any((p) => p.id == selectedId)) selectedId = 'default';
    }
    final profileRoot = Directory('${root.path}/profiles');
    if (await profileRoot.exists()) {
      await for (final entry in profileRoot.list(followLinks: false)) {
        final id = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (entry is Directory &&
            RegExp(r'^[0-9a-f]{32}$').hasMatch(id) &&
            !_profiles.any((p) => p.id == id)) {
          await onDiscardGuest?.call(id);
          await entry.delete(recursive: true);
        }
      }
    }
    await TvWorkspace.instance.open(directoryFor(selectedId));
  }

  Future<TvProfile> create(String name, {bool guest = false}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 60)
      throw ArgumentError('Nome da 1 a 60 caratteri');
    if (_profiles.any((p) => p.name.toLowerCase() == trimmed.toLowerCase()))
      throw ArgumentError('Nome già usato');
    final id = List.generate(
            16,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    final profile = TvProfile(id, trimmed, guest: guest);
    await directoryFor(id).create(recursive: true);
    _profiles = [..._profiles, profile];
    await _save();
    notifyListeners();
    return profile;
  }

  Future<void> select(String id) async {
    if (switching || id == selectedId) return;
    final next = _profiles.firstWhere((p) => p.id == id);
    final old = selected;
    switching = true;
    notifyListeners();
    try {
      if (onSwitch == null) throw StateError('Cambio profilo non disponibile');
      await onSwitch!(next);
      selectedId = id;
      if (old.guest) {
        await onDiscardGuest?.call(old.id);
        final dir = directoryFor(old.id);
        if (await dir.exists()) await dir.delete(recursive: true);
        _profiles.removeWhere((p) => p.id == old.id);
      }
      await _save();
    } finally {
      switching = false;
      notifyListeners();
    }
  }

  Future<void> _save() async {
    final f = File('${root.path}/tv-profiles.json.tmp');
    await f.writeAsString(
        jsonEncode({
          'version': 1,
          'selected': selected.guest ? 'default' : selectedId,
          'profiles': [
            for (final p in _profiles.where((p) => !p.guest)) p.toJson()
          ]
        }),
        flush: true);
    await f.rename('${root.path}/tv-profiles.json');
  }
}
