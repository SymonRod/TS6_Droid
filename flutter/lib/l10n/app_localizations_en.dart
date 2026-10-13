// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get serverAddress => 'Server address (host:port)';

  @override
  String get nickname => 'Nickname';

  @override
  String get serverPassword => 'Server password (optional)';

  @override
  String get channelOptional => 'Channel (optional, path with /)';

  @override
  String get connect => 'Connect';

  @override
  String get saveBookmark => 'Save bookmark';

  @override
  String get updateBookmark => 'Update bookmark';

  @override
  String get cancel => 'Cancel';

  @override
  String get reconnectLast => 'Reconnect to last server on start';

  @override
  String get noBookmarks => 'No bookmarks yet';

  @override
  String get errAddrNick => 'Address and nickname are required';

  @override
  String get disconnect => 'Disconnect';

  @override
  String get channels => 'Channels';

  @override
  String get chat => 'Chat';

  @override
  String get tabChannel => 'Channel';

  @override
  String get tabServer => 'Server';

  @override
  String get tabPrivate => 'Private';

  @override
  String get sendTo => 'Send to...';

  @override
  String get messageHint => 'Message';

  @override
  String get mute => 'Mute';

  @override
  String get unmute => 'Unmute';

  @override
  String get pushToTalk => 'Push to talk';

  @override
  String get holdToTalk => 'Hold to talk';

  @override
  String get you => 'you';

  @override
  String get watchShare => 'Watch screen share';

  @override
  String get streamNotReady => 'Stream info not received yet, try again.';

  @override
  String get channelPasswordTitle => 'Channel password';

  @override
  String get password => 'Password';

  @override
  String get join => 'Join';

  @override
  String get leave => 'Leave';

  @override
  String get fit => 'Fit the whole frame';

  @override
  String get fill => 'Fill the screen';

  @override
  String get shareRequesting => 'Waiting for the sharer to accept...';

  @override
  String get shareConnecting => 'Connecting...';

  @override
  String get shareEnded => 'The stream has ended';

  @override
  String get shareTimeout => 'No answer from the sharer';

  @override
  String get shareRefused => 'The sharer refused your request';

  @override
  String get shareIce => 'Could not connect to the stream';

  @override
  String get shareFailed => 'Failed.';

  @override
  String connectedTo(String address) {
    return 'Connected to $address';
  }

  @override
  String get notifMute => 'Mute';

  @override
  String get notifUnmute => 'Unmute';

  @override
  String get pttSetting => 'Push-to-talk mode';

  @override
  String get deafen => 'Deafen';

  @override
  String get undeafen => 'Undeafen';

  @override
  String get disconnectConfirm => 'Disconnect from the server?';
}
