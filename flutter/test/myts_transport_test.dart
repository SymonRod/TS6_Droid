// The production HTTP transport against a loopback server: no redirects, no
// body read for non-200, receive cap enforced while streaming, no compression,
// deadline. (TLS verification is dart:io's default: no badCertificateCallback.)
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/myts/api.dart';

void main() {
  late HttpServer server;
  late Uri uri;
  var requests = 0;
  Future<void> Function(HttpRequest) handler = (_) async {};

  setUp(() async {
    requests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    uri = Uri.parse('http://127.0.0.1:${server.port}/synchronization');
    server.listen((req) async {
      requests++;
      await req.drain<void>();
      await handler(req);
    });
    addTearDown(() => server.close(force: true));
  });

  Future<MyTsHttpResponse> post({int cap = 1024, Duration? deadline}) => myTsHttpPost(
    uri,
    {HttpHeaders.contentTypeHeader: 'application/ts3cloud'},
    Uint8List.fromList([1, 2, 3]),
    cap,
    deadline: deadline ?? const Duration(seconds: 5),
  );

  test('returns the body of a normal reply', () async {
    handler = (req) async {
      req.response.add(List.filled(100, 7));
      await req.response.close();
    };
    final r = await post();
    expect((r.status, r.body.length), (200, 100));
  });

  test('a redirect is not followed and nothing is re-sent', () async {
    handler = (req) async {
      req.response
        ..statusCode = HttpStatus.found
        ..headers.set(HttpHeaders.locationHeader, uri.toString());
      await req.response.close();
    };
    final r = await post();
    expect(r.status, 302);
    expect(r.body, isEmpty);
    expect(requests, 1);
  });

  test('a non-200 body is not read', () async {
    handler = (req) async {
      req.response.statusCode = 503;
      req.response.add(List.filled(100000, 1));
      await req.response.close();
    };
    final r = await post(cap: 10);
    expect(r.status, 503);
    expect(r.body, isEmpty);
  });

  test('a declared length above the cap is rejected', () async {
    handler = (req) async {
      req.response.contentLength = 5000;
      req.response.add(List.filled(5000, 1));
      await req.response.close();
    };
    await expectLater(post(cap: 1000), throwsA(isA<MyTsResponseRejected>()));
  });

  test('a chunked reply is cut off at the cap while streaming', () async {
    handler = (req) async {
      req.response.headers.chunkedTransferEncoding = true;
      for (var i = 0; i < 20; i++) {
        req.response.add(List.filled(100, 1));
        await req.response.flush();
      }
      await req.response.close();
    };
    await expectLater(post(cap: 1000), throwsA(isA<MyTsResponseRejected>()));
  });

  test('a reply exactly at the cap is accepted', () async {
    handler = (req) async {
      req.response.add(List.filled(1000, 1));
      await req.response.close();
    };
    expect((await post(cap: 1000)).body.length, 1000);
  });

  test('content encodings are refused (no decompression bombs)', () async {
    handler = (req) async {
      req.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
      req.response.add(gzip.encode(List.filled(100, 1)));
      await req.response.close();
    };
    await expectLater(post(), throwsA(isA<MyTsResponseRejected>()));
  });

  test('a stalled reply hits the overall deadline', () async {
    final stall = Completer<void>();
    addTearDown(() {
      if (!stall.isCompleted) stall.complete();
    });
    handler = (req) async {
      req.response.headers.chunkedTransferEncoding = true;
      req.response.add([1]);
      await req.response.flush();
      await stall.future; // never finishes the body
    };
    await expectLater(
      post(deadline: const Duration(milliseconds: 300)),
      throwsA(isA<TimeoutException>()),
    );
  });
}
