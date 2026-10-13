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
