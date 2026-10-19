import 'dart:async';
import 'package:flutter/foundation.dart';
import 'tv_workspace.dart';
import 'tv_diagnostics.dart';

class TvOperations extends ChangeNotifier {
  static final instance = TvOperations();
  final Set<String> _running = {};
  final Map<String, Completer<void>> _done = {};
  final Map<String, void Function()> _aborts = {};
  final Set<String> _cancelled = {};
  List<Map<String, dynamic>> get entries => [
        for (final v
            in (TvWorkspace.instance['operations'] as Map? ?? {}).values)
          Map<String, dynamic>.from(v as Map)
      ];
  bool cancelled(String id) => _cancelled.contains(id);
  void cancel(String id) {
    _cancelled.add(id);
    _aborts[id]?.call();
    notifyListeners();
  }

  Future<void> cancelAll() async {
    for (final id in _running.toList()) {
      cancel(id);
    }
    await Future.wait(_done.values.map((c) => c.future).toList());
  }

  Future<void> update(String id, Map<String, dynamic> values) async {
    if (!TvWorkspace.instance.initialized) return;
    await TvWorkspace.instance.mutate('operations', (old) {
      final entries = Map<String, dynamic>.from(old as Map? ?? {});
      final previous =
          Map<String, dynamic>.from(entries.remove(id) as Map? ?? {});
      entries[id] = {
        ...previous,
        'id': id,
        ...values,
        'updated': DateTime.now().toUtc().toIso8601String()
      };
      while (entries.length > 100) {
        final removable =
            entries.keys.where((key) => !_running.contains(key)).firstOrNull;
        if (removable == null) break;
        entries.remove(removable);
      }
      return entries;
    });
    notifyListeners();
  }

  Future<void> reconcileInterrupted() => TvWorkspace.instance.mutate(
      'operations',
      (old) => {
            for (final entry in (old as Map? ?? {}).entries)
              entry.key: {
                ...Map<String, dynamic>.from(entry.value as Map),
                if (entry.value['state'] == 'in corso' &&
                    !_running.contains(entry.key))
                  'state': 'interrotto'
              },
          });
  Future<T?> run<T>(
      String id, Map<String, dynamic> initial, Future<T> Function() work,
      {void Function()? onCancel}) async {
    if (!_running.add(id)) return null;
    _cancelled.remove(id);
    final done = Completer<void>();
    _done[id] = done;
    if (onCancel != null) _aborts[id] = onCancel;
    try {
      await update(id, {...initial, 'state': 'in corso'});
      return await work();
    } catch (e) {
      await update(id, {
        'state': cancelled(id) ? 'annullato' : 'errore',
        'error': TvDiagnostics.redact(e.toString())
      });
      TvDiagnostics.instance.record('Operazioni', e);
      rethrow;
    } finally {
      _running.remove(id);
      _aborts.remove(id);
      _done.remove(id);
      done.complete();
    }
  }
}
