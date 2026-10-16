import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:topo_tv/api/tapo_cloud.dart';

Uint8List _part(List<int> payload, {String extra = ''}) => Uint8List.fromList([
      ...ascii.encode('----device-stream-boundary--\r\n'
          'Content-Type: video/mp2t\r\n$extra'
          'Content-Length: ${payload.length}\r\n\r\n'),
      ...payload,
      ...ascii.encode('\r\n'),
    ]);

/// Splits [data] into random-sized chunks, like TLS records would.
Stream<Uint8List> _chunked(List<int> data, int seed) async* {
  final rng = Random(seed);
  var i = 0;
  while (i < data.length) {
    final n = min(1 + rng.nextInt(700), data.length - i);
    yield Uint8List.fromList(data.sublist(i, i + n));
    i += n;
  }
}

void main() {
  final head = ascii.encode('HTTP/1.1 200 OK\r\n'
      'Content-Type: multipart/mixed;boundary=--device-stream-boundary--\r\n'
      'Connection: keep-alive\r\n\r\n');

  test('extracts video payloads across arbitrary chunk boundaries', () async {
    final rng = Random(1);
    final payloads = [
      for (var p = 0; p < 30; p++) List<int>.generate(1 + rng.nextInt(5000), (_) => rng.nextInt(256)),
    ];
    final wire = <int>[...head, for (final p in payloads) ..._part(p)];
    final expected = [for (final p in payloads) ...p];
    for (var seed = 0; seed < 20; seed++) {
      final out = <int>[];
      // The relay never ends on its own; the parser reports the close.
      await expectLater(
        parseRelayResponse(_chunked(wire, seed)).forEach(out.addAll),
        throwsA(isA<TapoException>()),
      );
      expect(out, expected, reason: 'seed $seed');
    }
  });

  test('rejects a non-200 relay answer', () async {
    final wire = ascii.encode('HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n');
    expect(parseRelayResponse(_chunked(wire, 0)).toList(), throwsA(isA<TapoException>()));
  });

  test('reports encrypted streams', () async {
    final wire = [...head, ..._part([1, 2, 3], extra: 'X-If-Encrypt: 1\r\n')];
    expect(
      parseRelayResponse(_chunked(wire, 0)).toList(),
      throwsA(predicate((e) => e is TapoException && e.message.contains('encrypted'))),
    );
  });
}
