import 'package:Bloomee/core/models/exported.dart';

Track track(String id, {String? title, String artist = 'Artista'}) => Track(
      id: id,
      title: title ?? 'Brano $id',
      artists: [ArtistSummary(id: 'artist', name: artist)],
      thumbnail: const Artwork(url: '', layout: ImageLayout.square),
      isExplicit: false,
    );
