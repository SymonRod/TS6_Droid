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
  String get shareDeviceAudio => 'Share device audio';

  @override
  String get shareDeviceAudioHint =>
      'Music, games and videos reach viewers (not voices or mic). Set before sharing.';

  @override
  String get pttSetting => 'Push-to-talk mode';

  @override
  String get deafen => 'Deafen';

  @override
  String get undeafen => 'Undeafen';

  @override
  String get disconnectConfirm => 'Disconnect from the server?';

  @override
  String get shareScreen => 'Share screen';

  @override
  String get stopShare => 'Stop sharing';

  @override
  String get audioOutput => 'Audio output';

  @override
  String get audioAuto => 'Automatic';

  @override
  String get audioSpeaker => 'Speaker';

  @override
  String get audioEarpiece => 'Earpiece';

  @override
  String get audioDeviceFallback => 'Audio device';

  @override
  String get more => 'More';

  @override
  String get mytsTitle => 'myTeamSpeak';

  @override
  String get mytsEmail => 'Email';

  @override
  String get mytsAccountPassword => 'Account password';

  @override
  String get mytsOtp => 'One-time code';

  @override
  String get mytsOtpHint => 'Your account needs a one-time code.';

  @override
  String get mytsLogin => 'Sign in';

  @override
  String get mytsLogout => 'Sign out';

  @override
  String mytsLoggedInAs(String username) {
    return 'Signed in as $username';
  }

  @override
  String get mytsEmailPasswordRequired => 'Email and password are required';

  @override
  String get mytsErrorCredentials => 'Wrong email or password';

  @override
  String get mytsErrorOffline => 'Login service unavailable, try again later';

  @override
  String get mytsErrorEmailPending =>
      'This email address is awaiting confirmation';

  @override
  String get mytsErrorOtpRequired => 'This account needs a one-time code';

  @override
  String get mytsErrorOtpInvalid => 'Wrong one-time code';

  @override
  String get mytsErrorNetwork => 'Network error, check your connection';

  @override
  String mytsErrorHttp(String status) {
    return 'Login failed (HTTP $status)';
  }

  @override
  String get mytsErrorMalformed => 'Unexpected server reply';

  @override
  String get mytsErrorPaced => 'Wait a few seconds before retrying';

  @override
  String get mytsErrorOther => 'Login failed';

  @override
  String get setupWelcome => 'Welcome to TS6 Droid';

  @override
  String get setupIntro => 'Choose how to set up your TeamSpeak client.';

  @override
  String get setupAccountTitle => 'Your myTeamSpeak account';

  @override
  String get setupAccountHint =>
      'Account setup will automatically import supported cloud identities and server bookmarks, keeping each bookmark linked to its identity. Data saved only on your desktop cannot be restored from the cloud.';

  @override
  String get setupImportPending =>
      'Signing in downloads your identities and bookmarks and keeps them securely on this device. The account is only read; nothing is changed in the cloud.';

  @override
  String get setupSignIn => 'Sign in with myTeamSpeak';

  @override
  String get setupSkip => 'Skip sign-in';

  @override
  String get setupSkipHint =>
      'Create a local identity and use server connections without an account. You can sign in later; your local data will be preserved.';

  @override
  String get setupBack => 'Back to setup';

  @override
  String get setupRetry => 'Retry';

  @override
  String get setupReadError =>
      'Could not safely read your local setup. Your data has not been replaced. Check storage access and try again.';

  @override
  String get setupWriteError =>
      'Could not finish local setup. Try skipping sign-in again; any identity already saved will be reused.';

  @override
  String get mytsImportPendingTitle => 'Import your account data';

  @override
  String get mytsSetupImportPending =>
      'You are signed in, but nothing has been imported yet, so setup is not complete. Enter your account password to download your identities and bookmarks, or return to setup to use a local identity.';

  @override
  String get mytsExistingDataHint =>
      'Signing in never replaces your local identities or bookmarks. Importing only adds what is missing and asks you first.';

  @override
  String get mytsShowPassword => 'Show password';

  @override
  String get mytsHidePassword => 'Hide password';

  @override
  String get mytsImportAction => 'Import account data';

  @override
  String get mytsImportPasswordNote =>
      'The password unlocks your account key for this import only and is not stored.';

  @override
  String get mytsImportWorking => 'Downloading and checking your account data…';

  @override
  String get mytsImportConfirmTitle => 'Add your account data to this device?';

  @override
  String get mytsImportConfirm => 'Import';

  @override
  String get mytsImportContinue => 'Continue';

  @override
  String mytsImportAdded(int identities, int bookmarks) {
    return 'Added $identities identities and $bookmarks bookmarks.';
  }

  @override
  String get mytsImportUpToDate =>
      'Everything from your account is already on this device. Nothing was changed.';

  @override
  String mytsImportSkipped(int count) {
    return 'Skipped $count items that are invalid, duplicated or different from the copy already on this device. Nothing existing was replaced.';
  }

  @override
  String get mytsImportNothing =>
      'Your account has no identities or bookmarks to import. Nothing was changed and setup is not complete; you can go back and skip sign-in to create a local identity.';

  @override
  String get mytsImportChooseIdentityNote =>
      'You will choose which identity each bookmark uses the first time you connect.';

  @override
  String get mytsImportErrNoSession =>
      'You are not signed in. Sign in again to import.';

  @override
  String get mytsImportErrUnlock =>
      'Your account key could not be unlocked. Check the password and sign in again. Nothing was changed on this device.';

  @override
  String get mytsImportErrNetwork =>
      'Network error while downloading. Nothing was changed on this device.';

  @override
  String get mytsImportErrService =>
      'The service did not accept the request. Nothing was changed on this device.';

  @override
  String get mytsImportErrExpired =>
      'Your sign-in expired. Sign out and sign in again. Nothing was changed on this device.';

  @override
  String get mytsImportErrData =>
      'The reply was unexpected or too large. Nothing was changed on this device.';

  @override
  String get mytsImportErrIntegrity =>
      'The downloaded data failed its integrity check. Nothing was changed on this device.';

  @override
  String get mytsImportErrStorage =>
      'Could not read or save local data safely. Nothing existing was replaced.';

  @override
  String get identityChooseTitle => 'Choose an identity';

  @override
  String get identityChooseBody =>
      'Pick the identity to connect with. Your choice is remembered on this device only and does not change your account.';

  @override
  String get identityLocal => 'Local identity of this device';

  @override
  String get identityCreate => 'Create a new local identity';

  @override
  String get identityUnavailable =>
      'The identity could not be opened. Nothing was changed.';

  @override
  String get importedFromAccount => 'From your account';

  @override
  String get identityNotChosen => 'Identity: not chosen yet';

  @override
  String identityChosen(String label) {
    return 'Identity: $label';
  }

  @override
  String get identityChange => 'Change identity';
}
