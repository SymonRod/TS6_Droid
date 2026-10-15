import 'dart:io';

/// Resolve once, pin the checked address, and complete TLS before HttpClient
/// receives a socket. A custom connectionFactory must perform TLS itself.
Future<ConnectionTask<Socket>> publicHttpsConnection(
  Uri destination,
  String? proxyHost,
  int? proxyPort, {
  // Injectable for isolated DNS policy tests; production uses system DNS.
  Future<List<InternetAddress>> Function(String)? lookup,
}) async {
  if (proxyHost != null ||
      proxyPort != null ||
      destination.scheme != 'https' ||
      destination.userInfo.isNotEmpty ||
      destination.port != 443 ||
      !safePublicHttpsHost(destination.host)) {
    throw const FormatException('invalid HTTPS destination');
  }
  final addresses = await (lookup ?? InternetAddress.lookup)(destination.host);
  if (addresses.isEmpty || addresses.any((ip) => !isPublicAddress(ip))) {
    throw const FormatException('non-public destination');
  }
  // lookup() keeps the queried hostname in InternetAddress.host: dart:io uses
  // it for SNI/certificate validation, and its numeric address for the TCP peer.
  // Preserve that object rather than re-resolving the host or rebuilding an IP.
  return verifiedTlsConnection(addresses.first, destination.port);
}

/// Native TLS task, shared by production and real-socket tests.
/// Production always uses default platform trust; only isolated tests pass context.
Future<ConnectionTask<SecureSocket>> verifiedTlsConnection(
  InternetAddress address,
  int port, {
  SecurityContext? context,
}) => SecureSocket.startConnect(address, port, context: context);

/// Reject IP literals, local names, ports, credentials and ambiguous hostnames.
bool safePublicHttpsHost(String host) {
  if (host.length > 253 ||
      host.isEmpty ||
      host.endsWith('.') ||
      !host.contains('.')) {
    return false;
  }
  if (InternetAddress.tryParse(host) != null) return false;
  return host
          .split('.')
          .every(
            (part) =>
                part.isNotEmpty &&
                part.length <= 63 &&
                RegExp(
                  r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$',
                ).hasMatch(part),
          ) &&
      !host.toLowerCase().endsWith('.local') &&
      !host.toLowerCase().endsWith('.internal') &&
      !host.toLowerCase().endsWith('.localhost') &&
      !host.toLowerCase().endsWith('.test') &&
      !host.toLowerCase().endsWith('.invalid');
}

bool isPublicAddress(InternetAddress ip) {
  final b = ip.rawAddress;
  if (ip.type == InternetAddressType.IPv6) {
    // Global unicast only; exclude IPv4-mapped and documentation addresses.
    return b.length == 16 &&
        b[0] >= 0x20 &&
        b[0] <= 0x3f &&
        !(b[0] == 0x20 && b[1] == 0x01 && b[2] == 0x0d && b[3] == 0xb8);
  }
  if (b.length != 4) return false;
  return b[0] > 0 &&
      b[0] < 224 &&
      b[0] != 10 &&
      b[0] != 127 &&
      !(b[0] == 100 && b[1] >= 64 && b[1] <= 127) &&
      !(b[0] == 169 && b[1] == 254) &&
      !(b[0] == 172 && b[1] >= 16 && b[1] <= 31) &&
      !(b[0] == 192 && (b[1] == 0 || b[1] == 168)) &&
      !(b[0] == 198 && (b[1] == 18 || b[1] == 19)) &&
      !(b[0] == 192 && b[1] == 0 && b[2] == 2) &&
      !(b[0] == 198 && b[1] == 51 && b[2] == 100) &&
      !(b[0] == 203 && b[1] == 0 && b[2] == 113);
}
