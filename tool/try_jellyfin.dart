// Prova manuale del connettore Jellyfin con un token esistente.
// Uso: dart run tool/try_jellyfin.dart <baseUrl> <token> <userId>
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:http/http.dart' as http;

Future<void> main(List<String> a) async {
  final c = JellyfinClient(baseUrl: a[0], token: a[1], userId: a[2]);
  print('server: ${await c.serverName()}');
  final recent = await c.recentAlbums(limit: 5);
  print('ultimi album: ${recent.map((e) => '${e.albumArtist} - ${e.name} (${e.year})').join(' | ')}');
  final tracks = await c.albumTracks(recent.first.id);
  print('brani del primo: ${tracks.length}, es. ${tracks.first.trackNumber}. ${tracks.first.name} ${tracks.first.duration}');
  final s = await c.search('Rino');
  print('ricerca "Rino": ${s.take(4).map((e) => '${e.type}:${e.name}').join(', ')}');
  final r = await http.get(Uri.parse(c.streamUrl(tracks.first.id)), headers: {'Range': 'bytes=0-65535'});
  print('stream: HTTP ${r.statusCode}, ${r.headers['content-type']}, ${r.bodyBytes.length} byte');
  final img = await http.get(Uri.parse(c.imageUrl(recent.first.imageItemId!)));
  print('copertina: HTTP ${img.statusCode}, ${img.headers['content-type']}, ${img.bodyBytes.length} byte');
}
