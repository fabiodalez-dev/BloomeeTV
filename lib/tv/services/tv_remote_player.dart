import 'tv_remote_catalog.dart';
import 'package:Bloomee/services/bloomee_player.dart';
import 'package:Bloomee/services/player/player_engine.dart';
import 'tv_remote_server.dart';

void attachTvRemote(BloomeeMusicPlayer player) {
  final catalog = TvRemoteCatalog(player);
  tvRemote.browse = catalog.browse;
  tvRemote.resetCatalog = catalog.reset;
  tvRemote.readState = () {
    final item = player.mediaItem.valueOrNull;
    return {
      'name': 'Bloomee Android TV',
      'title': item?.title ?? 'Nessun brano',
      'artist': item?.artist ?? '',
      'playing': player.engine.playing,
      'positionMs': player.engine.position.inMilliseconds,
      'durationMs': player.engine.duration.inMilliseconds,
      'volume': player.engine.volume,
      'shuffle': player.shuffleMode.value,
      'repeat': player.loopMode.value == LoopMode.off ? 'off' : 'all',
      'index': player.currentQueueIndex,
      'queueTotal': player.queue.value.length,
      'queue': player.queue.value
          .take(500)
          .map((m) => {
                'title': m.title,
                'artist': m.artist ?? '',
              })
          .toList(),
    };
  };
  tvRemote.execute = (body) async {
    final value = body['value'];
    if (validCatalogCommand(body['action'], value)) {
      await catalog.command(body);
      return;
    }
    switch (body['action']) {
      case 'play':
        await player.play();
      case 'pause':
        await player.pause();
      case 'next':
        await player.skipToNext();
      case 'previous':
        await player.skipToPrevious();
      case 'seek':
        await player.seek(Duration(milliseconds: value as int));
      case 'volume':
        await player.engine.setVolume((value as num).toDouble());
      case 'shuffle':
        await player.shuffle(value as bool);
      case 'repeat':
        player.setLoopMode(value == 'all' ? LoopMode.all : LoopMode.off);
      case 'queue':
        if ((value as int) >= player.queue.value.length) {
          throw const FormatException();
        }
        await player.skipToQueueItem(value);
    }
  };
}
