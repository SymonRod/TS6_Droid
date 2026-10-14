import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../rust/myts.dart' as rs;

/// Thin myTeamSpeak `/authentication` client. The password KDF, the
/// ProtobufRPC framing (`application/ts3cloud`) and the reply classification
/// live in the Rust `tslib-myts` crate (via `rust/myts.dart`); this class only
/// performs the HTTPS POST (docs/myteamspeak-login-protocol.md, sections 4-6).
///
/// Rules: a single POST per call, never silently retried; redirects are
/// never followed with credential bodies; TLS failures, HTTP non-200,
/// malformed protobuf, credential rejection and OTP-needed states stay
/// distinguishable. Only metadata (method, status, field presence, lengths)
/// may be logged — never requests, replies or secrets.

/// Why a login did not produce a session. Transport, HTTP, protobuf and
/// application failures are distinct values; never retry wrong-password or
/// OTP failures in a loop.
enum MyTsFailure {
  /// Empty email or password; nothing was sent.
  invalidInput,

  /// A manual attempt started less than [MyTsApi.minRetryGap] ago.
  paced,

  /// TLS, DNS, connection or timeout failure.
  network,

  /// HTTP status != 200. [MyTsLoginOutcome.httpStatus] carries the code.
  /// The body is never parsed as protobuf (it may be an HTML gateway page).
  http,

  /// HTTP 200 body is not a `LoginSession`, or a parsed default/empty
  /// reply. [MyTsLoginOutcome.appError] may hold the application code.
  malformed,

  /// `ERROR_LOGIN_FAILED` (202): credentials rejected.
  credentials,

  /// `ERROR_LOGIN_OFFLINE` (201): login service unavailable.
  offline,

  /// `ERROR_LOGIN_EMAIL_PENDING` (203).
  emailPending,

  /// `ERROR_AUTH_REQUIRES_OTP` (208): ask for an OTP, do not treat as a
  /// wrong password.
  otpRequired,

  /// `ERROR_2FA_OTP_INVALID` (209): OTP rejected.
  otpInvalid,

  /// Any other application error, unknown enum value, or untested 2FA /
  /// recovery / device mode (210+). [MyTsLoginOutcome.appError] has it.
  other,
}

class MyTsLoginSuccess {
  final String session;
  final String uuid;
  final String username;

  /// Wrapped account key (ciphertext), empty when the service sent none.
  final Uint8List wrappedKey;

  MyTsLoginSuccess({
    required this.session,
    required this.uuid,
    required this.username,
    Uint8List? wrappedKey,
  }) : wrappedKey = wrappedKey ?? Uint8List(0);
}

class MyTsLoginOutcome {
  final MyTsLoginSuccess? success;
  final MyTsFailure? failure;

  /// HTTP status when [failure] == [MyTsFailure.http].
  final int? httpStatus;

  /// Raw `ErrorCommon` value when the server answered with one.
  final int? appError;

  const MyTsLoginOutcome._({this.success, this.failure, this.httpStatus, this.appError});

  factory MyTsLoginOutcome.ok(MyTsLoginSuccess s) => MyTsLoginOutcome._(success: s);

  factory MyTsLoginOutcome.fail(MyTsFailure f, {int? httpStatus, int? appError}) =>
      MyTsLoginOutcome._(failure: f, httpStatus: httpStatus, appError: appError);

  bool get isOk => success != null;
}

/// Why an account pull produced no batch. Transport, service, protocol and
/// integrity failures stay distinguishable; none of them carries payload data.
enum MyTsPullKind {
  /// No usable session; nothing was sent.
  invalidInput,

  /// TLS, DNS, connection or timeout failure.
  network,

  /// The reply exceeded the receive cap or a decoder limit.
  tooLarge,

  /// HTTP status != 200.
  http,

  /// The service no longer accepts the session: sign in again.
  sessionExpired,

  /// Any other service status.
  server,

  /// Malformed or inconsistent reply.
  invalid,

  /// An item failed decryption or its integrity check.
  integrity,
}

class MyTsPullResult {
  final rs.MyTsImportBatch? batch;
  final MyTsPullKind? failure;
  final int? httpStatus;
  final int? serverStatus;

  const MyTsPullResult.ok(rs.MyTsImportBatch this.batch)
      : failure = null,
        httpStatus = null,
        serverStatus = null;

  const MyTsPullResult.fail(MyTsPullKind this.failure, {this.httpStatus, this.serverStatus})
      : batch = null;
}

class MyTsHttpResponse {
  final int status;
  final Uint8List body;

  const MyTsHttpResponse(this.status, this.body);
}

/// A reply exceeded the receive cap (checked against the declared length and
/// again while streaming) or used a content encoding. The rest of the body is
/// never read.
class MyTsResponseRejected implements Exception {
  const MyTsResponseRejected();
}

