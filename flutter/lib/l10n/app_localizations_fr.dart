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
      'Le mot de passe déverrouille la clé du compte pour cette importation.';

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

  @override
  String get chatOpen => 'Chat du compte';

  @override
  String get chatTitle => 'Chat';

  @override
  String get chatTabChats => 'Discussions';

  @override
  String get chatTabContacts => 'Contacts';

  @override
  String get chatTabProfile => 'Profil';

  @override
  String get chatSignInRequired =>
      'Connectez-vous à myTeamSpeak pour utiliser le chat du compte.';

  @override
  String get chatSignIn => 'Se connecter';

  @override
  String get chatUnlockTitle => 'Déverrouiller le chat';

  @override
  String get chatUnlockBody =>
      'Vos conversations et clés sont stockées chiffrées sur cet appareil. Saisissez votre mot de passe myTeamSpeak pour les déverrouiller.';

  @override
  String get chatUnlock => 'Déverrouiller';

  @override
  String get homeChatSignedIn => 'Conversations et contacts';

  @override
  String get homeChatSignedOut =>
      'Connectez-vous avec myTeamSpeak pour discuter avec vos contacts';

  @override
  String get mytsRememberPassword =>
      'Mémoriser le mot de passe sur cet appareil';

  @override
  String get mytsRememberPasswordHint =>
      'Conservé dans le stockage sécurisé de l’appareil pour ne pas le redemander à chaque fois. Désactivez pour une sécurité maximale.';

  @override
  String get mytsImportUsingSaved =>
      'Le mot de passe enregistré sur cet appareil sera utilisé.';

  @override
  String get chatUnlockSavedBody =>
      'Déverrouillage avec le mot de passe enregistré sur cet appareil.';

  @override
  String get chatUnlockManual => 'Saisir le mot de passe manuellement';

  @override
  String get chatErrSavedPasswordRejected =>
      'Le mot de passe enregistré ne fonctionne plus. Saisissez-le à nouveau.';

  @override
  String get chatAdvanced => 'Avancé';

  @override
  String get chatAllowOwnEmpty =>
      'Lire aussi mes anciens messages dont la sauvegarde de clé ne contient pas d\'informations sur l\'expéditeur (l\'identité de l\'expéditeur ne peut pas être vérifiée)';

  @override
  String get chatConnecting => 'Connexion…';

  @override
  String get chatErrWrongPassword =>
      'Mot de passe incorrect, ou la clé du compte n\'a pas pu être déverrouillée.';

  @override
  String get chatErrNetwork =>
      'Impossible de joindre le serveur de chat. Les conversations enregistrées restent disponibles.';

  @override
  String get chatErrAuth =>
      'Le serveur de chat a refusé la connexion enregistrée. Pour éviter de créer des appareils en double, elle n\'est pas relancée automatiquement.';

  @override
  String get chatErrRateLimited =>
      'Trop de requêtes. Veuillez patienter un instant.';

  @override
  String chatErrServer(String status) {
    return 'Le serveur de chat a renvoyé une erreur (HTTP $status).';
  }

  @override
  String get chatErrInvalid => 'Réponse inattendue du serveur de chat.';

  @override
  String get chatErrLoginUncertain =>
      'Une précédente connexion au chat sur cet appareil ne s\'est pas terminée correctement. Appuyez sur réessayer : le même appareil de chat est réutilisé, aucun doublon n\'est créé.';

  @override
  String get chatErrNotSendable =>
      'Ce message ne peut pas être envoyé dans cette conversation.';

  @override
  String get chatErrContacts => 'Impossible de mettre à jour vos contacts.';

  @override
  String get chatRefresh => 'Actualiser';

  @override
  String get chatNoChats =>
      'Aucune conversation. Démarrez-en une depuis vos contacts.';

  @override
  String get chatNewChat => 'Nouveau chat';

  @override
  String get chatInvites => 'Invitations';

  @override
  String chatInvitedBy(Object name) {
    return '$name vous a invité';
  }

  @override
  String get chatAccept => 'Accepter';

  @override
  String get chatDecline => 'Refuser';

  @override
  String get chatYou => 'Vous';

  @override
  String get chatLastEncrypted => 'Message chiffré';

  @override
  String get chatLastUnavailable => 'Message indisponible';

  @override
  String get chatLastDeleted => 'Message supprimé';

  @override
  String get chatEncryptedRoom => 'Chiffré de bout en bout';

  @override
  String get chatPlainRoom => 'Non chiffré';

  @override
  String get chatSendDisabledEncrypted =>
      'L\'envoi n\'est pour l\'instant possible que dans les conversations chiffrées en tête-à-tête. Vous pouvez lire les messages ici et répondre depuis l\'application de bureau.';

  @override
  String get chatSendDisabledLoading =>
      'Chargement des détails de la conversation…';

  @override
  String get chatMessageHint => 'Message';

  @override
  String get chatSend => 'Envoyer';

  @override
  String get chatNotSent => 'Non envoyé · appuyez pour réessayer';

  @override
  String get chatDiscard => 'Supprimer';

  @override
  String get chatMissingKey => 'Message chiffré · clé indisponible';

  @override
  String get chatPartial => 'Antérieur à la clé disponible';

  @override
  String get chatDeleted => 'Message supprimé';

  @override
  String get chatInvalidMessage => 'Le message n\'a pas pu être vérifié';

  @override
  String get chatOlder => 'Charger les messages précédents';

  @override
  String get chatEmptyConversation => 'Pas encore de message. Dites bonjour !';

  @override
  String get chatCopy => 'Copier';

  @override
  String get chatCopied => 'Copié';

  @override
  String get chatLeave => 'Quitter la conversation';

  @override
  String get chatLeaveConfirm =>
      'Quitter cette conversation ? Elle disparaîtra de votre liste.';

  @override
  String get chatToday => 'Aujourd\'hui';

  @override
  String get chatYesterday => 'Hier';

  @override
  String chatFile(String name) {
    return 'Fichier : $name';
  }

  @override
  String chatImage(String name) {
    return 'Photo : $name';
  }

  @override
  String get chatStatusAvailable => 'Disponible';

  @override
  String get chatStatusAway => 'Absent';

  @override
  String get chatStatusDnd => 'Ne pas déranger';

  @override
  String get chatStatusOffline => 'Hors ligne';

  @override
  String get chatStatusInvisible => 'Apparaître hors ligne';

  @override
  String get chatContactsEmpty => 'Aucun contact pour l\'instant.';

  @override
  String get chatAddContact => 'Ajouter un contact';

  @override
  String get chatEditContact => 'Modifier le contact';

  @override
  String get chatContactId => 'ID de chat (@utilisateur:serveur)';

  @override
  String get chatContactNote => 'Nom ou note';

  @override
  String get chatSave => 'Enregistrer';

  @override
  String get chatRemove => 'Supprimer';

  @override
  String chatRemoveConfirm(String name) {
    return 'Retirer $name de vos contacts ?';
  }

  @override
  String get chatStartChat => 'Démarrer le chat';

  @override
  String get chatStartPlainTitle => 'Démarrer un chat non chiffré ?';

  @override
  String get chatStartPlainBody =>
      'Les nouvelles conversations démarrées ici ne sont pas chiffrées de bout en bout : le serveur de chat peut les lire. Pour les sujets privés, démarrez la conversation depuis l\'application de bureau.';

  @override
  String get chatStart => 'Démarrer';

  @override
  String get chatProfileName => 'Nom affiché';

  @override
  String get chatProfileId => 'ID de chat';

  @override
  String get chatProfileStatus => 'Statut';

  @override
  String get chatProfileStatusMessage => 'Message de statut';

  @override
  String get chatProfileStatusHint => 'Que faites-vous ?';

  @override
  String get chatProfileSaved => 'Enregistré';

  @override
  String get chatProfileAvatarTitle => 'Photo de profil';

  @override
  String get chatProfileAvatarNote =>
      'Le changement de photo n\'est pas encore disponible dans TS6 Droid. Une photo définie dans l\'application de bureau apparaît ici.';

  @override
  String get chatLock => 'Verrouiller le chat';

  @override
  String get chatLockHint =>
      'Oublie la clé déverrouillée. Les conversations enregistrées restent chiffrées sur cet appareil.';

  @override
  String get chatSecurityNote =>
      'Les messages chiffrés sont lus avec les clés restaurées depuis votre compte myTeamSpeak, et ceux que vous envoyez utilisent les clés de l\'appareil de chat de ce téléphone. L\'application ne vérifie pas les appareils de vos interlocuteurs.';

  @override
  String get chatSearch => 'Rechercher';

  @override
  String get chatErrNotLoggedIn =>
      'La connexion au chat n\'est pas encore terminée sur cet appareil ; rien ne peut être envoyé ni chargé.';

  @override
  String get chatRetryLogin => 'Réessayer la connexion au chat';

  @override
  String get chatEncryptConsentTitle =>
      'Envoyer des messages chiffrés depuis ce téléphone ?';

  @override
  String get chatEncryptConsentBody =>
      'Pour envoyer des messages chiffrés de bout en bout, TS6 Droid publie les clés de chiffrement de ce téléphone sur votre compte de chat myTeamSpeak. Il apparaît comme un nouvel appareil nommé « TS6 Droid » dans la liste des appareils de l\'application de bureau, pour vous et pour vos contacts.\n\nLes clés de conversation sont partagées avec tous les appareils des personnes de la conversation, y compris ceux qui n\'ont pas été vérifiés. L\'application ne peut pas encore vérifier les appareils.';

  @override
  String get chatEncryptConsentContinue => 'Continuer';

  @override
  String get chatErrNoRecipients =>
      'Le message n\'a pas été envoyé : aucun appareil de ce contact n\'est disponible pour recevoir les clés de chiffrement. Il doit peut-être d\'abord ouvrir son application de chat.';

  @override
  String get chatErrUnsupportedRoom =>
      'Les messages ne peuvent pas encore être envoyés dans cette conversation.';

  @override
  String get chatErrLimit =>
      'Ce téléphone ne peut pas stocker davantage de sessions de chiffrement ; le message n\'a donc pas été envoyé.';

  @override
  String get chatNoticeDeviceChanged =>
      'Un appareil de ce contact a modifié ses clés de chiffrement de manière inattendue. Il a été écarté et ne peut pas lire les nouveaux messages.';

  @override
  String get chatContactAdded => 'Contact ajouté';

  @override
  String get mytsResetTitle => 'Repartir de zéro ?';

  @override
  String get mytsResetBody =>
      'La connexion supprime tout ce que ce téléphone conserve sur myTeamSpeak et repart de zéro : session et mot de passe enregistrés, identités et favoris importés, clés et cache du chat, contacts en cache et favoris de serveurs enregistrés. Le fichier d\'identité TeamSpeak local et les réglages de l\'application sont conservés. Vous devrez réimporter le compte et le chat demandera à nouveau de publier les clés de chiffrement de ce téléphone. Cette action est irréversible.';

  @override
  String get mytsResetConfirm => 'Supprimer et se connecter';
}
