import 'dart:async';
import 'package:isar_community/isar.dart';

/// Rebinds DAO reads after a restore within one profile. A profile switch gets
/// a new handle: retired DAOs must never gain access to the next profile.
/// UI subscriptions must still be rebuilt after a restore.
class SwitchableDatabase implements Future<Isar> {
  late Future<Isar> current;
  @override
  Future<R> then<R>(FutureOr<R> Function(Isar) onValue, {Function? onError}) =>
      current.then(onValue, onError: onError);
  @override
  Stream<Isar> asStream() => current.asStream();
  @override
  Future<Isar> catchError(Function onError, {bool Function(Object)? test}) =>
      current.catchError(onError, test: test);
  @override
  Future<Isar> timeout(Duration timeLimit,
          {FutureOr<Isar> Function()? onTimeout}) =>
      current.timeout(timeLimit, onTimeout: onTimeout);
  @override
  Future<Isar> whenComplete(FutureOr<void> Function() action) =>
      current.whenComplete(action);
}
