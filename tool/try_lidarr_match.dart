// Verifica dell'abbinamento (solo ricerca, non scarica nulla).
// Uso: dart run tool/try_lidarr_match.dart <baseUrl> <apiKey>
import 'package:Bloomee/tv/connectors/lidarr_client.dart';

Future<void> main(List<String> a) async {
  final c = LidarrClient(baseUrl: a[0], apiKey: a[1]);
  for (final q in [
    ['Geolier', 'TUTTO È POSSIBILE - ATTO II'],
    ['Geolier', 'Tutto è possibile'],
    ['Green Day', 'Dookie (Remastered)'],
    ['Alkaline Trio', 'Goddamnit'],
    ['Bad Religion', 'Suffer'],
    ['Rino Gaetano', 'E io ci sto'],
  ]) {
    final r = await c.findAlbum(artist: q[0], album: q[1]);
    print('${q[0]} / ${q[1]} -> ${r.status.name} ${r.artistName ?? ''} ${r.albumTitle ?? ''} ${r.year ?? ''} ${r.message ?? ''}');
  }
}
