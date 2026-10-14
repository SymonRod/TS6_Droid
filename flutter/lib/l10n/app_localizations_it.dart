// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get serverAddress => 'Indirizzo del server (host:porta)';

  @override
  String get nickname => 'Nickname';

  @override
  String get serverPassword => 'Password del server (facoltativa)';

  @override
  String get channelOptional => 'Canale (facoltativo, percorso con /)';

  @override
  String get connect => 'Connetti';

  @override
  String get saveBookmark => 'Salva preferito';

  @override
  String get updateBookmark => 'Aggiorna preferito';

  @override
  String get cancel => 'Annulla';

  @override
  String get reconnectLast => 'Riconnetti all\'ultimo server all\'avvio';

  @override
  String get noBookmarks => 'Nessun preferito';

  @override
  String get newServer => 'Nuovo server';

  @override
  String get editServer => 'Modifica server';

  @override
  String get savedServers => 'Server salvati';

  @override
  String get errAddrNick => 'Indirizzo e nickname sono obbligatori';

  @override
  String get disconnect => 'Disconnetti';

  @override
  String get channels => 'Canali';

  @override
  String get chat => 'Chat';

  @override
  String get tabChannel => 'Canale';

  @override
  String get tabServer => 'Server';

  @override
  String get tabPrivate => 'Privato';

  @override
  String get sendTo => 'Invia a...';

  @override
  String get messageHint => 'Messaggio';

  @override
  String get mute => 'Disattiva il microfono';

  @override
  String get unmute => 'Attiva il microfono';

  @override
  String get pushToTalk => 'Premi per parlare';

  @override
  String get holdToTalk => 'Tieni premuto per parlare';

  @override
  String get you => 'tu';

  @override
  String get watchShare => 'Guarda la condivisione schermo';

  @override
  String get streamNotReady =>
      'Info sulla condivisione non ancora ricevute, riprova.';

  @override
  String get channelPasswordTitle => 'Password del canale';

  @override
  String get password => 'Password';

  @override
  String get join => 'Entra';

  @override
  String get leave => 'Esci';

  @override
  String get fit => 'Adatta l\'intera immagine';

  @override
  String get fill => 'Riempi lo schermo';

  @override
  String get shareRequesting => 'In attesa che l\'utente accetti...';

  @override
  String get shareConnecting => 'Connessione in corso...';

  @override
  String get shareEnded => 'La condivisione è terminata';

  @override
  String get shareTimeout => 'Nessuna risposta dall\'utente';

  @override
  String get shareRefused => 'L\'utente ha rifiutato la richiesta';

  @override
  String get shareIce => 'Impossibile connettersi alla condivisione';

  @override
  String get shareFailed => 'Errore.';

  @override
  String connectedTo(String address) {
    return 'Connesso a $address';
  }

  @override
  String get notifMute => 'Muto';

  @override
  String get notifUnmute => 'Riattiva';

  @override
  String get shareDeviceAudio => 'Condividi audio del dispositivo';

  @override
  String get shareDeviceAudioHint =>
      'Musica, giochi e video arrivano a chi guarda (non voci né microfono). Da impostare prima di condividere.';

  @override
  String get pttSetting => 'Modalità premi per parlare';

  @override
  String get deafen => 'Disattiva audio';

  @override
  String get undeafen => 'Riattiva audio';

  @override
  String get disconnectConfirm => 'Vuoi disconnetterti?';

  @override
  String get shareScreen => 'Condividi schermo';

  @override
  String get stopShare => 'Interrompi';

  @override
  String get audioOutput => 'Uscita audio';

  @override
  String get audioAuto => 'Automatico';

  @override
  String get audioSpeaker => 'Altoparlante';

  @override
  String get audioEarpiece => 'Auricolare';

  @override
  String get audioDeviceFallback => 'Dispositivo audio';

  @override
  String get more => 'Altro';

  @override
  String get mytsTitle => 'myTeamSpeak';

  @override
  String get mytsEmail => 'Email';

  @override
  String get mytsAccountPassword => 'Password dell\'account';

  @override
  String get mytsOtp => 'Codice monouso';

  @override
  String get mytsOtpHint => 'Il tuo account richiede un codice monouso.';

  @override
  String get mytsLogin => 'Accedi';

  @override
  String get mytsLogout => 'Esci';

  @override
  String mytsLoggedInAs(String username) {
    return 'Connesso come $username';
  }

  @override
  String get mytsEmailPasswordRequired => 'Email e password sono obbligatorie';

  @override
  String get mytsErrorCredentials => 'Email o password errati';

  @override
  String get mytsErrorOffline =>
      'Servizio di login non disponibile, riprova più tardi';

  @override
  String get mytsErrorEmailPending =>
      'Questo indirizzo email è in attesa di conferma';

  @override
  String get mytsErrorOtpRequired =>
      'Questo account richiede un codice monouso';

  @override
  String get mytsErrorOtpInvalid => 'Codice monouso errato';

  @override
  String get mytsErrorNetwork => 'Errore di rete, controlla la connessione';

  @override
  String mytsErrorHttp(String status) {
    return 'Accesso fallito (HTTP $status)';
  }

  @override
  String get mytsErrorMalformed => 'Risposta inattesa dal server';

  @override
  String get mytsErrorPaced => 'Attendi qualche secondo prima di riprovare';

  @override
  String get mytsErrorOther => 'Accesso fallito';

  @override
  String get setupWelcome => 'Benvenuto in TS6 Droid';

  @override
  String get setupIntro => 'Scegli come configurare il tuo client TeamSpeak.';

  @override
  String get setupAccountTitle => 'Il tuo account myTeamSpeak';

  @override
  String get setupAccountHint =>
      'La configurazione con account importerà automaticamente le identità e i preferiti server supportati dal cloud, mantenendo ogni preferito collegato alla sua identità. I dati salvati solo sul desktop non possono essere recuperati dal cloud.';

  @override
  String get setupImportPending =>
      'Accedendo scarichi le tue identità e i tuoi preferiti e li conservi in modo sicuro su questo dispositivo. L’account viene solo letto; nel cloud non cambia nulla.';

  @override
  String get setupSignIn => 'Accedi con myTeamSpeak';

  @override
  String get setupSkip => 'Salta l’accesso';

  @override
  String get setupSkipHint =>
      'Crea un’identità locale e connettiti ai server senza account. Potrai accedere in seguito; i tuoi dati locali saranno conservati.';

  @override
  String get setupBack => 'Torna alla configurazione';

  @override
  String get setupRetry => 'Riprova';

  @override
  String get setupReadError =>
      'Impossibile leggere in sicurezza la configurazione locale. I tuoi dati non sono stati sostituiti. Controlla l’accesso allo spazio di archiviazione e riprova.';

  @override
  String get setupWriteError =>
      'Impossibile completare la configurazione locale. Prova di nuovo a saltare l’accesso; qualsiasi identità già salvata verrà riutilizzata.';

  @override
  String get mytsImportPendingTitle => 'Importa i dati dell’account';

  @override
  String get mytsSetupImportPending =>
      'Hai effettuato l’accesso, ma non è stato ancora importato nulla, quindi la configurazione non è completa. Inserisci la password dell’account per scaricare identità e preferiti, oppure torna alla configurazione per usare un’identità locale.';

  @override
  String get mytsExistingDataHint =>
      'L’accesso non sostituisce mai le identità o i preferiti locali. L’importazione aggiunge solo ciò che manca e prima ti chiede conferma.';

  @override
  String get mytsShowPassword => 'Mostra password';

  @override
  String get mytsHidePassword => 'Nascondi password';

  @override
  String get mytsImportAction => 'Importa i dati dell’account';

  @override
  String get mytsImportPasswordNote =>
      'La password sblocca la chiave dell’account solo per questa importazione e non viene salvata.';

  @override
  String get mytsImportWorking => 'Download e verifica dei dati dell’account…';

  @override
  String get mytsImportConfirmTitle =>
      'Aggiungere i dati dell’account a questo dispositivo?';

  @override
  String get mytsImportConfirm => 'Importa';

  @override
  String get mytsImportContinue => 'Continua';

  @override
  String mytsImportAdded(int identities, int bookmarks) {
    return 'Aggiunte $identities identità e $bookmarks preferiti.';
  }

  @override
  String get mytsImportUpToDate =>
      'Tutto ciò che è nel tuo account è già su questo dispositivo. Non è stato modificato nulla.';

  @override
  String mytsImportSkipped(int count) {
    return 'Saltati $count elementi non validi, duplicati o diversi dalla copia già presente su questo dispositivo. Nulla di esistente è stato sostituito.';
  }

  @override
  String get mytsImportNothing =>
      'Il tuo account non ha identità o preferiti da importare. Non è stato modificato nulla e la configurazione non è completa; puoi tornare indietro e saltare l’accesso per creare un’identità locale.';

  @override
  String get mytsImportChooseIdentityNote =>
      'Sceglierai quale identità usa ogni preferito la prima volta che ti colleghi.';

  @override
  String get mytsImportErrNoSession =>
      'Non hai effettuato l’accesso. Accedi di nuovo per importare.';

  @override
  String get mytsImportErrUnlock =>
      'Impossibile sbloccare la chiave dell’account. Controlla la password e accedi di nuovo. Su questo dispositivo non è stato modificato nulla.';

  @override
  String get mytsImportErrNetwork =>
      'Errore di rete durante il download. Su questo dispositivo non è stato modificato nulla.';

  @override
  String get mytsImportErrService =>
      'Il servizio non ha accettato la richiesta. Su questo dispositivo non è stato modificato nulla.';

  @override
  String get mytsImportErrExpired =>
      'L’accesso è scaduto. Esci e accedi di nuovo. Su questo dispositivo non è stato modificato nulla.';

  @override
  String get mytsImportErrData =>
      'La risposta era inattesa o troppo grande. Su questo dispositivo non è stato modificato nulla.';

  @override
  String get mytsImportErrIntegrity =>
      'I dati scaricati non hanno superato il controllo di integrità. Su questo dispositivo non è stato modificato nulla.';

  @override
  String get mytsImportErrStorage =>
      'Impossibile leggere o salvare i dati locali in modo sicuro. Nulla di esistente è stato sostituito.';

  @override
  String get identityChooseTitle => 'Scegli un’identità';

  @override
  String get identityChooseBody =>
      'Scegli l’identità con cui collegarti. La scelta resta solo su questo dispositivo e non modifica il tuo account.';

  @override
  String get identityLocal => 'Identità locale di questo dispositivo';

  @override
  String get identityCreate => 'Crea una nuova identità locale';

  @override
  String get identityUnavailable =>
      'Impossibile aprire l’identità. Non è stato modificato nulla.';

  @override
  String get importedFromAccount => 'Dal tuo account';

  @override
  String get identityNotChosen => 'Identità: non ancora scelta';

  @override
  String identityChosen(String label) {
    return 'Identità: $label';
  }

  @override
  String get identityChange => 'Cambia identità';
}
