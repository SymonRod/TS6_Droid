import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
    Locale('it'),
  ];

  /// No description provided for @serverAddress.
  ///
  /// In en, this message translates to:
  /// **'Server address (host:port)'**
  String get serverAddress;

  /// No description provided for @nickname.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nickname;

  /// No description provided for @serverPassword.
  ///
  /// In en, this message translates to:
  /// **'Server password (optional)'**
  String get serverPassword;

  /// No description provided for @channelOptional.
  ///
  /// In en, this message translates to:
  /// **'Channel (optional, path with /)'**
  String get channelOptional;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @saveBookmark.
  ///
  /// In en, this message translates to:
  /// **'Save bookmark'**
  String get saveBookmark;

  /// No description provided for @updateBookmark.
  ///
  /// In en, this message translates to:
  /// **'Update bookmark'**
  String get updateBookmark;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @reconnectLast.
  ///
  /// In en, this message translates to:
  /// **'Reconnect to last server on start'**
  String get reconnectLast;

  /// No description provided for @noBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks yet'**
  String get noBookmarks;

  /// No description provided for @newServer.
  ///
  /// In en, this message translates to:
  /// **'New server'**
  String get newServer;

  /// No description provided for @editServer.
  ///
  /// In en, this message translates to:
  /// **'Edit server'**
  String get editServer;

  /// No description provided for @savedServers.
  ///
  /// In en, this message translates to:
  /// **'Saved servers'**
  String get savedServers;

  /// No description provided for @errAddrNick.
  ///
  /// In en, this message translates to:
  /// **'Address and nickname are required'**
  String get errAddrNick;

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get channels;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @tabChannel.
  ///
  /// In en, this message translates to:
  /// **'Channel'**
  String get tabChannel;

  /// No description provided for @tabServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get tabServer;

  /// No description provided for @tabPrivate.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get tabPrivate;

  /// No description provided for @sendTo.
  ///
  /// In en, this message translates to:
  /// **'Send to...'**
  String get sendTo;

  /// No description provided for @messageHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get messageHint;

  /// No description provided for @mute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get mute;

  /// No description provided for @unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get unmute;

  /// No description provided for @pushToTalk.
  ///
  /// In en, this message translates to:
  /// **'Push to talk'**
  String get pushToTalk;

  /// No description provided for @holdToTalk.
  ///
  /// In en, this message translates to:
  /// **'Hold to talk'**
  String get holdToTalk;

  /// No description provided for @you.
  ///
  /// In en, this message translates to:
  /// **'you'**
  String get you;

  /// No description provided for @watchShare.
  ///
  /// In en, this message translates to:
  /// **'Watch screen share'**
  String get watchShare;

  /// No description provided for @streamNotReady.
  ///
  /// In en, this message translates to:
  /// **'Stream info not received yet, try again.'**
  String get streamNotReady;

  /// No description provided for @channelPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Channel password'**
  String get channelPasswordTitle;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @fit.
  ///
  /// In en, this message translates to:
  /// **'Fit the whole frame'**
  String get fit;

  /// No description provided for @fill.
  ///
  /// In en, this message translates to:
  /// **'Fill the screen'**
  String get fill;

  /// No description provided for @shareRequesting.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the sharer to accept...'**
  String get shareRequesting;

  /// No description provided for @shareConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting...'**
  String get shareConnecting;

  /// No description provided for @shareEnded.
  ///
  /// In en, this message translates to:
  /// **'The stream has ended'**
  String get shareEnded;

  /// No description provided for @shareTimeout.
  ///
  /// In en, this message translates to:
  /// **'No answer from the sharer'**
  String get shareTimeout;

  /// No description provided for @shareRefused.
  ///
  /// In en, this message translates to:
  /// **'The sharer refused your request'**
  String get shareRefused;

  /// No description provided for @shareIce.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the stream'**
  String get shareIce;

  /// No description provided for @shareFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed.'**
  String get shareFailed;

  /// No description provided for @connectedTo.
  ///
  /// In en, this message translates to:
  /// **'Connected to {address}'**
  String connectedTo(String address);

  /// No description provided for @notifMute.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get notifMute;

  /// No description provided for @notifUnmute.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get notifUnmute;

  /// No description provided for @shareDeviceAudio.
  ///
  /// In en, this message translates to:
  /// **'Share device audio'**
  String get shareDeviceAudio;

  /// No description provided for @shareDeviceAudioHint.
  ///
  /// In en, this message translates to:
  /// **'Music, games and videos reach viewers (not voices or mic). Set before sharing.'**
  String get shareDeviceAudioHint;

  /// No description provided for @pttSetting.
  ///
  /// In en, this message translates to:
  /// **'Push-to-talk mode'**
  String get pttSetting;

  /// No description provided for @deafen.
  ///
  /// In en, this message translates to:
  /// **'Deafen'**
  String get deafen;

  /// No description provided for @undeafen.
  ///
  /// In en, this message translates to:
  /// **'Undeafen'**
  String get undeafen;

  /// No description provided for @disconnectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Disconnect from the server?'**
  String get disconnectConfirm;

  /// No description provided for @shareScreen.
  ///
  /// In en, this message translates to:
  /// **'Share screen'**
  String get shareScreen;

  /// No description provided for @stopShare.
  ///
  /// In en, this message translates to:
  /// **'Stop sharing'**
  String get stopShare;

  /// No description provided for @audioOutput.
  ///
  /// In en, this message translates to:
  /// **'Audio output'**
  String get audioOutput;

  /// No description provided for @audioAuto.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get audioAuto;

  /// No description provided for @audioSpeaker.
  ///
  /// In en, this message translates to:
  /// **'Speaker'**
  String get audioSpeaker;

  /// No description provided for @audioEarpiece.
  ///
  /// In en, this message translates to:
  /// **'Earpiece'**
  String get audioEarpiece;

  /// No description provided for @audioDeviceFallback.
  ///
  /// In en, this message translates to:
  /// **'Audio device'**
  String get audioDeviceFallback;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @mytsTitle.
  ///
  /// In en, this message translates to:
  /// **'myTeamSpeak'**
  String get mytsTitle;

  /// No description provided for @mytsEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get mytsEmail;

  /// No description provided for @mytsAccountPassword.
  ///
  /// In en, this message translates to:
  /// **'Account password'**
  String get mytsAccountPassword;

  /// No description provided for @mytsOtp.
  ///
  /// In en, this message translates to:
  /// **'One-time code'**
  String get mytsOtp;

  /// No description provided for @mytsOtpHint.
  ///
  /// In en, this message translates to:
  /// **'Your account needs a one-time code.'**
  String get mytsOtpHint;

  /// No description provided for @mytsLogin.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get mytsLogin;

  /// No description provided for @mytsLogout.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get mytsLogout;

  /// No description provided for @mytsLoggedInAs.
  ///
  /// In en, this message translates to:
  /// **'Signed in as {username}'**
  String mytsLoggedInAs(String username);

  /// No description provided for @mytsEmailPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Email and password are required'**
  String get mytsEmailPasswordRequired;

  /// No description provided for @mytsErrorCredentials.
  ///
  /// In en, this message translates to:
  /// **'Wrong email or password'**
  String get mytsErrorCredentials;

  /// No description provided for @mytsErrorOffline.
  ///
  /// In en, this message translates to:
  /// **'Login service unavailable, try again later'**
  String get mytsErrorOffline;

  /// No description provided for @mytsErrorEmailPending.
  ///
  /// In en, this message translates to:
  /// **'This email address is awaiting confirmation'**
  String get mytsErrorEmailPending;

  /// No description provided for @mytsErrorOtpRequired.
  ///
  /// In en, this message translates to:
  /// **'This account needs a one-time code'**
  String get mytsErrorOtpRequired;

  /// No description provided for @mytsErrorOtpInvalid.
  ///
  /// In en, this message translates to:
  /// **'Wrong one-time code'**
  String get mytsErrorOtpInvalid;

  /// No description provided for @mytsErrorNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error, check your connection'**
  String get mytsErrorNetwork;

  /// No description provided for @mytsErrorHttp.
  ///
  /// In en, this message translates to:
  /// **'Login failed (HTTP {status})'**
  String mytsErrorHttp(String status);

  /// No description provided for @mytsErrorMalformed.
  ///
  /// In en, this message translates to:
  /// **'Unexpected server reply'**
  String get mytsErrorMalformed;

  /// No description provided for @mytsErrorPaced.
  ///
  /// In en, this message translates to:
  /// **'Wait a few seconds before retrying'**
  String get mytsErrorPaced;

  /// No description provided for @mytsErrorOther.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get mytsErrorOther;

  /// No description provided for @setupWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to TS6 Droid'**
  String get setupWelcome;

  /// No description provided for @setupIntro.
  ///
  /// In en, this message translates to:
  /// **'Choose how to set up your TeamSpeak client.'**
  String get setupIntro;

  /// No description provided for @setupAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Your myTeamSpeak account'**
  String get setupAccountTitle;

  /// No description provided for @setupAccountHint.
  ///
  /// In en, this message translates to:
  /// **'Account setup will automatically import supported cloud identities and server bookmarks, keeping each bookmark linked to its identity. Data saved only on your desktop cannot be restored from the cloud.'**
  String get setupAccountHint;

  /// No description provided for @setupImportPending.
  ///
  /// In en, this message translates to:
  /// **'Signing in downloads your identities and bookmarks and keeps them securely on this device. The account is only read; nothing is changed in the cloud.'**
  String get setupImportPending;

  /// No description provided for @setupSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in with myTeamSpeak'**
  String get setupSignIn;

  /// No description provided for @setupSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip sign-in'**
  String get setupSkip;

  /// No description provided for @setupSkipHint.
  ///
  /// In en, this message translates to:
  /// **'Create a local identity and use server connections without an account. You can sign in later; your local data will be preserved.'**
  String get setupSkipHint;

  /// No description provided for @setupBack.
  ///
  /// In en, this message translates to:
  /// **'Back to setup'**
  String get setupBack;

  /// No description provided for @setupRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get setupRetry;

  /// No description provided for @setupReadError.
  ///
  /// In en, this message translates to:
  /// **'Could not safely read your local setup. Your data has not been replaced. Check storage access and try again.'**
  String get setupReadError;

  /// No description provided for @setupWriteError.
  ///
  /// In en, this message translates to:
  /// **'Could not finish local setup. Try skipping sign-in again; any identity already saved will be reused.'**
  String get setupWriteError;

  /// No description provided for @mytsImportPendingTitle.
  ///
  /// In en, this message translates to:
  /// **'Import your account data'**
  String get mytsImportPendingTitle;

  /// No description provided for @mytsSetupImportPending.
  ///
  /// In en, this message translates to:
  /// **'You are signed in, but nothing has been imported yet, so setup is not complete. Enter your account password to download your identities and bookmarks, or return to setup to use a local identity.'**
  String get mytsSetupImportPending;

  /// No description provided for @mytsExistingDataHint.
  ///
  /// In en, this message translates to:
  /// **'Signing in never replaces your local identities or bookmarks. Importing only adds what is missing and asks you first.'**
  String get mytsExistingDataHint;

  /// No description provided for @mytsShowPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get mytsShowPassword;

  /// No description provided for @mytsHidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get mytsHidePassword;

  /// No description provided for @mytsImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import account data'**
  String get mytsImportAction;

  /// No description provided for @mytsImportPasswordNote.
  ///
  /// In en, this message translates to:
  /// **'The password unlocks your account key for this import.'**
  String get mytsImportPasswordNote;

  /// No description provided for @mytsImportWorking.
  ///
  /// In en, this message translates to:
  /// **'Downloading and checking your account data…'**
  String get mytsImportWorking;

  /// No description provided for @mytsImportConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your account data to this device?'**
  String get mytsImportConfirmTitle;

  /// No description provided for @mytsImportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get mytsImportConfirm;

  /// No description provided for @mytsImportContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get mytsImportContinue;

  /// No description provided for @mytsImportAdded.
  ///
  /// In en, this message translates to:
  /// **'Added {identities} identities and {bookmarks} bookmarks.'**
  String mytsImportAdded(int identities, int bookmarks);

  /// No description provided for @mytsImportUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Everything from your account is already on this device. Nothing was changed.'**
  String get mytsImportUpToDate;

  /// No description provided for @mytsImportSkipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped {count} items that are invalid, duplicated or different from the copy already on this device. Nothing existing was replaced.'**
  String mytsImportSkipped(int count);

  /// No description provided for @mytsImportNothing.
  ///
  /// In en, this message translates to:
  /// **'Your account has no identities or bookmarks to import. Nothing was changed and setup is not complete; you can go back and skip sign-in to create a local identity.'**
  String get mytsImportNothing;

  /// No description provided for @mytsImportChooseIdentityNote.
  ///
  /// In en, this message translates to:
  /// **'You will choose which identity each bookmark uses the first time you connect.'**
  String get mytsImportChooseIdentityNote;

  /// No description provided for @mytsImportErrNoSession.
  ///
  /// In en, this message translates to:
  /// **'You are not signed in. Sign in again to import.'**
  String get mytsImportErrNoSession;

  /// No description provided for @mytsImportErrUnlock.
  ///
  /// In en, this message translates to:
  /// **'Your account key could not be unlocked. Check the password and sign in again. Nothing was changed on this device.'**
  String get mytsImportErrUnlock;

  /// No description provided for @mytsImportErrNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network error while downloading. Nothing was changed on this device.'**
  String get mytsImportErrNetwork;

  /// No description provided for @mytsImportErrService.
  ///
  /// In en, this message translates to:
  /// **'The service did not accept the request. Nothing was changed on this device.'**
  String get mytsImportErrService;

  /// No description provided for @mytsImportErrExpired.
  ///
  /// In en, this message translates to:
  /// **'Your sign-in expired. Sign out and sign in again. Nothing was changed on this device.'**
  String get mytsImportErrExpired;

  /// No description provided for @mytsImportErrData.
  ///
  /// In en, this message translates to:
  /// **'The reply was unexpected or too large. Nothing was changed on this device.'**
  String get mytsImportErrData;

  /// No description provided for @mytsImportErrIntegrity.
  ///
  /// In en, this message translates to:
  /// **'The downloaded data failed its integrity check. Nothing was changed on this device.'**
  String get mytsImportErrIntegrity;

  /// No description provided for @mytsImportErrStorage.
  ///
  /// In en, this message translates to:
  /// **'Could not read or save local data safely. Nothing existing was replaced.'**
  String get mytsImportErrStorage;

  /// No description provided for @identityChooseTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose an identity'**
  String get identityChooseTitle;

  /// No description provided for @identityChooseBody.
  ///
  /// In en, this message translates to:
  /// **'Pick the identity to connect with. Your choice is remembered on this device only and does not change your account.'**
  String get identityChooseBody;

  /// No description provided for @identityLocal.
  ///
  /// In en, this message translates to:
  /// **'Local identity of this device'**
  String get identityLocal;

  /// No description provided for @identityCreate.
  ///
  /// In en, this message translates to:
  /// **'Create a new local identity'**
  String get identityCreate;

  /// No description provided for @identityUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The identity could not be opened. Nothing was changed.'**
  String get identityUnavailable;

  /// No description provided for @importedFromAccount.
  ///
  /// In en, this message translates to:
  /// **'From your account'**
  String get importedFromAccount;

  /// No description provided for @identityNotChosen.
  ///
  /// In en, this message translates to:
  /// **'Identity: not chosen yet'**
  String get identityNotChosen;

  /// No description provided for @identityChosen.
  ///
  /// In en, this message translates to:
  /// **'Identity: {label}'**
  String identityChosen(String label);

  /// No description provided for @identityChange.
  ///
  /// In en, this message translates to:
  /// **'Change identity'**
  String get identityChange;

  /// No description provided for @chatOpen.
  ///
  /// In en, this message translates to:
  /// **'Account chat'**
  String get chatOpen;

  /// No description provided for @chatTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chatTitle;

  /// No description provided for @chatTabChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get chatTabChats;

  /// No description provided for @chatTabContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get chatTabContacts;

  /// No description provided for @chatTabProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get chatTabProfile;

  /// No description provided for @chatSignInRequired.
  ///
  /// In en, this message translates to:
  /// **'Sign in to myTeamSpeak to use account chat.'**
  String get chatSignInRequired;

  /// No description provided for @chatSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get chatSignIn;

  /// No description provided for @chatUnlockTitle.
  ///
  /// In en, this message translates to:
  /// **'Unlock your chat'**
  String get chatUnlockTitle;

  /// No description provided for @chatUnlockBody.
  ///
  /// In en, this message translates to:
  /// **'Your conversations and keys are stored encrypted on this device. Enter your myTeamSpeak password to unlock them.'**
  String get chatUnlockBody;

  /// No description provided for @chatUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get chatUnlock;

  /// No description provided for @homeChatSignedIn.
  ///
  /// In en, this message translates to:
  /// **'Conversations and contacts'**
  String get homeChatSignedIn;

  /// No description provided for @homeChatSignedOut.
  ///
  /// In en, this message translates to:
  /// **'Sign in with myTeamSpeak to chat with your contacts'**
  String get homeChatSignedOut;

  /// No description provided for @mytsRememberPassword.
  ///
  /// In en, this message translates to:
  /// **'Remember password on this device'**
  String get mytsRememberPassword;

  /// No description provided for @mytsRememberPasswordHint.
  ///
  /// In en, this message translates to:
  /// **'Kept in the device\'s secure storage so you aren\'t asked each time. Turn off for maximum security.'**
  String get mytsRememberPasswordHint;

  /// No description provided for @mytsImportUsingSaved.
  ///
  /// In en, this message translates to:
  /// **'The password saved on this device will be used.'**
  String get mytsImportUsingSaved;

  /// No description provided for @chatUnlockSavedBody.
  ///
  /// In en, this message translates to:
  /// **'Unlocking with the password saved on this device.'**
  String get chatUnlockSavedBody;

  /// No description provided for @chatUnlockManual.
  ///
  /// In en, this message translates to:
  /// **'Enter password manually'**
  String get chatUnlockManual;

  /// No description provided for @chatErrSavedPasswordRejected.
  ///
  /// In en, this message translates to:
  /// **'The saved password no longer works. Enter it again.'**
  String get chatErrSavedPasswordRejected;

  /// No description provided for @chatAdvanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get chatAdvanced;

  /// No description provided for @chatAllowOwnEmpty.
  ///
  /// In en, this message translates to:
  /// **'Also read my own older messages whose key backup has no sender information (the sender identity can\'t be verified)'**
  String get chatAllowOwnEmpty;

  /// No description provided for @chatConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get chatConnecting;

  /// No description provided for @chatErrWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password, or the account key couldn\'t be unlocked.'**
  String get chatErrWrongPassword;

  /// No description provided for @chatErrNetwork.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the chat server. Saved conversations are still available.'**
  String get chatErrNetwork;

  /// No description provided for @chatErrAuth.
  ///
  /// In en, this message translates to:
  /// **'The chat server rejected the saved chat login. To avoid creating duplicate devices, it is not retried automatically.'**
  String get chatErrAuth;

  /// No description provided for @chatErrRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please wait a moment.'**
  String get chatErrRateLimited;

  /// No description provided for @chatErrServer.
  ///
  /// In en, this message translates to:
  /// **'The chat server returned an error (HTTP {status}).'**
  String chatErrServer(String status);

  /// No description provided for @chatErrInvalid.
  ///
  /// In en, this message translates to:
  /// **'Unexpected response from the chat server.'**
  String get chatErrInvalid;

  /// No description provided for @chatErrLoginUncertain.
  ///
  /// In en, this message translates to:
  /// **'An earlier chat login on this device didn\'t finish cleanly. Tap retry: the same chat device is reused, no duplicate is created.'**
  String get chatErrLoginUncertain;

  /// No description provided for @chatErrNotSendable.
  ///
  /// In en, this message translates to:
  /// **'This message can\'t be sent in this conversation.'**
  String get chatErrNotSendable;

  /// No description provided for @chatErrContacts.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update your contacts.'**
  String get chatErrContacts;

  /// No description provided for @chatRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get chatRefresh;

  /// No description provided for @chatNoChats.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet. Start one from your contacts.'**
  String get chatNoChats;

  /// No description provided for @chatNewChat.
  ///
  /// In en, this message translates to:
  /// **'New chat'**
  String get chatNewChat;

  /// No description provided for @chatInvites.
  ///
  /// In en, this message translates to:
  /// **'Invitations'**
  String get chatInvites;

  /// No description provided for @chatInvitedBy.
  ///
  /// In en, this message translates to:
  /// **'{name} invited you'**
  String chatInvitedBy(Object name);

  /// No description provided for @chatAccept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get chatAccept;

  /// No description provided for @chatDecline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get chatDecline;

  /// No description provided for @chatYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get chatYou;

  /// No description provided for @chatLastEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Encrypted message'**
  String get chatLastEncrypted;

  /// No description provided for @chatLastUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Message unavailable'**
  String get chatLastUnavailable;

  /// No description provided for @chatLastDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get chatLastDeleted;

  /// No description provided for @chatEncryptedRoom.
  ///
  /// In en, this message translates to:
  /// **'End-to-end encrypted'**
  String get chatEncryptedRoom;

  /// No description provided for @chatPlainRoom.
  ///
  /// In en, this message translates to:
  /// **'Not encrypted'**
  String get chatPlainRoom;

  /// No description provided for @chatSendDisabledEncrypted.
  ///
  /// In en, this message translates to:
  /// **'Sending is only available in one-to-one encrypted conversations for now. You can read messages here and reply from the desktop app.'**
  String get chatSendDisabledEncrypted;

  /// No description provided for @chatSendDisabledLoading.
  ///
  /// In en, this message translates to:
  /// **'Conversation details are still loading…'**
  String get chatSendDisabledLoading;

  /// No description provided for @chatMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get chatMessageHint;

  /// No description provided for @chatSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get chatSend;

  /// No description provided for @chatNotSent.
  ///
  /// In en, this message translates to:
  /// **'Not sent · tap to retry'**
  String get chatNotSent;

  /// No description provided for @chatDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get chatDiscard;

  /// No description provided for @chatMissingKey.
  ///
  /// In en, this message translates to:
  /// **'Encrypted message · key not available'**
  String get chatMissingKey;

  /// No description provided for @chatPartial.
  ///
  /// In en, this message translates to:
  /// **'Older than the available key'**
  String get chatPartial;

  /// No description provided for @chatDeleted.
  ///
  /// In en, this message translates to:
  /// **'Message deleted'**
  String get chatDeleted;

  /// No description provided for @chatInvalidMessage.
  ///
  /// In en, this message translates to:
  /// **'Message couldn\'t be verified'**
  String get chatInvalidMessage;

  /// No description provided for @chatOlder.
  ///
  /// In en, this message translates to:
  /// **'Load older messages'**
  String get chatOlder;

  /// No description provided for @chatEmptyConversation.
  ///
  /// In en, this message translates to:
  /// **'No messages yet. Say hello!'**
  String get chatEmptyConversation;

  /// No description provided for @chatCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get chatCopy;

  /// No description provided for @chatCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get chatCopied;

  /// No description provided for @chatLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave conversation'**
  String get chatLeave;

  /// No description provided for @chatLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave this conversation? It will disappear from your list.'**
  String get chatLeaveConfirm;

  /// No description provided for @chatToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get chatToday;

  /// No description provided for @chatYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get chatYesterday;

  /// No description provided for @chatFile.
  ///
  /// In en, this message translates to:
  /// **'File: {name}'**
  String chatFile(String name);

  /// No description provided for @chatImage.
  ///
  /// In en, this message translates to:
  /// **'Photo: {name}'**
  String chatImage(String name);

  /// No description provided for @chatStatusAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get chatStatusAvailable;

  /// No description provided for @chatStatusAway.
  ///
  /// In en, this message translates to:
  /// **'Away'**
  String get chatStatusAway;

  /// No description provided for @chatStatusDnd.
  ///
  /// In en, this message translates to:
  /// **'Do not disturb'**
  String get chatStatusDnd;

  /// No description provided for @chatStatusOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get chatStatusOffline;

  /// No description provided for @chatStatusInvisible.
  ///
  /// In en, this message translates to:
  /// **'Appear offline'**
  String get chatStatusInvisible;

  /// No description provided for @chatContactsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No contacts yet.'**
  String get chatContactsEmpty;

  /// No description provided for @chatAddContact.
  ///
  /// In en, this message translates to:
  /// **'Add contact'**
  String get chatAddContact;

  /// No description provided for @chatEditContact.
  ///
  /// In en, this message translates to:
  /// **'Edit contact'**
  String get chatEditContact;

  /// No description provided for @chatContactId.
  ///
  /// In en, this message translates to:
  /// **'Chat ID (@user:server)'**
  String get chatContactId;

  /// No description provided for @chatContactNote.
  ///
  /// In en, this message translates to:
  /// **'Name or note'**
  String get chatContactNote;

  /// No description provided for @chatSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get chatSave;

  /// No description provided for @chatRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get chatRemove;

  /// No description provided for @chatRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from your contacts?'**
  String chatRemoveConfirm(String name);

  /// No description provided for @chatStartChat.
  ///
  /// In en, this message translates to:
  /// **'Start chat'**
  String get chatStartChat;

  /// No description provided for @chatStartPlainTitle.
  ///
  /// In en, this message translates to:
  /// **'Start an unencrypted chat?'**
  String get chatStartPlainTitle;

  /// No description provided for @chatStartPlainBody.
  ///
  /// In en, this message translates to:
  /// **'New conversations started here are not end-to-end encrypted: the chat server can read them. For private topics, start the conversation from the desktop app.'**
  String get chatStartPlainBody;

  /// No description provided for @chatStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get chatStart;

  /// No description provided for @chatProfileName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get chatProfileName;

  /// No description provided for @chatProfileId.
  ///
  /// In en, this message translates to:
  /// **'Chat ID'**
  String get chatProfileId;

  /// No description provided for @chatProfileStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get chatProfileStatus;

  /// No description provided for @chatProfileStatusMessage.
  ///
  /// In en, this message translates to:
  /// **'Status message'**
  String get chatProfileStatusMessage;

  /// No description provided for @chatProfileStatusHint.
  ///
  /// In en, this message translates to:
  /// **'What are you up to?'**
  String get chatProfileStatusHint;

  /// No description provided for @chatProfileSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get chatProfileSaved;

  /// No description provided for @chatProfileAvatarTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile picture'**
  String get chatProfileAvatarTitle;

  /// No description provided for @chatProfileAvatarNote.
  ///
  /// In en, this message translates to:
  /// **'Changing your picture isn\'t available in TS6 Droid yet. A picture set in the desktop app shows up here.'**
  String get chatProfileAvatarNote;

  /// No description provided for @chatLock.
  ///
  /// In en, this message translates to:
  /// **'Lock chat'**
  String get chatLock;

  /// No description provided for @chatLockHint.
  ///
  /// In en, this message translates to:
  /// **'Forgets the unlocked key. Saved conversations stay encrypted on this device.'**
  String get chatLockHint;

  /// No description provided for @chatSecurityNote.
  ///
  /// In en, this message translates to:
  /// **'Encrypted messages are read with keys restored from your myTeamSpeak account, and the ones you send use keys of this phone\'s own chat device. This app does not verify the devices of the people you talk to.'**
  String get chatSecurityNote;

  /// No description provided for @chatSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get chatSearch;

  /// No description provided for @chatErrNotLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'The chat login hasn\'t completed on this device yet, so nothing can be sent or loaded.'**
  String get chatErrNotLoggedIn;

  /// No description provided for @chatRetryLogin.
  ///
  /// In en, this message translates to:
  /// **'Retry chat login'**
  String get chatRetryLogin;

  /// No description provided for @chatEncryptConsentTitle.
  ///
  /// In en, this message translates to:
  /// **'Send encrypted messages from this phone?'**
  String get chatEncryptConsentTitle;

  /// No description provided for @chatEncryptConsentBody.
  ///
  /// In en, this message translates to:
  /// **'To send end-to-end encrypted messages, TS6 Droid publishes this phone\'s encryption keys to your myTeamSpeak chat account. It shows up as a new device named “TS6 Droid” in the device list of the desktop app, for you and for your contacts.\n\nRoom keys are shared with every device of the people in the conversation, including devices that haven\'t been verified. This app can\'t verify devices yet.'**
  String get chatEncryptConsentBody;

  /// No description provided for @chatEncryptConsentContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get chatEncryptConsentContinue;

  /// No description provided for @chatErrNoRecipients.
  ///
  /// In en, this message translates to:
  /// **'The message wasn\'t sent: none of this contact\'s devices is available to receive encryption keys. They may need to open their chat app first.'**
  String get chatErrNoRecipients;

  /// No description provided for @chatErrUnsupportedRoom.
  ///
  /// In en, this message translates to:
  /// **'Messages can\'t be sent in this conversation yet.'**
  String get chatErrUnsupportedRoom;

  /// No description provided for @chatErrLimit.
  ///
  /// In en, this message translates to:
  /// **'This phone can\'t hold more encryption sessions, so the message wasn\'t sent.'**
  String get chatErrLimit;

  /// No description provided for @chatNoticeDeviceChanged.
  ///
  /// In en, this message translates to:
  /// **'One of this contact\'s devices changed its encryption keys unexpectedly. It was left out and can\'t read new messages.'**
  String get chatNoticeDeviceChanged;

  /// No description provided for @chatContactAdded.
  ///
  /// In en, this message translates to:
  /// **'Contact added'**
  String get chatContactAdded;

  /// No description provided for @mytsResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Start from scratch?'**
  String get mytsResetTitle;

  /// No description provided for @mytsResetBody.
  ///
  /// In en, this message translates to:
  /// **'Signing in deletes everything this phone keeps about myTeamSpeak and starts over: the saved session and password, imported identities and bookmarks, chat keys and cache, cached contacts and saved server bookmarks. Your local TeamSpeak identity file and the app settings stay. You\'ll have to import your account again, and the chat will ask again to publish this phone\'s encryption keys. This can\'t be undone.'**
  String get mytsResetBody;

  /// No description provided for @mytsResetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete and sign in'**
  String get mytsResetConfirm;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
