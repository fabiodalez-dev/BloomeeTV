// Prova manuale del connettore Lidarr (solo anteprima, non aggiunge nulla).
// Uso: dart run tool/try_lidarr.dart <baseUrl> <apiKey> "<artista>" "<album>"
import 'package:Bloomee/tv/connectors/lidarr_client.dart';

Future<void> main(List<String> a) async {
  final c = LidarrClient(baseUrl: a[0], apiKey: a[1]);
  print(await c.ping());
  final r = await c.findAlbum(artist: a[2], album: a[3]);
  print('${r.status.name}: ${r.artistName} - ${r.albumTitle} (${r.year}) ${r.message ?? ''}');
}
