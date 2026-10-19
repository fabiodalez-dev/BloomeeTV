import 'package:Bloomee/services/player/queue_manager.dart';
import 'package:Bloomee/services/player/player_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/tracks.dart';

void main() {
  late QueueManager queue;
  setUp(() => queue = QueueManager());
  tearDown(() => queue.dispose());
  test('moving later songs preserves current song and changes actual next', () {
    final songs = [track('a'), track('b'), track('c'), track('d')];
    queue.updateQueue(songs, startIndex: 1);
    expect(
        queue.applyEdit(
            songs, [songs[0], songs[1], songs[3], songs[2]], [0, 1, 3, 2]),
        isTrue);
    expect(queue.currentTrack, same(songs[1]));
    expect(queue.peekNext(), same(songs[3]));
    queue.advanceToNext();
    expect(queue.currentTrack, same(songs[3]));
  });
  test('current occurrence moves to requested index', () {
    final songs = [track('a'), track('b'), track('c')];
    queue.updateQueue(songs, startIndex: 1);
    queue.applyEdit(songs, [songs[1], songs[0], songs[2]], [1, 0, 2]);
    expect(queue.currentIndex, 0);
    expect(queue.currentTrack, same(songs[1]));
  });
  test('repeated identical objects preserve the exact playing occurrence', () {
    final song = track('a');
    final other = track('b');
    queue.updateQueue([song, other]);
    queue.applyEdit([song, other], [song, song, other], [0, -1, 1]);
    queue.jumpTo(1);
    expect(queue.applyEdit([song, song, other], [song, other, song], [1, 2, 0]),
        isTrue);
    expect(queue.currentIndex, 0);
  });
  test('removing an earlier entry keeps current and undo restores ordering',
      () {
    final songs = [track('a'), track('b'), track('c')];
    queue.updateQueue(songs, startIndex: 1);
    queue.applyEdit(songs, [songs[1], songs[2]], [1, 2]);
    expect(queue.currentIndex, 0);
    queue.applyEdit([songs[1], songs[2]], songs, [-1, 0, 1]);
    expect(queue.currentIndex, 1);
    expect(queue.tracks, orderedEquals(songs));
  });
  test('removing current reports stop and empty queue is safe', () {
    final songs = [track('a'), track('b')];
    queue.updateQueue(songs);
    expect(queue.applyEdit(songs, [songs[1]], [1]), isFalse);
    expect(queue.applyEdit([songs[1]], [], []), isFalse);
    expect(queue.currentTrack, isNull);
    expect(queue.peekNext(loopMode: LoopMode.all), isNull);
  });
  test('editing after automatic advance preserves the song now playing', () {
    final songs = [track('a'), track('b'), track('c')];
    queue.updateQueue(songs);
    queue.advanceToNext();
    queue.applyEdit(songs, [songs[2], songs[0], songs[1]], [2, 0, 1]);
    expect(queue.currentTrack, same(songs[1]));
    expect(queue.currentIndex, 2);
  });
  test('stale editor cannot overwrite an externally replaced queue', () {
    final songs = [track('a'), track('b')];
    queue.updateQueue([track('new')]);
    expect(() => queue.applyEdit(songs, songs.reversed.toList(), [1, 0]),
        throwsStateError);
    expect(queue.currentTrack!.id, 'new');
  });
  test('invalid origins fail atomically', () {
    final songs = [track('a'), track('b')];
    queue.updateQueue(songs);
    expect(() => queue.applyEdit(songs, songs, [0, 0]), throwsArgumentError);
    expect(queue.tracks, songs);
  });
  test('explicit order disables shuffle so displayed order matches playback',
      () {
    final songs = [track('a'), track('b'), track('c')];
    queue.updateQueue(songs, startIndex: 1);
    queue.shuffle(true);
    queue.applyEdit(songs, songs, [0, 1, 2]);
    expect(queue.shuffleMode.value, isFalse);
    expect(queue.peekNext(), same(songs[2]));
  });
  test('ReorderableListView insertion slot moves down and preserves current',
      () {
    final songs = [track('a'), track('b'), track('c')];
    queue.updateQueue(songs, startIndex: 1);
    queue.moveTrack(1, 3);
    expect(queue.tracks.map((t) => t.id), ['a', 'c', 'b']);
    expect(queue.currentIndex, 2);
    queue.moveTrack(-1, 0);
    queue.removeTrackAt(-1);
    expect(queue.currentTrack, same(songs[1]));
  });
}
