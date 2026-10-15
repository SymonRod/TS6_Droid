import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/myts/public_https.dart';

class _RealHttp extends HttpOverrides {}

void main() {
  final cert = File('test/fixtures/https/cert.pem').readAsBytesSync();
  final key = File('test/fixtures/https/key.pem').readAsBytesSync();
  SecurityContext trusted() =>
      SecurityContext()..setTrustedCertificatesBytes(cert);
  SecurityContext serverContext() => SecurityContext()
    ..useCertificateChainBytes(cert)
    ..usePrivateKeyBytes(key);

  Future<ConnectionTask<Socket>> connect(
    int port, {
    SecurityContext? context,
    bool wrongHost = false,
  }) async {
    final address = wrongHost
        ? InternetAddress.loopbackIPv4
        : (await InternetAddress.lookup(
            'localhost',
            type: InternetAddressType.IPv4,
          )).first;
    return verifiedTlsConnection(address, port, context: context);
  }

  test('HTTP POST reaches the server only after verified TLS', () async {
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext(),
    );
    addTearDown(() => server.close(force: true));
    final received = Completer<String>();
    server.listen((request) async {
      received.complete(await utf8.decoder.bind(request).join());
      request.response.write('{"versions":["v1.1"]}');
      await request.response.close();
    });
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      client.connectionFactory = (uri, proxy, port) =>
          connect(server.port, context: trusted());
      final request = await client.postUrl(
        Uri.https('chat.example.org', '/_matrix/client/r0/login'),
      );
      request.write('synthetic-password-only');
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(await utf8.decoder.bind(response).join(), contains('versions'));
    }, _RealHttp());
    expect(await received.future, 'synthetic-password-only');
  });

  test('default trust rejects a self-signed server before any HTTP', () async {
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext(),
    );
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((_) => requests++, onError: (Object _) {});
    final task = await connect(server.port);
    await expectLater(task.socket, throwsA(isA<HandshakeException>()));
    expect(requests, 0);
  });

  test('trusted certificate with wrong hostname is rejected', () async {
    final server = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      serverContext(),
    );
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((_) => requests++, onError: (Object _) {});
    final task = await connect(
      server.port,
      context: trusted(),
      wrongHost: true,
    );
    await expectLater(task.socket, throwsA(isA<HandshakeException>()));
    expect(requests, 0);
  });

  test('first wire bytes are TLS, never an HTTP request', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final first = Completer<List<int>>();
    server.listen((socket) {
      addTearDown(socket.destroy);
      socket.listen((bytes) {
        if (!first.isCompleted) first.complete(bytes);
        socket.destroy();
      });
    });
    final task = await connect(server.port);
    final rejected = expectLater(
      task.socket,
      throwsA(isA<HandshakeException>()),
    );
    final packet = await first.future;
    expect(packet.first, 0x16); // TLS handshake record, not G(ET) or P(OST).
    expect(packet[1], 3);
    expect(utf8.decode(packet, allowMalformed: true), isNot(contains('POST ')));
    await rejected;
  });

  test('HTTP connection deadline bounds a stalled TLS handshake', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final started = Completer<void>();
    server.listen((socket) {
      addTearDown(socket.destroy);
      socket.listen((_) {
        if (!started.isCompleted) started.complete();
      });
    });
    await HttpOverrides.runWithHttpOverrides(() async {
      final client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 100);
      addTearDown(() => client.close(force: true));
      client.connectionFactory = (_, _, _) => connect(server.port);
      await expectLater(
        client.getUrl(Uri.https('chat.example.org', '/')),
        throwsA(isA<SocketException>()),
      );
      expect(started.isCompleted, isTrue);
    }, _RealHttp());
  });

  test('unsafe URL or proxy is rejected before DNS/TCP', () async {
    var lookups = 0;
    Future<List<InternetAddress>> lookup(String _) async {
      lookups++;
      return [InternetAddress('8.8.8.8')];
    }

    for (final uri in [
      Uri.http('chat.example.org', '/'),
      Uri.parse('https://chat.example.org:444/'),
      Uri.parse('https://user@chat.example.org/'),
      Uri.https('127.0.0.1', '/'),
    ]) {
      await expectLater(
        publicHttpsConnection(uri, null, null, lookup: lookup),
        throwsFormatException,
      );
    }
    await expectLater(
      publicHttpsConnection(
        Uri.https('chat.example.org', '/'),
        'proxy.example.org',
        8080,
        lookup: lookup,
      ),
      throwsFormatException,
    );
    expect(lookups, 0);
  });

  test('empty or mixed private DNS answers fail before TCP', () async {
    for (final addresses in [
      <InternetAddress>[],
      [InternetAddress('8.8.8.8'), InternetAddress('127.0.0.1')],
    ]) {
      await expectLater(
        publicHttpsConnection(
          Uri.https('chat.example.org', '/'),
          null,
          null,
          lookup: (_) async => addresses,
        ),
        throwsFormatException,
      );
    }
  });
}
