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
  String get pttSetting => 'Mode appuyer pour parler';
}
