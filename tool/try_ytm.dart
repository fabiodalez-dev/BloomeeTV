// Prova del client YouTube Music senza account: dart run tool/try_ytm.dart "Green Day"
import 'package:Bloomee/tv/connectors/ytmusic_account.dart';

Future<void> main(List<String> a) async {
  final c = YtMusicClient();
  final ch = await c.findArtistChannel(a.isEmpty ? 'Green Day' : a[0]);
  print('canale: $ch');
  final info = await c.artist(ch!);
  print('nome: ${info.name}');
  print('ascoltatori: ${info.monthlyListeners} | iscritti: ${info.subscribers}');
  print('banner: ${info.banner}');
  print('about: ${info.description?.substring(0, (info.description!.length).clamp(0, 160))}');
  for (final s in info.sections.take(6)) {
    print('sezione "${s.title}": ${s.items.length} -> ${s.items.take(3).map((e) => '${e.kind}:${e.title}${e.videoId != null ? '[${e.videoId}]' : ''}${e.browseId != null ? '{${e.browseId}}' : ''}').join(', ')}');
  }
  final alb = info.sections.expand((s) => s.items).firstWhere((i) => i.kind == 'album');
  final col = await c.collection(alb.browseId!);
  print('album "${col.title}" (${col.subtitle}): ${col.tracks.length} brani, es. ${col.tracks.take(2).map((t) => '${t.title}[${t.videoId}] ${t.duration} art=${t.artistNames}').join(' | ')}');
  final home = await c.home();
  print('home pubblica: ${home.map((s) => '${s.title}(${s.items.length})').take(6).join(', ')}');
}