/// Injectable transport for tests: exact URI, headers and framed body in,
/// status plus raw body out. [maxBytes] is the receive cap the transport must
/// enforce while the reply streams in. The default implementation uses
/// `dart:io` with verified TLS, redirects disabled, no compression and an
/// overall deadline.
typedef MyTsPost = Future<MyTsHttpResponse> Function(
  Uri uri,
  Map<String, String> headers,
  Uint8List body,
  int maxBytes,
);

const _connectTimeout = Duration(seconds: 15);
const _requestDeadline = Duration(seconds: 45);

Future<MyTsHttpResponse> _defaultPost(
  Uri uri,
  Map<String, String> headers,
  Uint8List body,
  int maxBytes,
) => myTsHttpPost(uri, headers, body, maxBytes);

/// The production transport (public so tests can aim it at a loopback server).
Future<MyTsHttpResponse> myTsHttpPost(
  Uri uri,
  Map<String, String> headers,
  Uint8List body,
  int maxBytes, {
  Duration deadline = _requestDeadline,
}) async {
  // Normal certificate and hostname verification: no badCertificateCallback.
  // Compression is off so a small reply cannot expand past the cap.
  final client = HttpClient()
    ..connectionTimeout = _connectTimeout
    ..autoUncompress = false;
  try {
    return await _exchange(client, uri, headers, body, maxBytes).timeout(
      deadline,
      onTimeout: () => throw TimeoutException('myTS request deadline'),
    );
  } finally {
    // Also aborts a still-streaming body after a timeout or cap violation.
    client.close(force: true);
  }
}

Future<MyTsHttpResponse> _exchange(
  HttpClient client,
  Uri uri,
  Map<String, String> headers,
  Uint8List body,
  int maxBytes,
) async {
  final req = await client.postUrl(uri);
  req.followRedirects = false;
  headers.forEach(req.headers.set);
  req.contentLength = body.length;
  req.add(body);
  final resp = await req.close();
  // A non-200 body is never parsed (it may be an HTML gateway page), so it is
  // not read either; a redirect is reported as the HTTP failure it is.
  if (resp.statusCode != HttpStatus.ok) {
    return MyTsHttpResponse(resp.statusCode, Uint8List(0));
  }
  final encoding = resp.headers.value(HttpHeaders.contentEncodingHeader);
  if (encoding != null && encoding.toLowerCase() != 'identity') {
    throw const MyTsResponseRejected();
  }
  if (resp.contentLength > maxBytes) throw const MyTsResponseRejected();
  final out = BytesBuilder(copy: false);
  await for (final chunk in resp) {
    if (out.length + chunk.length > maxBytes) {
      throw const MyTsResponseRejected();
    }
    out.add(chunk);
  }
  return MyTsHttpResponse(resp.statusCode, out.takeBytes());
}

class MyTsApi {
  /// Minimum gap between manual login attempts (research/app convention).
  static const minRetryGap = Duration(seconds: 4);

  final MyTsPost _post;

  /// `null` means the library default.
  final String? deviceName;

  MyTsApi({MyTsPost? post, this.deviceName}) : _post = post ?? _defaultPost;

  late final rs.MyTsEndpoint _endpoint = rs.myTsEndpoint();

  Uri get _uri => Uri.https(_endpoint.host, _endpoint.authPath);
  Uri get _syncUri => Uri.https(_endpoint.host, _endpoint.syncPath);

  Map<String, String> get _headers => {
        HttpHeaders.contentTypeHeader: _endpoint.contentType,
        HttpHeaders.userAgentHeader: _endpoint.userAgent,
      };

  /// One password-login attempt, no retries. [email] must already be the
  /// trimmed address the UI also sends as the KDF input (the API never
  /// trims or normalizes; the password is always used byte-for-byte).
  /// [otp] is only sent for the explicit second step after [MyTsFailure.otpRequired].
  Future<MyTsLoginOutcome> login({
    required String email,
    required String password,
    String? otp,
  }) async {
    // The KDF runs in Rust on the FRB worker pool; only its Base64 output
    // is placed in the request.
    final body = await rs.myTsBuildLogin(
      email: email,
      password: password,
      otp: (otp != null && otp.isNotEmpty) ? otp : null,
      deviceName: deviceName ?? _endpoint.defaultDeviceName,
    );
    if (body == null) {
      return MyTsLoginOutcome.fail(MyTsFailure.invalidInput);
    }
    final MyTsHttpResponse resp;
    try {
      resp = await _post(_uri, _headers, body, _endpoint.loginReplyLimit);
    } on MyTsResponseRejected {
      return MyTsLoginOutcome.fail(MyTsFailure.malformed);
    } on TimeoutException catch (_) {
      return MyTsLoginOutcome.fail(MyTsFailure.network);
    } on SocketException catch (_) {
      return MyTsLoginOutcome.fail(MyTsFailure.network);
    } on HttpException catch (_) {
      return MyTsLoginOutcome.fail(MyTsFailure.network);
    } on TlsException catch (_) {
      return MyTsLoginOutcome.fail(MyTsFailure.network);
    }
    final parsed = rs.myTsParseLogin(httpStatus: resp.status, body: resp.body);
    final ok = parsed.success;
    if (ok != null) {
      return MyTsLoginOutcome.ok(MyTsLoginSuccess(
        session: ok.session,
        uuid: ok.uuid,
        username: ok.username,
        wrappedKey: Uint8List.fromList(ok.wrappedKey),
      ));
    }
    return MyTsLoginOutcome.fail(
      _failure(parsed.failure),
      httpStatus: parsed.httpStatus,
      appError: parsed.appError,
    );
  }

