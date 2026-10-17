// Uso: dart run tool/try_lidarr_one.dart <baseUrl> <apiKey> "<artista>" "<album>" (solo ricerca)
import 'package:Bloomee/tv/connectors/lidarr_client.dart';

Future<void> main(List<String> a) async {
  final r = await LidarrClient(baseUrl: a[0], apiKey: a[1]).findAlbum(artist: a[2], album: a[3]);
  print('${r.status.name} ${r.artistName ?? ''} ${r.albumTitle ?? ''} ${r.year ?? ''} ${r.message ?? ''}');
}
