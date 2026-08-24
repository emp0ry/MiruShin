import 'package:flutter_test/flutter_test.dart';
import 'package:mirushin/features/player/engine/dash_hls_manifest.dart';

void main() {
  test('converts static DASH SegmentTemplate tracks to fMP4 HLS', () {
    const String manifest = r'''<?xml version="1.0"?>
<MPD xmlns="urn:mpeg:dash:schema:mpd:2011" type="static"
    mediaPresentationDuration="PT6S">
  <Period>
    <AdaptationSet contentType="video" frameRate="24">
      <Representation id="0" mimeType="video/mp4" codecs="avc1.4d4028"
          bandwidth="900000" width="1920" height="1080">
        <SegmentTemplate timescale="1000" startNumber="1"
            initialization="init-stream$RepresentationID$.m4s"
            media="chunk-stream$RepresentationID$-$Number%05d$.m4s">
          <SegmentTimeline><S t="0" d="3000" r="1" /></SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
    <AdaptationSet contentType="audio" lang="ru">
      <Role value="AniLibria" />
      <Representation id="1" mimeType="audio/mp4" codecs="mp4a.40.2"
          bandwidth="128000">
        <SegmentTemplate timescale="1000" startNumber="1"
            initialization="init-stream$RepresentationID$.m4s"
            media="chunk-stream$RepresentationID$-$Number%05d$.m4s">
          <SegmentTimeline><S t="0" d="2000" r="2" /></SegmentTimeline>
        </SegmentTemplate>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';

    final DashHlsPresentation presentation = buildDashHlsPresentation(
      manifest: manifest,
      manifestUri: Uri.parse('https://cdn.example/show/1080.mpd'),
      mediaUrlFor: (Uri uri) =>
          'http://127.0.0.1/dash-media?u=${Uri.encodeQueryComponent(uri.toString())}',
      mediaPlaylistUrlFor: (String id) =>
          'http://127.0.0.1/dash-hls-media?track=$id',
    );

    expect(presentation.masterPlaylist, contains('#EXT-X-MEDIA:TYPE=AUDIO'));
    expect(presentation.masterPlaylist, contains('NAME="AniLibria"'));
    expect(presentation.masterPlaylist, contains('AUDIO="audio"'));
    expect(
      presentation.masterPlaylist,
      contains('CODECS="avc1.4d4028,mp4a.40.2"'),
    );
    expect(presentation.masterPlaylist, contains('RESOLUTION=1920x1080'));

    final String video = presentation.mediaPlaylists['video0']!;
    expect(video, contains('#EXT-X-TARGETDURATION:3'));
    expect(
      video,
      contains(
        Uri.encodeQueryComponent('https://cdn.example/show/init-stream0.m4s'),
      ),
    );
    expect(
      video,
      contains(
        Uri.encodeQueryComponent(
          'https://cdn.example/show/chunk-stream0-00001.m4s',
        ),
      ),
    );
    expect(
      video,
      contains(
        Uri.encodeQueryComponent(
          'https://cdn.example/show/chunk-stream0-00002.m4s',
        ),
      ),
    );
    expect('#EXTINF:'.allMatches(video), hasLength(2));

    final String audio = presentation.mediaPlaylists['audio0']!;
    expect('#EXTINF:'.allMatches(audio), hasLength(3));
    expect(audio, contains('#EXT-X-ENDLIST'));
  });

  test('rejects dynamic MPDs with a useful compatibility error', () {
    expect(
      () => buildDashHlsPresentation(
        manifest: '<MPD type="dynamic"><Period /></MPD>',
        manifestUri: Uri.parse('https://cdn.example/live.mpd'),
        mediaUrlFor: (Uri uri) => uri.toString(),
        mediaPlaylistUrlFor: (String id) => id,
      ),
      throwsA(
        isA<UnsupportedError>().having(
          (UnsupportedError error) => error.message,
          'message',
          contains('static/VOD'),
        ),
      ),
    );
  });
}
