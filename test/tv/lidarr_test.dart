import 'dart:convert';
import 'package:Bloomee/tv/connectors/lidarr_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
      'non-Latin artists remain distinct and earliest original edition wins ties',
      () async {
    final transport = MockClient((request) async => http.Response(
        jsonEncode([
          {
            'title': 'Album',
            'releaseDate': '2020-01-01',
            'foreignAlbumId': 'new',
            'artist': {'artistName': '宇多田ヒカル'}
          },
          {
            'title': 'Album',
            'releaseDate': '1999-01-01',
            'foreignAlbumId': 'original',
            'artist': {'artistName': '宇多田ヒカル'}
          },
          {
            'title': 'Album',
            'releaseDate': '1990-01-01',
            'foreignAlbumId': 'wrong',
            'artist': {'artistName': '東京事変'}
          },
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    addTearDown(transport.close);
    final result = await LidarrClient(
            baseUrl: 'http://lidarr.test', apiKey: 'secret', client: transport)
        .findAlbum(artist: '宇多田ヒカル', album: 'Album');
    expect(result.albumId, 'original', reason: result.message);
    expect(result.year, 1999);
  });
  test('single-letter artist cannot match a larger artist sharing that token',
      () async {
    final transport = MockClient((_) async => http.Response(
        '[{"title":"Album","foreignAlbumId":"wrong","artist":{"artistName":"Band A"}}]',
        200));
    addTearDown(transport.close);
    final result = await LidarrClient(
            baseUrl: 'http://lidarr.test', apiKey: 'secret', client: transport)
        .findAlbum(artist: 'A', album: 'Album');
    expect(result.status, LidarrRequestStatus.notFound);
  });
  test('a changed preview candidate is rejected before any server write',
      () async {
    var writes = 0;
    final transport = MockClient((request) async {
      if (request.method != 'GET') writes++;
      return http.Response(
          '[{"title":"Album","foreignAlbumId":"changed","artist":{"artistName":"Artist"}}]',
          200);
    });
    addTearDown(transport.close);
    final result = await LidarrClient(
            baseUrl: 'http://lidarr.test', apiKey: 'secret', client: transport)
        .requestAlbum(
            artist: 'Artist', album: 'Album', expectedAlbumId: 'confirmed');
    expect(result.status, LidarrRequestStatus.error);
    expect(writes, 0);
  });
}
