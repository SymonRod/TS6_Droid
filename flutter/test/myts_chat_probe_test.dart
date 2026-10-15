import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ts6_flutter/src/myts/api.dart';
import 'package:ts6_flutter/src/myts/history.dart';
import 'package:ts6_flutter/src/myts/public_https.dart';
import 'package:ts6_flutter/src/rust/myts.dart' as rs;

class _ProbeHeaders extends Fake implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }
}

class _ProbeResponse extends Fake implements HttpClientResponse {
  final List<int> body;
  @override
  final int statusCode;

  _ProbeResponse(this.statusCode, String body) : body = utf8.encode(body);

  @override
  int get contentLength => body.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

class _ProbeRequest extends Fake implements HttpClientRequest {
  final _ProbeResponse response;
  @override
  final _ProbeHeaders headers = _ProbeHeaders();
  final sent = <int>[];
  bool? redirects;
  _ProbeRequest(this.response);

  @override
  set followRedirects(bool value) => redirects = value;

  @override
  set contentLength(int value) {}

  @override
  void add(List<int> data) => sent.addAll(data);

  @override
  Future<HttpClientResponse> close() async => response;
}

class _ProbeClient extends Fake implements HttpClient {
  final _ProbeRequest request;
  Uri? destination;
  String? agent;
  String? method;
  Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? factory;
  bool forcedClose = false;
  _ProbeClient(int status, String body)
    : request = _ProbeRequest(_ProbeResponse(status, body));

  @override
  set connectionTimeout(Duration? value) {}

  @override
  set userAgent(String? value) => agent = value;

  @override
  set findProxy(String Function(Uri)? value) {}

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri, String?, int?)? value,
  ) => factory = value;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    this.method = method;
    destination = url;
    return request;
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    destination = url;
    return request;
  }

  @override
  void close({bool force = false}) => forcedClose = force;
}

void main() {
  test('default probe uses verified TLS factory and compatible UA', () async {
    final client = _ProbeClient(200, '{"versions":["v1.1"]}');
    final status = await HttpOverrides.runZoned(
      () => checkChatVersions('chat.example.org'),
      createHttpClient: (_) => client,
    );
    expect(status, 200);
    expect(client.agent, 'Go-http-client/1.1');
    expect(client.factory, publicHttpsConnection);
    expect(
      client.destination,
      Uri.https('chat.example.org', '/_matrix/client/versions'),
    );
    expect(client.request.redirects, isFalse);
    expect(client.forcedClose, isTrue);
  });

  for (final status in [301, 400, 503]) {
    test(
      'HTTP $status is retained, never retried or treated as success',
      () async {
        final client = _ProbeClient(status, '<html>error</html>');
        var clients = 0;
        expect(
          await HttpOverrides.runZoned(
            () => checkChatVersions('chat.example.org'),
            createHttpClient: (_) {
              clients++;
              return client;
            },
          ),
          status,
        );
        expect(clients, 1);
        expect(client.forcedClose, isTrue);
      },
    );
  }

  test('HTML and empty versions are not a successful probe', () async {
    for (final body in ['<html>error</html>', '{"versions":[]}']) {
      final client = _ProbeClient(200, body);
      await expectLater(
        HttpOverrides.runZoned(
          () => checkChatVersions('chat.example.org'),
          createHttpClient: (_) => client,
        ),
        throwsFormatException,
      );
      expect(client.forcedClose, isTrue);
    }
  });

  test('probe keeps reply limits and destination validation', () async {
    final client = _ProbeClient(200, 'x' * (64 * 1024 + 1));
    await expectLater(
      HttpOverrides.runZoned(
        () => checkChatVersions('chat.example.org'),
        createHttpClient: (_) => client,
      ),
      throwsA(isA<MyTsResponseRejected>()),
    );
    expect(client.forcedClose, isTrue);
    await expectLater(checkChatVersions('127.0.0.1'), throwsFormatException);
  });

  test('unrelated image GET keeps its default User-Agent', () async {
    final client = _ProbeClient(200, 'image');
    await HttpOverrides.runZoned(
      () => myTsHttpGet(Uri.https('cdn.example.org', '/avatar'), 32),
      createHttpClient: (_) => client,
    );
    expect(client.agent, isNull);
    expect(client.factory, publicHttpsConnection);
  });

  for (final action in ['login', 'rooms']) {
    test('history $action uses the same verified TLS factory', () async {
      final client = _ProbeClient(200, '{}');
      final body = Uint8List.fromList(utf8.encode('synthetic-password-only'));
      await HttpOverrides.runZoned(
        () => matrixHistoryExchange(
          rs.MyTsHistoryRequest(
            host: 'chat.example.org',
            path:
                '/_matrix/client/r0/${action == 'login' ? 'login' : 'joined_rooms'}',
            query: '{}',
            headers: '{"User-Agent":"Go-http-client/1.1"}',
            body: body,
          ),
          action,
          '',
        ),
        createHttpClient: (_) => client,
      );
      expect(client.factory, publicHttpsConnection);
      expect(client.method, action == 'login' ? 'POST' : 'GET');
      expect(client.request.redirects, isFalse);
      expect(client.forcedClose, isTrue);
      expect(client.request.headers.values['User-Agent'], 'Go-http-client/1.1');
      expect(body.every((b) => b == 0), isTrue);
      expect(
        utf8.decode(client.request.sent),
        action == 'login' ? 'synthetic-password-only' : '',
      );
    });
  }
}
