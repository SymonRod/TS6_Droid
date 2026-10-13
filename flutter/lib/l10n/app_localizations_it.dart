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
}