  static MyTsFailure _failure(rs.MyTsLoginFailure? f) => switch (f) {
        rs.MyTsLoginFailure.http => MyTsFailure.http,
        rs.MyTsLoginFailure.malformed || null => MyTsFailure.malformed,
        rs.MyTsLoginFailure.credentials => MyTsFailure.credentials,
        rs.MyTsLoginFailure.offline => MyTsFailure.offline,
        rs.MyTsLoginFailure.emailPending => MyTsFailure.emailPending,
        rs.MyTsLoginFailure.otpRequired => MyTsFailure.otpRequired,
        rs.MyTsLoginFailure.otpInvalid => MyTsFailure.otpInvalid,
        rs.MyTsLoginFailure.other => MyTsFailure.other,
      };

  /// Deletes a session created by [login] (`ERROR_SESSION_DELETED_OK`
  /// is 204, not 200). Used to clean up test sessions and on logout.
  /// Returns true only on confirmed server deletion; transport or
  /// application failures return false and are never thrown.
  Future<bool> deleteSession(String session) async {
    final body = rs.myTsBuildDeleteSession(session: session);
    if (body == null) return false;
    try {
      final resp = await _post(_uri, _headers, body, _endpoint.loginReplyLimit);
      return rs.myTsParseDeleteSession(httpStatus: resp.status, body: resp.body);
    } catch (_) {
      return false;
    }
  }

  /// Runs the account-key KDF and authenticates the wrapped key. Returns null
  /// for an absent, altered or unsupported key (fail closed, no fallback).
  /// The returned handle must be released with `dispose()`.
  Future<rs.MyTsAccountKey?> unlockAccountKey({
    required String email,
    required String password,
    required List<int> wrappedKey,
  }) async {
    if (email.isEmpty || password.isEmpty || wrappedKey.isEmpty) return null;
    try {
      return await rs.myTsUnlockAccountKey(
        email: email,
        password: password,
        wrappedKey: wrappedKey,
      );
    } catch (_) {
      return null; // Never surface native error text near key material.
    }
  }

  /// One read-only `requestServerItems` POST, never retried. The reply is
  /// decrypted and validated atomically in Rust: a batch or a failure.
  Future<MyTsPullResult> pull({
    required String session,
    required rs.MyTsAccountKey key,
  }) async {
    final request = rs.myTsBuildInitialPull(session: session);
    if (request == null) return const MyTsPullResult.fail(MyTsPullKind.invalidInput);
    final MyTsHttpResponse resp;
    try {
      resp = await _post(_syncUri, _headers, request, _endpoint.pullReplyLimit);
    } on MyTsResponseRejected {
      return const MyTsPullResult.fail(MyTsPullKind.tooLarge);
    } on TimeoutException catch (_) {
      return const MyTsPullResult.fail(MyTsPullKind.network);
    } on SocketException catch (_) {
      return const MyTsPullResult.fail(MyTsPullKind.network);
    } on HttpException catch (_) {
      return const MyTsPullResult.fail(MyTsPullKind.network);
    } on TlsException catch (_) {
      return const MyTsPullResult.fail(MyTsPullKind.network);
    }
    final parsed = await rs.myTsParsePull(
      key: key,
      httpStatus: resp.status,
      body: resp.body,
    );
    final batch = parsed.batch;
    if (batch != null) return MyTsPullResult.ok(batch);
    return MyTsPullResult.fail(
      switch (parsed.failure) {
        rs.MyTsPullFailure.http => MyTsPullKind.http,
        rs.MyTsPullFailure.sessionExpired => MyTsPullKind.sessionExpired,
        rs.MyTsPullFailure.server => MyTsPullKind.server,
        rs.MyTsPullFailure.limit => MyTsPullKind.tooLarge,
        rs.MyTsPullFailure.integrity => MyTsPullKind.integrity,
        rs.MyTsPullFailure.invalid || null => MyTsPullKind.invalid,
      },
      httpStatus: parsed.httpStatus,
      serverStatus: parsed.serverStatus,
    );
  }
}
