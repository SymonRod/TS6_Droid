import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'password.dart';
import 'proto.dart';

/// Thin myTeamSpeak `/authentication` client: ProtobufRPC framing
/// (`application/ts3cloud`) exactly as demonstrated against the live
/// endpoint (docs/myteamspeak-login-protocol.md, sections 4-6).
///
/// Rules: a single POST per call, never silently retried; redirects are
/// never followed with credential bodies; TLS failures, HTTP non-200,
/// malformed protobuf, credential rejection and OTP-needed states stay
/// distinguishable. Only metadata (method, status, field presence, lengths)
/// may be logged — never requests, replies or secrets.

const myTsHost = 'clientapi.myteamspeak.com';
const myTsAuthPath = '/authentication';
const myTsContentType = 'application/ts3cloud';

/// The standalone validation used this User-Agent, which also appears in
/// historical forum captures. Whether the server requires it is untested;
/// the app behaves like the desktop client and sends it.
const myTsUserAgent = 'cpp-httplib/0.11.1';

/// `ErrorCommon` numeric values relevant to login (from descriptors).
abstract final class MyTsAppError {
  static const int loginOk = 200;
  static const int loginOffline = 201;
  static const int loginFailed = 202;
  static const int emailPending = 203;
  static const int sessionDeletedOk = 204;
  static const int otpRequired = 208;
  static const int otpInvalid = 209;
}

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

  const MyTsLoginSuccess({
    required this.session,
    required this.uuid,
    required this.username,
  });
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

class MyTsHttpResponse {
  final int status;
  final Uint8List body;

  const MyTsHttpResponse(this.status, this.body);
}

/// Injectable transport for tests: exact URI, headers and framed body in,
/// status plus raw body out. The default implementation uses `dart:io`
/// with redirects disabled.
typedef MyTsPost = Future<MyTsHttpResponse> Function(
  Uri uri,
  Map<String, String> headers,
  Uint8List body,
);

Future<MyTsHttpResponse> _defaultPost(
  Uri uri,
  Map<String, String> headers,
  Uint8List body,
) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.postUrl(uri);
    req.followRedirects = false;
    headers.forEach(req.headers.set);
    req.contentLength = body.length;
    req.add(body);
    final resp = await req.close().timeout(const Duration(seconds: 30));
    final bytes = await consolidateHttpClientResponseBytes(resp);
    return MyTsHttpResponse(resp.statusCode, bytes);
  } finally {
    client.close();
  }
}

class MyTsApi {
  /// Minimum gap between manual login attempts (research/app convention).
  static const minRetryGap = Duration(seconds: 4);

  final MyTsPost _post;
  final String deviceName;

  MyTsApi({MyTsPost? post, this.deviceName = defaultMyTsDeviceName})
      : _post = post ?? _defaultPost;

  Uri get _uri => Uri.https(myTsHost, myTsAuthPath);

  Map<String, String> get _headers => {
        HttpHeaders.contentTypeHeader: myTsContentType,
        HttpHeaders.userAgentHeader: myTsUserAgent,
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
    if (email.isEmpty || password.isEmpty) {
      return MyTsLoginOutcome.fail(MyTsFailure.invalidInput);
    }
    // KDF first, off the calling isolate; only the Base64 value is sent.
    final wire = await myTsWirePasswordAsync(email: email, password: password);
    final body = frameMyTsRpc(
      'login',
      encodeMyTsLoginData(
        email: email,
        wirePassword: wire,
        otp: (otp != null && otp.isNotEmpty) ? otp : null,
        deviceName: deviceName,
      ),
    );
    final MyTsHttpResponse resp;
    try {
      resp = await _post(_uri, _headers, body);
    } on TimeoutException catch (_) {
      return MyTsLoginOutcome.fail(MyTsFailure.network);
    } on SocketException catch (_) {
      return MyTsLoginOutcome.fail(MyTsFailure.network);
    } on HttpException catch (_) {
      return MyTsLoginOutcome.fail(MyTsFailure.network);
    } on TlsException catch (_) {
      return MyTsLoginOutcome.fail(MyTsFailure.network);
    }
    if (resp.status != 200) {
      return MyTsLoginOutcome.fail(MyTsFailure.http, httpStatus: resp.status);
    }
    final MyTsLoginSession reply;
    try {
      reply = decodeMyTsLoginSession(resp.body);
    } on FormatException catch (_) {
      return MyTsLoginOutcome.fail(MyTsFailure.malformed);
    }
    return _classify(reply.error, reply);
  }

  MyTsLoginOutcome _classify(int error, MyTsLoginSession reply) {
    switch (error) {
      case MyTsAppError.loginOk:
        // Success requires all of: HTTP 200, parseable reply, code 200,
        // nonempty session. A default/empty reply is not a session.
        if (reply.session.isEmpty) {
          return MyTsLoginOutcome.fail(MyTsFailure.malformed, appError: error);
        }
        return MyTsLoginOutcome.ok(MyTsLoginSuccess(
          session: reply.session,
          uuid: reply.uuid,
          username: reply.username,
        ));
      case MyTsAppError.loginFailed:
        return MyTsLoginOutcome.fail(MyTsFailure.credentials, appError: error);
      case MyTsAppError.loginOffline:
        return MyTsLoginOutcome.fail(MyTsFailure.offline, appError: error);
      case MyTsAppError.emailPending:
        return MyTsLoginOutcome.fail(MyTsFailure.emailPending, appError: error);
      case MyTsAppError.otpRequired:
        return MyTsLoginOutcome.fail(MyTsFailure.otpRequired, appError: error);
      case MyTsAppError.otpInvalid:
        return MyTsLoginOutcome.fail(MyTsFailure.otpInvalid, appError: error);
      default:
        return MyTsLoginOutcome.fail(MyTsFailure.other, appError: error);
    }
  }

  /// Deletes a session created by [login] (`ERROR_SESSION_DELETED_OK`
  /// is 204, not 200). Used to clean up test sessions and on logout.
  /// Returns true only on confirmed server deletion; transport or
  /// application failures return false and are never thrown.
  Future<bool> deleteSession(String session) async {
    if (session.isEmpty) return false;
    try {
      final resp = await _post(
        _uri,
        _headers,
        frameMyTsRpc('deleteSession', encodeMyTsSession(session)),
      );
      if (resp.status != 200) return false;
      return decodeMyTsLoginStatus(resp.body).error == MyTsAppError.sessionDeletedOk;
    } catch (_) {
      return false;
    }
  }
}
