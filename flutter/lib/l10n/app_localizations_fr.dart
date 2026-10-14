// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get serverAddress => 'Adresse du serveur (hôte:port)';

  @override
  String get nickname => 'Pseudo';

  @override
  String get serverPassword => 'Mot de passe du serveur (optionnel)';

  @override
  String get channelOptional => 'Channel (optionnel, chemin avec /)';

  @override
  String get connect => 'Se connecter';

  @override
  String get saveBookmark => 'Enregistrer le favori';

  @override
  String get updateBookmark => 'Mettre à jour le favori';

  @override
  String get cancel => 'Annuler';

  @override
  String get reconnectLast => 'Se reconnecter au dernier serveur au démarrage';

  @override
  String get noBookmarks => 'Aucun favori';

  @override
  String get errAddrNick => 'L\'adresse et le pseudo sont requis';

  @override
  String get disconnect => 'Déconnexion';

  @override
  String get channels => 'Channels';

  @override
  String get chat => 'Chat';

  @override
  String get tabChannel => 'Channel';

  @override
  String get tabServer => 'Serveur';

  @override
  String get tabPrivate => 'Privé';

  @override
  String get sendTo => 'Envoyer à...';

  @override
  String get messageHint => 'Message';

  @override
  String get mute => 'Couper le micro';

  @override
  String get unmute => 'Activer le micro';

  @override
  String get pushToTalk => 'Appuyer pour parler';

  @override
  String get holdToTalk => 'Maintenir pour parler';

  @override
  String get you => 'vous';

  @override
  String get watchShare => 'Regarder le partage d\'écran';

  @override
  String get streamNotReady => 'Infos du partage pas encore reçues, réessayez.';

  @override
  String get channelPasswordTitle => 'Mot de passe du channel';

  @override
  String get password => 'Mot de passe';

  @override
  String get join => 'Rejoindre';

  @override
  String get leave => 'Quitter';

  @override
  String get fit => 'Afficher l\'image entière';

  @override
  String get fill => 'Remplir l\'écran';

  @override
  String get shareRequesting => 'En attente de l\'acceptation...';

  @override
  String get shareConnecting => 'Connexion...';

  @override
  String get shareEnded => 'Le partage est terminé';

  @override
  String get shareTimeout => 'Aucune réponse du partageur';

  @override
  String get shareRefused => 'Le partage a été refusé';

  @override
  String get shareIce => 'Connexion au partage impossible';

  @override
  String get shareFailed => 'Échec.';

  @override
  String connectedTo(String address) {
    return 'Connecté à $address';
  }

  @override
  String get notifMute => 'Mute';

  @override
  String get notifUnmute => 'Réactiver';

  @override
  String get shareDeviceAudio => 'Partager l’audio de l’appareil';

  @override
  String get shareDeviceAudioHint =>
      'Musique, jeux et vidéos arrivent aux spectateurs (ni voix ni micro). À régler avant de partager.';

  @override
  String get pttSetting => 'Mode appuyer pour parler';

  @override
  String get deafen => 'Couper le son';

  @override
  String get undeafen => 'Rétablir le son';

  @override
  String get disconnectConfirm => 'Voulez-vous vous déconnecter ?';

  @override
  String get shareScreen => 'Partager l’écran';

  @override
  String get stopShare => 'Arrêter';

  @override
  String get audioOutput => 'Sortie audio';

  @override
  String get audioAuto => 'Automatique';

  @override
  String get audioSpeaker => 'Haut-parleur';

  @override
  String get audioEarpiece => 'Écouteur';

  @override
  String get audioDeviceFallback => 'Périphérique audio';

  @override
  String get more => 'Plus';

  @override
  String get mytsTitle => 'myTeamSpeak';

  @override
  String get mytsEmail => 'E-mail';

  @override
  String get mytsAccountPassword => 'Mot de passe du compte';

  @override
  String get mytsOtp => 'Code à usage unique';

  @override
  String get mytsOtpHint => 'Votre compte exige un code à usage unique.';

  @override
  String get mytsLogin => 'Se connecter';

  @override
  String get mytsLogout => 'Se déconnecter';

  @override
  String mytsLoggedInAs(String username) {
    return 'Connecté en tant que $username';
  }

  @override
  String get mytsEmailPasswordRequired => 'L\'e-mail et le mot de passe sont requis';

  @override
  String get mytsErrorCredentials => 'E-mail ou mot de passe incorrect';

  @override
  String get mytsErrorOffline => 'Service de connexion indisponible, réessayez plus tard';

  @override
  String get mytsErrorEmailPending => 'Cette adresse e-mail est en attente de confirmation';

  @override
  String get mytsErrorOtpRequired => 'Ce compte exige un code à usage unique';

  @override
  String get mytsErrorOtpInvalid => 'Code à usage unique incorrect';

  @override
  String get mytsErrorNetwork => 'Erreur réseau, vérifiez votre connexion';

  @override
  String mytsErrorHttp(String status) {
    return 'Échec de la connexion (HTTP $status)';
  }

  @override
  String get mytsErrorMalformed => 'Réponse inattendue du serveur';

  @override
  String get mytsErrorPaced => 'Attendez quelques secondes avant de réessayer';

  @override
  String get mytsErrorOther => 'Échec de la connexion';
}
