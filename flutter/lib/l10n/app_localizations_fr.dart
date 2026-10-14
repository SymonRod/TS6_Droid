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
  String get newServer => 'Nouveau serveur';

  @override
  String get editServer => 'Modifier le serveur';

  @override
  String get savedServers => 'Serveurs enregistrés';

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
  String get mytsEmailPasswordRequired =>
      'L\'e-mail et le mot de passe sont requis';

  @override
  String get mytsErrorCredentials => 'E-mail ou mot de passe incorrect';

  @override
  String get mytsErrorOffline =>
      'Service de connexion indisponible, réessayez plus tard';

  @override
  String get mytsErrorEmailPending =>
      'Cette adresse e-mail est en attente de confirmation';

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

  @override
  String get setupWelcome => 'Bienvenue dans TS6 Droid';

  @override
  String get setupIntro =>
      'Choisissez comment configurer votre client TeamSpeak.';

  @override
  String get setupAccountTitle => 'Votre compte myTeamSpeak';

  @override
  String get setupAccountHint =>
      'La configuration avec un compte importera automatiquement les identités et favoris serveur pris en charge depuis le cloud, en conservant le lien entre chaque favori et son identité. Les données enregistrées uniquement sur votre ordinateur ne peuvent pas être restaurées depuis le cloud.';

  @override
  String get setupImportPending =>
      'Se connecter télécharge vos identités et favoris et les conserve de façon sécurisée sur cet appareil. Le compte est seulement lu ; rien ne change dans le cloud.';

  @override
  String get setupSignIn => 'Se connecter avec myTeamSpeak';

  @override
  String get setupSkip => 'Ignorer la connexion';

  @override
  String get setupSkipHint =>
      'Créez une identité locale et connectez-vous aux serveurs sans compte. Vous pourrez vous connecter plus tard ; vos données locales seront conservées.';

  @override
  String get setupBack => 'Retour à la configuration';

  @override
  String get setupRetry => 'Réessayer';

  @override
  String get setupReadError =>
      'Impossible de lire votre configuration locale en toute sécurité. Vos données n’ont pas été remplacées. Vérifiez l’accès au stockage et réessayez.';

  @override
  String get setupWriteError =>
      'Impossible de terminer la configuration locale. Réessayez d’ignorer la connexion ; toute identité déjà enregistrée sera réutilisée.';

  @override
  String get mytsImportPendingTitle => 'Importer les données du compte';

  @override
  String get mytsSetupImportPending =>
      'Vous êtes connecté, mais rien n’a encore été importé : la configuration n’est donc pas terminée. Saisissez le mot de passe du compte pour télécharger identités et favoris, ou revenez à la configuration pour utiliser une identité locale.';

  @override
  String get mytsExistingDataHint =>
      'La connexion ne remplace jamais vos identités ou favoris locaux. L’importation n’ajoute que ce qui manque et vous demande d’abord confirmation.';

  @override
  String get mytsShowPassword => 'Afficher le mot de passe';

  @override
  String get mytsHidePassword => 'Masquer le mot de passe';

  @override
  String get mytsImportAction => 'Importer les données du compte';

  @override
  String get mytsImportPasswordNote =>
      'Le mot de passe déverrouille la clé du compte pour cette importation uniquement et n’est pas enregistré.';

  @override
  String get mytsImportWorking =>
      'Téléchargement et vérification des données du compte…';

  @override
  String get mytsImportConfirmTitle =>
      'Ajouter les données du compte à cet appareil ?';

  @override
  String get mytsImportConfirm => 'Importer';

  @override
  String get mytsImportContinue => 'Continuer';

  @override
  String mytsImportAdded(int identities, int bookmarks) {
    return '$identities identités et $bookmarks favoris ajoutés.';
  }

  @override
  String get mytsImportUpToDate =>
      'Tout ce qui se trouve dans votre compte est déjà sur cet appareil. Rien n’a été modifié.';

  @override
  String mytsImportSkipped(int count) {
    return '$count éléments ignorés car invalides, en double ou différents de la copie déjà présente sur cet appareil. Rien d’existant n’a été remplacé.';
  }

  @override
  String get mytsImportNothing =>
      'Votre compte n’a ni identité ni favori à importer. Rien n’a été modifié et la configuration n’est pas terminée ; vous pouvez revenir et ignorer la connexion pour créer une identité locale.';

  @override
  String get mytsImportChooseIdentityNote =>
      'Vous choisirez l’identité de chaque favori lors de la première connexion.';

  @override
  String get mytsImportErrNoSession =>
      'Vous n’êtes pas connecté. Reconnectez-vous pour importer.';

  @override
  String get mytsImportErrUnlock =>
      'Impossible de déverrouiller la clé du compte. Vérifiez le mot de passe et reconnectez-vous. Rien n’a été modifié sur cet appareil.';

  @override
  String get mytsImportErrNetwork =>
      'Erreur réseau pendant le téléchargement. Rien n’a été modifié sur cet appareil.';

  @override
  String get mytsImportErrService =>
      'Le service n’a pas accepté la requête. Rien n’a été modifié sur cet appareil.';

  @override
  String get mytsImportErrExpired =>
      'Votre connexion a expiré. Déconnectez-vous puis reconnectez-vous. Rien n’a été modifié sur cet appareil.';

  @override
  String get mytsImportErrData =>
      'La réponse était inattendue ou trop volumineuse. Rien n’a été modifié sur cet appareil.';

  @override
  String get mytsImportErrIntegrity =>
      'Les données téléchargées ont échoué au contrôle d’intégrité. Rien n’a été modifié sur cet appareil.';

  @override
  String get mytsImportErrStorage =>
      'Impossible de lire ou d’enregistrer les données locales en toute sécurité. Rien d’existant n’a été remplacé.';

  @override
  String get identityChooseTitle => 'Choisir une identité';

  @override
  String get identityChooseBody =>
      'Choisissez l’identité avec laquelle vous connecter. Ce choix reste sur cet appareil et ne modifie pas votre compte.';

  @override
  String get identityLocal => 'Identité locale de cet appareil';

  @override
  String get identityCreate => 'Créer une nouvelle identité locale';

  @override
  String get identityUnavailable =>
      'Impossible d’ouvrir l’identité. Rien n’a été modifié.';

  @override
  String get importedFromAccount => 'Depuis votre compte';

  @override
  String get identityNotChosen => 'Identité : pas encore choisie';

  @override
  String identityChosen(String label) {
    return 'Identité : $label';
  }

  @override
  String get identityChange => 'Changer d’identité';
}
