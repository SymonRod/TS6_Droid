class ServerBookmark {
  final String name;
  final String address;
  final String nickname;
  final String? password;
  final String? channel;
  final String? serverName;
  final int iconId;

  const ServerBookmark({
    this.name = '',
    required this.address,
    this.nickname = '',
    this.password,
    this.channel,
    this.serverName,
    this.iconId = 0,
  });

  // Same JSON shape as the Kotlin app's bookmarks, so an export/import is easy later.
  factory ServerBookmark.fromJson(Map<String, dynamic> j) {
    String? s(dynamic v) => (v == null || v == 'null') ? null : v.toString();
    return ServerBookmark(
      name: s(j['name']) ?? '',
      address: s(j['address']) ?? '',
      nickname: s(j['nickname']) ?? '',
      password: s(j['password']),
      channel: s(j['channel']),
      serverName: s(j['serverName']),
      iconId: int.tryParse('${j['iconId']}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'nickname': nickname,
        if (password != null) 'password': password,
        if (channel != null) 'channel': channel,
        if (serverName != null) 'serverName': serverName,
        'iconId': iconId,
      };
}
