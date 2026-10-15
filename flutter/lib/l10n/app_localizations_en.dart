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
  String get newServer => 'New server';

  @override
  String get editServer => 'Edit server';

  @override
  String get savedServers => 'Saved servers';

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
      'The password unlocks your account key for this import.';

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

  @override
  String get chatOpen => 'Account chat';

  @override
  String get chatTitle => 'Chat';

  @override
  String get chatTabChats => 'Chats';

  @override
  String get chatTabContacts => 'Contacts';

  @override
  String get chatTabProfile => 'Profile';

  @override
  String get chatSignInRequired =>
      'Sign in to myTeamSpeak to use account chat.';

  @override
  String get chatSignIn => 'Sign in';

  @override
  String get chatUnlockTitle => 'Unlock your chat';

  @override
  String get chatUnlockBody =>
      'Your conversations and keys are stored encrypted on this device. Enter your myTeamSpeak password to unlock them.';

  @override
  String get chatUnlock => 'Unlock';

  @override
  String get homeChatSignedIn => 'Conversations and contacts';

  @override
  String get homeChatSignedOut =>
      'Sign in with myTeamSpeak to chat with your contacts';

  @override
  String get mytsRememberPassword => 'Remember password on this device';

  @override
  String get mytsRememberPasswordHint =>
      'Kept in the device\'s secure storage so you aren\'t asked each time. Turn off for maximum security.';

  @override
  String get mytsImportUsingSaved =>
      'The password saved on this device will be used.';

  @override
  String get chatUnlockSavedBody =>
      'Unlocking with the password saved on this device.';

  @override
  String get chatUnlockManual => 'Enter password manually';

  @override
  String get chatErrSavedPasswordRejected =>
      'The saved password no longer works. Enter it again.';

  @override
  String get chatAdvanced => 'Advanced';

  @override
  String get chatAllowOwnEmpty =>
      'Also read my own older messages whose key backup has no sender information (the sender identity can\'t be verified)';

  @override
  String get chatConnecting => 'Connecting…';

  @override
  String get chatErrWrongPassword =>
      'Wrong password, or the account key couldn\'t be unlocked.';

  @override
  String get chatErrNetwork =>
      'Can\'t reach the chat server. Saved conversations are still available.';

  @override
  String get chatErrAuth =>
      'The chat server rejected the saved chat login. To avoid creating duplicate devices, it is not retried automatically.';

  @override
  String get chatErrRateLimited => 'Too many requests. Please wait a moment.';

  @override
  String chatErrServer(String status) {
    return 'The chat server returned an error (HTTP $status).';
  }

  @override
  String get chatErrInvalid => 'Unexpected response from the chat server.';

  @override
  String get chatErrLoginUncertain =>
      'An earlier chat login on this device didn\'t finish cleanly. Tap retry: the same chat device is reused, no duplicate is created.';

  @override
  String get chatErrNotSendable =>
      'This message can\'t be sent in this conversation.';

  @override
  String get chatErrContacts => 'Couldn\'t update your contacts.';

  @override
  String get chatRefresh => 'Refresh';

  @override
  String get chatNoChats =>
      'No conversations yet. Start one from your contacts.';

  @override
  String get chatNewChat => 'New chat';

  @override
  String get chatInvites => 'Invitations';

  @override
  String chatInvitedBy(Object name) {
    return '$name invited you';
  }

  @override
  String get chatAccept => 'Accept';

  @override
  String get chatDecline => 'Decline';

  @override
  String get chatYou => 'You';

  @override
  String get chatLastEncrypted => 'Encrypted message';

  @override
  String get chatLastUnavailable => 'Message unavailable';

  @override
  String get chatLastDeleted => 'Message deleted';

  @override
  String get chatEncryptedRoom => 'End-to-end encrypted';

  @override
  String get chatPlainRoom => 'Not encrypted';

  @override
  String get chatSendDisabledEncrypted =>
      'Sending is only available in one-to-one encrypted conversations for now. You can read messages here and reply from the desktop app.';

  @override
  String get chatSendDisabledLoading =>
      'Conversation details are still loading…';

  @override
  String get chatMessageHint => 'Message';

  @override
  String get chatSend => 'Send';

  @override
  String get chatNotSent => 'Not sent · tap to retry';

  @override
  String get chatDiscard => 'Discard';

  @override
  String get chatMissingKey => 'Encrypted message · key not available';

  @override
  String get chatPartial => 'Older than the available key';

  @override
  String get chatDeleted => 'Message deleted';

  @override
  String get chatInvalidMessage => 'Message couldn\'t be verified';

  @override
  String get chatOlder => 'Load older messages';

  @override
  String get chatEmptyConversation => 'No messages yet. Say hello!';

  @override
  String get chatCopy => 'Copy';

  @override
  String get chatCopied => 'Copied';

  @override
  String get chatLeave => 'Leave conversation';

  @override
  String get chatLeaveConfirm =>
      'Leave this conversation? It will disappear from your list.';

  @override
  String get chatToday => 'Today';

  @override
  String get chatYesterday => 'Yesterday';

  @override
  String chatFile(String name) {
    return 'File: $name';
  }

  @override
  String chatImage(String name) {
    return 'Photo: $name';
  }

  @override
  String get chatStatusAvailable => 'Available';

  @override
  String get chatStatusAway => 'Away';

  @override
  String get chatStatusDnd => 'Do not disturb';

  @override
  String get chatStatusOffline => 'Offline';

  @override
  String get chatStatusInvisible => 'Appear offline';

  @override
  String get chatContactsEmpty => 'No contacts yet.';

  @override
  String get chatAddContact => 'Add contact';

  @override
  String get chatEditContact => 'Edit contact';

  @override
  String get chatContactId => 'Chat ID (@user:server)';

  @override
  String get chatContactNote => 'Name or note';

  @override
  String get chatSave => 'Save';

  @override
  String get chatRemove => 'Remove';

  @override
  String chatRemoveConfirm(String name) {
    return 'Remove $name from your contacts?';
  }

  @override
  String get chatStartChat => 'Start chat';

  @override
  String get chatStartPlainTitle => 'Start an unencrypted chat?';

  @override
  String get chatStartPlainBody =>
      'New conversations started here are not end-to-end encrypted: the chat server can read them. For private topics, start the conversation from the desktop app.';

  @override
  String get chatStart => 'Start';

  @override
  String get chatProfileName => 'Display name';

  @override
  String get chatProfileId => 'Chat ID';

  @override
  String get chatProfileStatus => 'Status';

  @override
  String get chatProfileStatusMessage => 'Status message';

  @override
  String get chatProfileStatusHint => 'What are you up to?';

  @override
  String get chatProfileSaved => 'Saved';

  @override
  String get chatProfileAvatarTitle => 'Profile picture';

  @override
  String get chatProfileAvatarNote =>
      'Changing your picture isn\'t available in TS6 Droid yet. A picture set in the desktop app shows up here.';

  @override
  String get chatLock => 'Lock chat';

  @override
  String get chatLockHint =>
      'Forgets the unlocked key. Saved conversations stay encrypted on this device.';

  @override
  String get chatSecurityNote =>
      'Encrypted messages are read with keys restored from your myTeamSpeak account, and the ones you send use keys of this phone\'s own chat device. This app does not verify the devices of the people you talk to.';

  @override
  String get chatSearch => 'Search';

  @override
  String get chatErrNotLoggedIn =>
      'The chat login hasn\'t completed on this device yet, so nothing can be sent or loaded.';

  @override
  String get chatRetryLogin => 'Retry chat login';

  @override
  String get chatEncryptConsentTitle =>
      'Send encrypted messages from this phone?';

  @override
  String get chatEncryptConsentBody =>
      'To send end-to-end encrypted messages, TS6 Droid publishes this phone\'s encryption keys to your myTeamSpeak chat account. It shows up as a new device named “TS6 Droid” in the device list of the desktop app, for you and for your contacts.\n\nRoom keys are shared with every device of the people in the conversation, including devices that haven\'t been verified. This app can\'t verify devices yet.';

  @override
  String get chatEncryptConsentContinue => 'Continue';

  @override
  String get chatErrNoRecipients =>
      'The message wasn\'t sent: none of this contact\'s devices is available to receive encryption keys. They may need to open their chat app first.';

  @override
  String get chatErrUnsupportedRoom =>
      'Messages can\'t be sent in this conversation yet.';

  @override
  String get chatErrLimit =>
      'This phone can\'t hold more encryption sessions, so the message wasn\'t sent.';

  @override
  String get chatNoticeDeviceChanged =>
      'One of this contact\'s devices changed its encryption keys unexpectedly. It was left out and can\'t read new messages.';

  @override
  String get chatContactAdded => 'Contact added';

  @override
  String get mytsResetTitle => 'Start from scratch?';

  @override
  String get mytsResetBody =>
      'Signing in deletes everything this phone keeps about myTeamSpeak and starts over: the saved session and password, imported identities and bookmarks, chat keys and cache, cached contacts and saved server bookmarks. Your local TeamSpeak identity file and the app settings stay. You\'ll have to import your account again, and the chat will ask again to publish this phone\'s encryption keys. This can\'t be undone.';

  @override
  String get mytsResetConfirm => 'Delete and sign in';
}
