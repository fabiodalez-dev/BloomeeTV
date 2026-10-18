// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get onboardingTitle => 'Benvenuto in Bloomee TV';

  @override
  String get onboardingSubtitle => 'Imposta la tua lingua e la tua regione.';

  @override
  String get continueButton => 'Continua';

  @override
  String get navHome => 'Home';

  @override
  String get navLibrary => 'Libreria';

  @override
  String get navSearch => 'Cerca';

  @override
  String get navLocal => 'Locali';

  @override
  String get navOffline => 'Scaricati';

  @override
  String get playerEnjoyingFrom => 'In riproduzione da';

  @override
  String get playerQueue => 'Coda';

  @override
  String get playerPlayWithMix => 'Riproduci con Auto-Mix';

  @override
  String get playerPlayNext => 'Riproduci dopo';

  @override
  String get playerAddToQueue => 'Aggiungi alla coda';

  @override
  String get playerAddToFavorites => 'Aggiungi ai preferiti';

  @override
  String get playerNoLyricsFound => 'Nessun testo trovato';

  @override
  String get playerLyricsNoPlugin =>
      'Nessun provider di testi configurato. Vai in Impostazioni → Plugin per installarne uno.';

  @override
  String get playerFullscreenLyrics => 'Testo a schermo intero';

  @override
  String get localMusicTitle => 'Locali';

  @override
  String get localMusicGrantPermission => 'Concedi autorizzazione';

  @override
  String get localMusicStorageAccessRequired =>
      'Accesso alla memoria richiesto';

  @override
  String get localMusicStorageAccessDesc =>
      'Concedi l\'autorizzazione per cercare e riprodurre i file audio memorizzati sul dispositivo.';

  @override
  String get localMusicAddFolder => 'Aggiungi cartella musicale';

  @override
  String get localMusicScanNow => 'Scansiona ora';

  @override
  String localMusicScanFailed(String message) {
    return 'Scansione non riuscita: $message';
  }

  @override
  String get localMusicScanning => 'Ricerca di file audio sul dispositivo...';

  @override
  String get localMusicEmpty => 'Nessuna musica locale trovata';

  @override
  String get localMusicSearchEmpty => 'Nessun brano corrisponde alla ricerca.';

  @override
  String get localMusicShuffle => 'Casuale';

  @override
  String get localMusicPlayAll => 'Riproduci tutto';

  @override
  String get localMusicSearchHint => 'Cerca nella musica locale...';

  @override
  String get localMusicRescanDevice => 'Riscansiona dispositivo';

  @override
  String get localMusicRemoveFolder => 'Rimuovi cartella';

  @override
  String get localMusicMusicFolders => 'Cartelle musicali';

  @override
  String localMusicTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count brani',
      one: '1 brano',
    );
    return '$_temp0';
  }

  @override
  String get buttonCancel => 'Annulla';

  @override
  String get buttonDelete => 'Elimina';

  @override
  String get buttonOk => 'OK';

  @override
  String get buttonUpdate => 'Aggiorna';

  @override
  String get buttonDownload => 'Scarica';

  @override
  String get buttonShare => 'Condividi';

  @override
  String get buttonLater => 'Più tardi';

  @override
  String get buttonInfo => 'Info';

  @override
  String get buttonMore => 'Altro';

  @override
  String get dialogDeleteTrack => 'Elimina brano';

  @override
  String dialogDeleteTrackMessage(String title) {
    return 'Vuoi davvero eliminare \"$title\" dal dispositivo? Questa azione non può essere annullata.';
  }

  @override
  String get dialogDeleteTrackLinkedPlaylists =>
      'Questo brano verrà rimosso anche da:';

  @override
  String get dialogDontAskAgain => 'Non chiedere più';

  @override
  String get dialogDeletePlugin => 'Eliminare il plugin?';

  @override
  String dialogDeletePluginMessage(String name) {
    return 'Vuoi davvero eliminare \"$name\"? I suoi file verranno rimossi in modo definitivo.';
  }

  @override
  String get dialogUpdateAvailable => 'Aggiornamento disponibile';

  @override
  String get dialogUpdateNow => 'Aggiorna ora';

  @override
  String get dialogDownloadPlaylist => 'Scarica playlist';

  @override
  String dialogDownloadPlaylistMessage(int count, String title) {
    return 'Vuoi scaricare $count brani da \"$title\"? Verranno aggiunti alla coda di download.';
  }

  @override
  String get dialogDownloadAll => 'Scarica tutto';

  @override
  String get playlistEdit => 'Modifica playlist';

  @override
  String get playlistShareFile => 'Condividi file';

  @override
  String get playlistExportFile => 'Esporta file';

  @override
  String get playlistPlay => 'Riproduci';

  @override
  String get playlistAddToQueue => 'Aggiungi playlist alla coda';

  @override
  String get playlistShare => 'Condividi playlist';

  @override
  String get playlistDelete => 'Elimina playlist';

  @override
  String get playlistEmptyState => 'Nessun brano ancora!';

  @override
  String get playlistAvailableOffline => 'Disponibile offline';

  @override
  String get playlistShuffle => 'Casuale';

  @override
  String get playlistMoreOptions => 'Altre opzioni';

  @override
  String get playlistNoMatchSearch =>
      'Nessuna playlist corrisponde alla ricerca';

  @override
  String get playlistCreateNew => 'Crea nuova playlist 😍';

  @override
  String get playlistCreateFirstOne =>
      'Nessuna playlist ancora. Creane una per iniziare!';

  @override
  String get addToPlaylistNoSongSelected => 'Nessun brano selezionato';

  @override
  String get createPlaylistDialogBarrierLabel =>
      'Finestra di creazione playlist';

  @override
  String get createPlaylistDialogNameHint => 'Vibe estive';

  @override
  String get createPlaylistDialogCreate => 'Crea';

  @override
  String playlistSongCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count brani',
      one: '1 brano',
    );
    return '$_temp0';
  }

  @override
  String playlistRemovedTrack(String title, String playlist) {
    return '$title rimosso da $playlist';
  }

  @override
  String get playlistFailedToLoad => 'Impossibile caricare la playlist';

  @override
  String get settingsTitle => 'Impostazioni';

  @override
  String get settingsPlugins => 'Plugin';

  @override
  String get settingsPluginsSubtitle => 'Installa, carica e gestisci i plugin.';

  @override
  String get settingsUpdates => 'Aggiornamenti';

  @override
  String get settingsUpdatesSubtitle => 'Controlla nuovi aggiornamenti';

  @override
  String get settingsDownloads => 'Download';

  @override
  String get settingsDownloadsSubtitle =>
      'Cartella di download, qualità di download e altro...';

  @override
  String get settingsLocalTracks => 'Brani locali';

  @override
  String get settingsLocalTracksSubtitle =>
      'Scansione, gestione delle cartelle e impostazioni di scansione automatica.';

  @override
  String get settingsPlayer => 'Impostazioni player';

  @override
  String get settingsPlayerSubtitle =>
      'Qualità dello streaming, riproduzione automatica, ecc.';

  @override
  String get settingsPluginDefaults => 'Impostazioni predefinite plugin';

  @override
  String get settingsPluginDefaultsSubtitle =>
      'Sorgente di Esplora, priorità dei resolver.';

  @override
  String get settingsUIElements => 'Elementi UI e servizi';

  @override
  String get settingsUIElementsSubtitle =>
      'Scorrimento automatico, modifiche UI ecc.';

  @override
  String get settingsLastFM => 'Impostazioni Last.FM';

  @override
  String get settingsLastFMSubtitle =>
      'Chiave API, segreto e impostazioni di scrobbling.';

  @override
  String get settingsStorage => 'Memoria';

  @override
  String get settingsStorageSubtitle =>
      'Backup, cache, cronologia, ripristino e altro...';

  @override
  String get settingsLanguageCountry => 'Lingua e paese';

  @override
  String get settingsLanguageCountrySubtitle =>
      'Seleziona la tua lingua e il tuo paese.';

  @override
  String get settingsAbout => 'Info';

  @override
  String get settingsAboutSubtitle =>
      'Info sull\'app, versione, sviluppatore, ecc.';

  @override
  String get settingsScanning => 'Scansione';

  @override
  String get settingsMusicFolders => 'Cartelle musicali';

  @override
  String get settingsQuality => 'Qualità';

  @override
  String get settingsHistory => 'Cronologia';

  @override
  String get settingsBackupRestore => 'Backup e ripristino';

  @override
  String get settingsAutomatic => 'Automatico';

  @override
  String get settingsDangerZone => 'Zona pericolosa';

  @override
  String get settingsScrobbling => 'Scrobbling';

  @override
  String get settingsAuthentication => 'Autenticazione';

  @override
  String get settingsHomeScreen => 'Schermata Home';

  @override
  String get settingsChartVisibility => 'Visibilità classifiche';

  @override
  String get settingsLocation => 'Posizione';

  @override
  String get pluginRepositoryTitle => 'Repository dei plugin';

  @override
  String get pluginRepositorySubtitle =>
      'Aggiungi una sorgente JSON per sfogliare i plugin remoti.';

  @override
  String get pluginRepositoryAddAction => 'Aggiungi repository';

  @override
  String get pluginRepositoryAddTitle => 'Aggiungi repository';

  @override
  String get pluginRepositoryAddSubtitle =>
      'Inserisci l\'URL di un file JSON valido di repository plugin.';

  @override
  String get pluginRepositoryEmpty => 'Nessun repository aggiunto.';

  @override
  String get pluginRepositoryUrlCopied =>
      'URL del repository copiato negli appunti';

  @override
  String get pluginRepositoryNoDescription => 'Nessuna descrizione fornita.';

  @override
  String get pluginRepositoryUnknownUpdate => 'Aggiornamento sconosciuto';

  @override
  String pluginRepositoryPluginsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plugin',
      one: '1 plugin',
    );
    return '$_temp0';
  }

  @override
  String get pluginRepositoryErrorLoad => 'Impossibile caricare i repository.';

  @override
  String get pluginRepositoryErrorInvalid =>
      'URL del repository o file del repository non valido.';

  @override
  String get pluginRepositoryErrorRemove =>
      'Impossibile rimuovere il repository.';

  @override
  String pluginRepositoryError(String message) {
    return 'Errore: $message';
  }

  @override
  String get dialogAddingToDownloadQueue => 'Aggiunta alla coda di download';

  @override
  String get emptyNoInternet => 'Nessuna connessione Internet!';

  @override
  String get emptyNoContentPlugin =>
      'Nessun plugin di contenuti caricato. Carica un Content Resolver in Gestione plugin.';

  @override
  String get emptyRefreshingSource =>
      'Aggiornamento della sorgente di Esplora... La sorgente precedente non è più disponibile.';

  @override
  String get emptyNoTracks => 'Nessun brano disponibile';

  @override
  String get emptyNoResults => 'Nessuna corrispondenza trovata';

  @override
  String snackbarDeletedTrack(String title) {
    return 'Eliminato \"$title\"';
  }

  @override
  String snackbarDeleteFailed(String title) {
    return 'Impossibile eliminare \"$title\"';
  }

  @override
  String get snackbarAddedToNextQueue => 'Aggiunto come prossimo in coda';

  @override
  String get snackbarAddedToQueue => 'Aggiunto alla coda';

  @override
  String snackbarAddedToLiked(String title) {
    return '$title aggiunto ai Mi piace!!';
  }

  @override
  String snackbarNowPlaying(String name) {
    return 'In riproduzione $name';
  }

  @override
  String snackbarPlaylistAddedToQueue(String name) {
    return 'Aggiunta alla coda: $name';
  }

  @override
  String get snackbarPlaylistQueued =>
      'Playlist aggiunta alla coda di download';

  @override
  String get snackbarPlaylistUpdated => 'Playlist aggiornata!';

  @override
  String get snackbarNoInternet => 'Nessuna connessione Internet.';

  @override
  String get snackbarImportFailed => 'Importazione non riuscita!';

  @override
  String get snackbarImportCompleted => 'Importazione completata';

  @override
  String get snackbarBackupFailed => 'Backup non riuscito!';

  @override
  String snackbarExportedTo(String path) {
    return 'Esportato in: $path';
  }

  @override
  String get snackbarMediaIdCopied => 'ID media copiato';

  @override
  String get snackbarLinkCopied => 'Link copiato';

  @override
  String get snackbarNoLinkAvailable => 'Nessun link disponibile';

  @override
  String get snackbarCouldNotOpenLink => 'Impossibile aprire il link';

  @override
  String snackbarPreparingDownload(String title) {
    return 'Preparazione del download di $title...';
  }

  @override
  String snackbarAlreadyDownloaded(String title) {
    return '$title è già scaricato.';
  }

  @override
  String snackbarAlreadyInQueue(String title) {
    return '$title è già in coda.';
  }

  @override
  String snackbarDownloaded(String title) {
    return 'Scaricato $title';
  }

  @override
  String get snackbarDownloadServiceUnavailable =>
      'Errore: servizio di download non disponibile.';

  @override
  String snackbarSongsAddedToQueue(int count) {
    return 'Aggiunti $count brani alla coda di download';
  }

  @override
  String get snackbarDeleteTrackFailDevice =>
      'Impossibile eliminare il brano dalla memoria del dispositivo.';

  @override
  String get searchHintExplore => 'Cosa vuoi ascoltare?';

  @override
  String get searchHintLibrary => 'Cerca in libreria...';

  @override
  String get searchHintOfflineMusic => 'Cerca tra i tuoi brani...';

  @override
  String get searchHintPlaylists => 'Cerca playlist...';

  @override
  String get searchStartTyping => 'Inizia a digitare per cercare...';

  @override
  String get searchNoSuggestions => 'Nessun suggerimento trovato!';

  @override
  String get searchNoResults =>
      'Nessun risultato trovato!\nProva un\'altra parola chiave o sorgente.';

  @override
  String get searchFailed => 'Ricerca non riuscita!';

  @override
  String get searchDiscover => 'Scopri musica fantastica...';

  @override
  String get searchSources => 'SORGENTI';

  @override
  String get searchNoPlugins => 'Nessun plugin installato';

  @override
  String get searchTracks => 'Brani';

  @override
  String get searchAlbums => 'Album';

  @override
  String get searchArtists => 'Artisti';

  @override
  String get searchPlaylists => 'Playlist';

  @override
  String get exploreDiscover => 'Esplora';

  @override
  String get exploreRecently => 'Di recente';

  @override
  String get exploreLastFmPicks => 'Consigli Last.Fm';

  @override
  String get exploreFailedToLoad =>
      'Impossibile caricare le sezioni della Home.';

  @override
  String get libraryTitle => 'Libreria';

  @override
  String get libraryEmptyState =>
      'La tua libreria è vuota. Aggiungi qualche brano per animarla!';

  @override
  String libraryIn(String playlistName) {
    return 'in $playlistName';
  }

  @override
  String get menuAddToPlaylist => 'Aggiungi a playlist';

  @override
  String get menuSmartReplace => 'Sostituzione intelligente';

  @override
  String get menuShare => 'Condividi';

  @override
  String get menuAvailableOffline => 'Disponibile offline';

  @override
  String get menuDownload => 'Scarica';

  @override
  String get menuOpenOriginalLink => 'Apri link originale';

  @override
  String get menuDeleteTrack => 'Elimina';

  @override
  String get songInfoTitle => 'Titolo';

  @override
  String get songInfoArtist => 'Artista';

  @override
  String get songInfoAlbum => 'Album';

  @override
  String get songInfoMediaId => 'ID media';

  @override
  String get songInfoCopyId => 'Copia ID';

  @override
  String get songInfoCopyLink => 'Copia link';

  @override
  String get songInfoOpenBrowser => 'Apri nel browser';

  @override
  String get tooltipRemoveFromLibrary => 'Rimuovi dalla libreria';

  @override
  String get tooltipSaveToLibrary => 'Salva in libreria';

  @override
  String get tooltipOpenOriginalLink => 'Apri link originale';

  @override
  String get tooltipShuffle => 'Casuale';

  @override
  String get tooltipAvailableOffline => 'Disponibile offline';

  @override
  String get tooltipDownloadPlaylist => 'Scarica playlist';

  @override
  String get tooltipMoreOptions => 'Altre opzioni';

  @override
  String get tooltipInfo => 'Info';

  @override
  String get appuiTitle => 'UI e servizi';

  @override
  String get appuiAutoSlideCharts => 'Scorrimento automatico classifiche';

  @override
  String get appuiAutoSlideChartsSubtitle =>
      'Fa scorrere automaticamente le classifiche nella schermata Home.';

  @override
  String get appuiLastFmPicksSubtitle =>
      'Mostra suggerimenti da Last.FM. Accesso e riavvio richiesti.';

  @override
  String get appuiNoChartsAvailable =>
      'Nessuna classifica disponibile. Carica un plugin di classifiche.';

  @override
  String get appuiLoginToLastFm => 'Accedi prima a Last.FM.';

  @override
  String get appuiShowInCarousel => 'Mostra nel carosello della Home.';

  @override
  String get countrySettingTitle => 'Paese e lingua';

  @override
  String get countrySettingAutoDetect => 'Rileva paese automaticamente';

  @override
  String get countrySettingAutoDetectSubtitle =>
      'Rileva automaticamente il tuo paese all\'apertura dell\'app.';

  @override
  String get countrySettingCountryLabel => 'Paese';

  @override
  String get countrySettingLanguageLabel => 'Lingua';

  @override
  String get countrySettingSystemDefault => 'Predefinito di sistema';

  @override
  String get downloadSettingTitle => 'Download';

  @override
  String get downloadSettingQuality => 'Qualità download';

  @override
  String get downloadSettingQualitySubtitle =>
      'Preferenza universale di qualità audio per i brani scaricati.';

  @override
  String get downloadSettingFolder => 'Cartella di download';

  @override
  String get downloadSettingResetFolder => 'Ripristina cartella di download';

  @override
  String get downloadSettingResetFolderSubtitle =>
      'Ripristina il percorso di download predefinito.';

  @override
  String get lastfmTitle => 'Last.FM';

  @override
  String get lastfmScrobbleTracks => 'Scrobbling dei brani';

  @override
  String get lastfmScrobbleTracksSubtitle =>
      'Invia i brani riprodotti al tuo profilo Last.FM.';

  @override
  String get lastfmAuthFirst => 'Autentica prima l\'API di Last.FM.';

  @override
  String get lastfmAuthenticatedAs => 'Autenticato come';

  @override
  String get lastfmAuthFailed => 'Autenticazione non riuscita:';

  @override
  String get lastfmNotAuthenticated => 'Non autenticato';

  @override
  String get lastfmSteps =>
      'Passaggi per l\'autenticazione:\n1. Crea o accedi a un account Last.FM su last.fm\n2. Genera una chiave API su last.fm/api/account/create\n3. Inserisci qui sotto la tua chiave API e il segreto\n4. Tocca \"Avvia autenticazione\" e approva nel browser\n5. Tocca \"Ottieni e salva chiave di sessione\" per completare';

  @override
  String get lastfmApiKey => 'Chiave API';

  @override
  String get lastfmApiSecret => 'Segreto API';

  @override
  String get lastfmStartAuth => '1. Avvia autenticazione';

  @override
  String get lastfmGetSession => '2. Ottieni e salva chiave di sessione';

  @override
  String get lastfmRemoveKeys => 'Rimuovi chiavi';

  @override
  String get lastfmStartAuthFirst =>
      'Avvia prima l\'autenticazione, poi approva nel browser.';

  @override
  String get localSettingTitle => 'Brani locali';

  @override
  String get localSettingAutoScan => 'Scansione automatica all\'avvio';

  @override
  String get localSettingAutoScanSubtitle =>
      'Cerca automaticamente nuovi brani locali all\'avvio dell\'app.';

  @override
  String get localSettingLastScan => 'Ultima scansione';

  @override
  String get localSettingNeverScanned => 'Mai';

  @override
  String get localSettingScanInProgress => 'Scansione in corso…';

  @override
  String get localSettingScanNowSubtitle =>
      'Avvia manualmente una scansione completa della libreria.';

  @override
  String get localSettingNoFolders =>
      'Nessuna cartella aggiunta. Aggiungi una cartella per iniziare la scansione.';

  @override
  String get localSettingAddFolder => 'Aggiungi cartella';

  @override
  String get playerSettingTitle => 'Impostazioni player';

  @override
  String get playerSettingStreamingHeader => 'Streaming';

  @override
  String get playerSettingStreamQuality => 'Qualità streaming';

  @override
  String get playerSettingStreamQualitySubtitle =>
      'Bitrate audio globale per la riproduzione online.';

  @override
  String get playerSettingQualityLow => 'Bassa';

  @override
  String get playerSettingQualityMedium => 'Media';

  @override
  String get playerSettingQualityHigh => 'Alta';

  @override
  String get playerSettingPlaybackHeader => 'Riproduzione';

  @override
  String get playerSettingAutoPlay => 'Riproduzione automatica';

  @override
  String get playerSettingAutoPlaySubtitle =>
      'Accoda brani simili quando la coda finisce.';

  @override
  String get playerSettingAutoFallback => 'Riproduzione di ripiego automatica';

  @override
  String get playerSettingAutoFallbackSubtitle =>
      'Se un plugin manca o non restituisce flussi, prova un resolver compatibile solo per la riproduzione.';

  @override
  String get playerSettingCrossfade => 'Dissolvenza incrociata';

  @override
  String get playerSettingCrossfadeOff => 'Disattivata';

  @override
  String get playerSettingCrossfadeInstant =>
      'I brani cambiano istantaneamente';

  @override
  String playerSettingCrossfadeBlend(int seconds) {
    return 'Miscelazione di $seconds s tra i brani';
  }

  @override
  String get playerSettingEqualizer => 'Equalizzatore';

  @override
  String get playerSettingEqualizerActive => 'Attivo';

  @override
  String playerSettingEqualizerActivePreset(String preset) {
    return 'Attivo — preset $preset';
  }

  @override
  String get playerSettingEqualizerSubtitle =>
      'EQ parametrico a 10 bande tramite FFmpeg.';

  @override
  String get pluginDefaultsTitle => 'Impostazioni predefinite plugin';

  @override
  String get pluginDefaultsDiscoverHeader => 'Sorgente di Esplora';

  @override
  String get pluginDefaultsNoResolver =>
      'Nessun resolver di contenuti caricato. Carica un plugin per scegliere una sorgente di Esplora.';

  @override
  String get pluginDefaultsAutomaticSubtitle =>
      'Usa il primo resolver di contenuti disponibile.';

  @override
  String get pluginDefaultsPriorityHeader => 'Priorità dei resolver';

  @override
  String get pluginDefaultsNoPriority =>
      'Nessun resolver di contenuti caricato. L\'ordine di priorità apparirà qui dopo il caricamento dei plugin.';

  @override
  String get pluginDefaultsPriorityDesc =>
      'Trascina per riordinare (col telecomando: OK porta in cima). I resolver con priorità più alta vengono provati per primi quando si risolvono elementi di classifica o brani importati in brani riproducibili.';

  @override
  String get pluginDefaultsLyricsHeader => 'Priorità dei testi';

  @override
  String get pluginDefaultsLyricsNone => 'Nessun provider di testi caricato.';

  @override
  String get pluginDefaultsLyricsDesc =>
      'Trascina per riordinare i provider di testi (col telecomando: OK porta in cima). Il primo provider viene provato per primo.';

  @override
  String get pluginDefaultsSuggestionsHeader => 'Suggerimenti di ricerca';

  @override
  String get pluginDefaultsSuggestionsNone =>
      'Nessun provider di suggerimenti caricato.';

  @override
  String get pluginDefaultsSuggestionsHistoryOnlyTitle => 'Nessuno';

  @override
  String get pluginDefaultsSuggestionsHistoryOnlySubtitle =>
      'Usa solo la cronologia di ricerca.';

  @override
  String get storageSettingTitle => 'Memoria';

  @override
  String get storageClearHistoryEvery => 'Cancella cronologia ogni';

  @override
  String get storageClearHistorySubtitle =>
      'Cancella la cronologia di ascolto dopo il periodo scelto.';

  @override
  String storageDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni',
      one: '1 giorno',
    );
    return '$_temp0';
  }

  @override
  String get storageBackupLocation => 'Posizione del backup';

  @override
  String get storageBackupLocationAndroid => 'Cartella Download / dati app';

  @override
  String get storageBackupLocationDownloads => 'Cartella Download';

  @override
  String get storageCreateBackup => 'Crea backup';

  @override
  String get storageCreateBackupSubtitle =>
      'Salva impostazioni e dati in un file di backup.';

  @override
  String storageBackupCreatedAt(String path) {
    return 'Backup creato in $path';
  }

  @override
  String storageBackupShareFailed(String error) {
    return 'Condivisione del backup non riuscita: $error';
  }

  @override
  String get storageBackupFailed => 'Backup non riuscito!';

  @override
  String get storageRestoreBackup => 'Ripristina backup';

  @override
  String get storageRestoreBackupSubtitle =>
      'Ripristina impostazioni e dati da un file di backup.';

  @override
  String get storageAutoBackup => 'Backup automatico';

  @override
  String get storageAutoBackupSubtitle =>
      'Crea periodicamente un backup automatico dei tuoi dati.';

  @override
  String get storageAutoLyrics => 'Salva automaticamente i testi';

  @override
  String get storageAutoLyricsSubtitle =>
      'Salva i testi automaticamente quando un brano viene riprodotto.';

  @override
  String get storageResetApp => 'Ripristina app Bloomee';

  @override
  String get storageResetAppSubtitle =>
      'Elimina tutti i dati e riporta l\'app allo stato predefinito.';

  @override
  String get storageResetConfirmTitle => 'Conferma ripristino';

  @override
  String get storageResetConfirmMessage =>
      'Vuoi davvero ripristinare Bloomee? Verranno eliminati tutti i tuoi dati e l\'operazione non può essere annullata.';

  @override
  String get storageResetButton => 'Ripristina';

  @override
  String get storageResetSuccess =>
      'L\'app è stata riportata allo stato predefinito.';

  @override
  String get storageLocationDialogTitle => 'Posizione del backup';

  @override
  String get storageLocationAndroid =>
      'I backup sono salvati in:\n\n1. Cartella Download\n2. Android/data/ls.bloomee.musicplayer/data\n\nCopia il file da una delle due posizioni.';

  @override
  String get storageLocationOther =>
      'I backup sono salvati nella cartella Download. Copia il file da lì.';

  @override
  String get storageRestoreOptionsTitle => 'Opzioni di ripristino';

  @override
  String get storageRestoreOptionsDesc =>
      'Scegli quali dati ripristinare dal file di backup selezionato. Deseleziona le voci che NON vuoi importare. Per impostazione predefinita sono tutte selezionate.';

  @override
  String get storageRestoreSelectAll => 'Seleziona tutto';

  @override
  String get storageRestoreMediaItems =>
      'Elementi multimediali (brani, tracce, voci di libreria)';

  @override
  String get storageRestoreSearchHistory => 'Cronologia di ricerca';

  @override
  String get storageRestoreContinue => 'Continua';

  @override
  String get storageRestoreNoFile => 'Nessun file selezionato.';

  @override
  String get storageRestoreSaveFailed =>
      'Impossibile salvare il file selezionato.';

  @override
  String get storageRestoreConfirmTitle => 'Conferma ripristino';

  @override
  String get storageRestoreConfirmPrefix =>
      'Questa operazione sovrascriverà e unirà le parti selezionate nell\'app con i dati del file di backup:';

  @override
  String get storageRestoreConfirmSuffix =>
      'I tuoi dati attuali verranno modificati o uniti. Vuoi davvero procedere?';

  @override
  String get storageRestoreYes => 'Sì, ripristina';

  @override
  String get storageRestoreNo => 'No';

  @override
  String get storageRestoring =>
      'Ripristino dei dati selezionati…\nAttendi il completamento dell\'operazione.';

  @override
  String get storageRestoreMediaBullet => '• Elementi multimediali';

  @override
  String get storageRestoreHistoryBullet => '• Cronologia di ricerca';

  @override
  String get storageUnexpectedError =>
      'Si è verificato un errore imprevisto durante il ripristino.';

  @override
  String get storageRestoreCompleted => 'Ripristino completato';

  @override
  String get storageRestoreFailedTitle => 'Ripristino non riuscito';

  @override
  String get storageRestoreSuccessMessage =>
      'I dati selezionati sono stati ripristinati con successo. Per risultati migliori, riavvia ora l\'app.';

  @override
  String get storageRestoreFailedMessage =>
      'Il ripristino non è riuscito con i seguenti errori:';

  @override
  String get storageRestoreUnknownError =>
      'Errore sconosciuto durante il ripristino.';

  @override
  String get storageRestoreRestartHint =>
      'Riavvia l\'app per una maggiore coerenza.';

  @override
  String get updateSettingTitle => 'Aggiornamenti';

  @override
  String get updateAppUpdatesHeader => 'Aggiornamenti app';

  @override
  String get updateCheckForUpdates => 'Controlla aggiornamenti';

  @override
  String get updateCheckSubtitle =>
      'Verifica se è disponibile una versione più recente di Bloomee.';

  @override
  String get updateAutoNotify => 'Notifica automatica aggiornamenti';

  @override
  String get updateAutoNotifySubtitle =>
      'Ricevi una notifica all\'avvio dell\'app quando sono disponibili aggiornamenti.';

  @override
  String get updateCheckTitle => 'Controlla aggiornamenti';

  @override
  String get updateUpToDate => 'Bloomee🌸 è aggiornato!!!';

  @override
  String get updateViewPreRelease => 'Vedi ultima pre-release';

  @override
  String updateCurrentVersion(String curr, String build) {
    return 'Versione attuale: $curr + $build';
  }

  @override
  String get updateNewVersionAvailable =>
      'È ora disponibile una nuova versione di Bloomee🌸!!';

  @override
  String updateVersion(String ver, String build) {
    return 'Versione: $ver+$build';
  }

  @override
  String get updateDownloadNow => 'Scarica ora';

  @override
  String get updateChecking =>
      'Verifica della disponibilità di una versione più recente in corso!';

  @override
  String get timerTitle => 'Timer di spegnimento';

  @override
  String get timerInterludeMessage =>
      'Preparazione di un tranquillo intermezzo tra…';

  @override
  String get timerHours => 'Ore';

  @override
  String get timerMinutes => 'Minuti';

  @override
  String get timerSeconds => 'Secondi';

  @override
  String get timerStop => 'Ferma timer';

  @override
  String get timerFinishedMessage => 'I brani si sono riposati. Buonanotte 🥰.';

  @override
  String get timerGotIt => 'Ok!';

  @override
  String get timerSetTimeError => 'Imposta un orario';

  @override
  String get timerStart => 'Avvia timer';

  @override
  String get notificationsTitle => 'Notifiche';

  @override
  String get notificationsEmpty => 'Nessuna notifica ancora!';

  @override
  String get recentsTitle => 'Cronologia';

  @override
  String playlistByCreator(String creator) {
    return 'di $creator';
  }

  @override
  String get playlistTypeAlbum => 'Album';

  @override
  String get playlistTypePlaylist => 'Playlist';

  @override
  String get playlistYou => 'Tu';

  @override
  String get pluginManagerTitle => 'Plugin';

  @override
  String get pluginManagerEmpty =>
      'Nessun plugin installato.\nTocca + per aggiungere un file .bex.';

  @override
  String get pluginManagerFilterAll => 'Tutti';

  @override
  String get pluginManagerFilterContent => 'Resolver di contenuti';

  @override
  String get pluginManagerFilterCharts => 'Provider di classifiche';

  @override
  String get pluginManagerFilterLyrics => 'Provider di testi';

  @override
  String get pluginManagerFilterSuggestions => 'Provider di suggerimenti';

  @override
  String get pluginManagerFilterImporters => 'Importatori di contenuti';

  @override
  String get pluginManagerTooltipRefresh => 'Aggiorna';

  @override
  String get pluginManagerTooltipInstall => 'Installa plugin';

  @override
  String get pluginManagerNoMatch =>
      'Nessun plugin corrisponde a questo filtro';

  @override
  String pluginManagerPickFailed(String error) {
    return 'Selezione del file non riuscita: $error';
  }

  @override
  String get pluginManagerInstalling => 'Installazione del plugin...';

  @override
  String get pluginManagerTypeContentResolver => 'Resolver di contenuti';

  @override
  String get pluginManagerTypeChartProvider => 'Provider di classifiche';

  @override
  String get pluginManagerTypeLyricsProvider => 'Provider di testi';

  @override
  String get pluginManagerTypeSuggestionProvider => 'Suggerimenti di ricerca';

  @override
  String get pluginManagerTypeContentImporter => 'Importatore di contenuti';

  @override
  String get pluginManagerDeleteTitle => 'Eliminare il plugin?';

  @override
  String pluginManagerDeleteMessage(String name) {
    return 'Vuoi davvero eliminare \"$name\"? I suoi file verranno rimossi in modo definitivo.';
  }

  @override
  String get pluginManagerDeleteAction => 'Elimina';

  @override
  String get pluginManagerCancel => 'Annulla';

  @override
  String get pluginManagerEnablePlugin => 'Attiva plugin';

  @override
  String get pluginManagerUnloadPlugin => 'Scarica plugin';

  @override
  String get pluginManagerDeleting => 'Eliminazione...';

  @override
  String get pluginManagerApiKeysTitle => 'Chiavi API';

  @override
  String get pluginManagerApiKeysSaved => 'Chiavi API salvate';

  @override
  String get pluginManagerSave => 'Salva';

  @override
  String get pluginManagerDetailVersion => 'Versione';

  @override
  String get pluginManagerDetailType => 'Tipo';

  @override
  String get pluginManagerDetailPublisher => 'Editore';

  @override
  String get pluginManagerDetailLastUpdated => 'Ultimo aggiornamento';

  @override
  String get pluginManagerDetailCreated => 'Creato il';

  @override
  String get pluginManagerDetailHomepage => 'Sito web';

  @override
  String get pluginManagerDowngradeTitle => 'Eseguire il downgrade del plugin?';

  @override
  String pluginManagerDowngradeMessage(String name) {
    return 'Stai installando una versione uguale o precedente di \"$name\". Continuare?';
  }

  @override
  String get pluginManagerDowngradeAction => 'Installa comunque';

  @override
  String get pluginManagerDeleteStorageTitle => 'Eliminare i dati del plugin?';

  @override
  String pluginManagerDeleteStorageMessage(String name) {
    return 'Vuoi rimuovere anche le chiavi API e le impostazioni salvate per \"$name\"?';
  }

  @override
  String get pluginManagerDeleteStorageKeep => 'Mantieni dati';

  @override
  String get pluginManagerDeleteStorageRemove => 'Rimuovi dati';

  @override
  String get segmentsSheetTitle => 'Segmenti';

  @override
  String get segmentsSheetEmpty => 'Nessun segmento disponibile';

  @override
  String get segmentsSheetUntitled => 'Segmento senza titolo';

  @override
  String get smartReplaceTitle => 'Sostituzione intelligente';

  @override
  String smartReplaceSubtitle(String title) {
    return 'Scegli un sostituto riproducibile per \"$title\" e aggiorna i riferimenti salvati nelle playlist.';
  }

  @override
  String get smartReplaceClose => 'Chiudi';

  @override
  String get smartReplaceNoMatch => 'Nessun sostituto trovato';

  @override
  String get smartReplaceNoMatchSubtitle =>
      'Nessuno dei plugin resolver caricati ha restituito una corrispondenza sufficientemente valida.';

  @override
  String get smartReplaceBestMatch => 'Migliore corrispondenza';

  @override
  String get smartReplaceSearchFailed => 'Ricerca non riuscita';

  @override
  String smartReplaceApplyFailed(String error) {
    return 'Sostituzione intelligente non riuscita: $error';
  }

  @override
  String smartReplaceApplied(String queue) {
    return 'Sostituzione applicata$queue.';
  }

  @override
  String smartReplaceAppliedPlaylists(int count, String plural, String queue) {
    return 'Sostituito in $count playlist$plural$queue.';
  }

  @override
  String get smartReplaceQueueUpdated => ' e coda aggiornata';

  @override
  String get playerUnknownQueue => 'Sconosciuto';

  @override
  String playerLiked(String title) {
    return '$title aggiunto ai Mi piace!!';
  }

  @override
  String playerUnliked(String title) {
    return '$title rimosso dai Mi piace!!';
  }

  @override
  String get offlineNoDownloads => 'Nessun download';

  @override
  String get offlineTitle => 'Scaricati';

  @override
  String get offlineSearchHint => 'Cerca tra i tuoi brani...';

  @override
  String get offlineRefreshTooltip => 'Aggiorna download';

  @override
  String get offlineCloseSearch => 'Chiudi ricerca';

  @override
  String get offlineSearchTooltip => 'Cerca';

  @override
  String get offlineOpenFailed =>
      'Impossibile aprire questo brano offline. Prova ad aggiornare i download.';

  @override
  String get offlinePlayFailed =>
      'Impossibile riprodurre questo brano offline. Riprova.';

  @override
  String albumViewTrackCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count brani',
      one: '1 brano',
    );
    return '$_temp0';
  }

  @override
  String get albumViewLoadFailed => 'Impossibile caricare l\'album';

  @override
  String get aboutCraftingSubtitle => 'Creare sinfonie nel codice.';

  @override
  String get aboutFollowGitHub => 'Seguilo su GitHub';

  @override
  String get aboutSendInquiry => 'Invia una richiesta commerciale';

  @override
  String get aboutCreativeHighlights => 'Aggiornamenti e novità creative';

  @override
  String get aboutTipQuote =>
      'Ti piace Bloomee? Una piccola offerta lo mantiene in fiore. 🌸';

  @override
  String get aboutTipButton => 'Ti aiuto';

  @override
  String get aboutTipDesc => 'Voglio che Bloomee continui a migliorare.';

  @override
  String get aboutGitHub => 'GitHub';

  @override
  String get songInfoSectionDetails => 'Dettagli brano';

  @override
  String get songInfoSectionTechnical => 'Info tecniche';

  @override
  String get songInfoSectionActions => 'Azioni';

  @override
  String get songInfoLabelTitle => 'Titolo';

  @override
  String get songInfoLabelArtist => 'Artista';

  @override
  String get songInfoLabelAlbum => 'Album';

  @override
  String get songInfoLabelDuration => 'Durata';

  @override
  String get songInfoLabelSource => 'Sorgente';

  @override
  String get songInfoLabelMediaId => 'ID media';

  @override
  String get songInfoLabelPluginId => 'ID plugin';

  @override
  String get songInfoIdCopied => 'ID media copiato';

  @override
  String get songInfoLinkCopied => 'Link copiato';

  @override
  String get songInfoNoLink => 'Nessun link disponibile';

  @override
  String get songInfoOpenFailed => 'Impossibile aprire il link';

  @override
  String get songInfoUpdateMetadata => 'Ottieni metadati aggiornati';

  @override
  String get songInfoMetadataUpdated => 'Metadati aggiornati';

  @override
  String get songInfoMetadataUpdateFailed =>
      'Impossibile aggiornare i metadati';

  @override
  String get songInfoMetadataUnavailable =>
      'L\'aggiornamento dei metadati non è disponibile per questa sorgente';

  @override
  String get songInfoSearchTitle => 'Cerca questo brano in Bloomee';

  @override
  String get songInfoSearchArtist => 'Cerca questo artista in Bloomee';

  @override
  String get songInfoSearchAlbum => 'Cerca questo album in Bloomee';

  @override
  String get eqTitle => 'Equalizzatore';

  @override
  String get eqResetTooltip => 'Ripristina piatto';

  @override
  String get chartNoItems => 'Nessun elemento in questa classifica';

  @override
  String get chartLoadFailed => 'Impossibile caricare la classifica';

  @override
  String get chartPlay => 'Riproduci';

  @override
  String get chartResolving => 'Risoluzione in corso';

  @override
  String get chartReady => 'Pronto';

  @override
  String get chartAddToPlaylist => 'Aggiungi a playlist';

  @override
  String get chartNoResolver =>
      'Nessun resolver di contenuti caricato. Installa un plugin per riprodurre.';

  @override
  String get chartResolveFailed => 'Impossibile risolvere. Ricerca in corso...';

  @override
  String get chartNoResolverAdd => 'Nessun resolver di contenuti caricato.';

  @override
  String get chartNoMatch =>
      'Nessuna corrispondenza trovata. Prova a cercare manualmente.';

  @override
  String get chartStatPeak => 'Picco';

  @override
  String get chartStatWeeks => 'Settimane';

  @override
  String get chartStatChange => 'Variazione';

  @override
  String menuSharePreparing(String title) {
    return 'Preparazione di $title per la condivisione.';
  }

  @override
  String get menuOpenLinkFailed => 'Impossibile aprire il link';

  @override
  String get localMusicFolders => 'Cartelle musicali';

  @override
  String get localMusicCloseSearch => 'Chiudi ricerca';

  @override
  String get localMusicOpenSearch => 'Cerca';

  @override
  String get localMusicNoMusicFound => 'Nessuna musica locale trovata';

  @override
  String get localMusicNoSearchResults =>
      'Nessun brano corrisponde alla ricerca.';

  @override
  String get importSongsTitle => 'Importa brani';

  @override
  String get importNoPluginsLoaded =>
      'Nessun plugin di importazione di contenuti caricato.\nInstalla un plugin di importazione per importare playlist da servizi esterni.';

  @override
  String get importBloomeeFiles => 'Importa file Bloomee';

  @override
  String get importM3UFiles => 'Importa playlist M3U';

  @override
  String get importM3UNameDialogTitle => 'Nome playlist';

  @override
  String get importM3UNameHint => 'Inserisci un nome per questa playlist';

  @override
  String get importM3UNoTracks => 'Nessun brano valido trovato nel file M3U.';

  @override
  String get importNoteTitle => 'Nota';

  @override
  String get importNoteMessage =>
      'Puoi importare solo file creati da Bloomee.\nSe il file proviene da un\'altra fonte, non funzionerà. Continuare comunque?';

  @override
  String get importTitle => 'Importa';

  @override
  String get importCheckingUrl => 'Verifica URL...';

  @override
  String get importFetchingTracks => 'Recupero brani...';

  @override
  String get importSavingToLibrary => 'Salvataggio in libreria...';

  @override
  String get importPasteUrlHint =>
      'Incolla l\'URL di una playlist o di un album da importare';

  @override
  String get importAction => 'Importa';

  @override
  String importTrackCount(int count) {
    return '$count brani';
  }

  @override
  String get importResolving => 'Risoluzione in corso...';

  @override
  String importResolvingProgress(int done, int total) {
    return 'Risoluzione brani: $done / $total';
  }

  @override
  String get importReviewTitle => 'Revisione importazione';

  @override
  String importReviewSummary(int resolved, int failed, int total) {
    return '$resolved risolti, $failed non riusciti su $total';
  }

  @override
  String importSaveTracks(int count) {
    return 'Salva $count brani';
  }

  @override
  String importTracksSaved(int count) {
    return '$count brani salvati!';
  }

  @override
  String get importDone => 'Fatto';

  @override
  String get importMore => 'Importa altro';

  @override
  String get importUnknownError => 'Errore sconosciuto';

  @override
  String get importTryAgain => 'Riprova';

  @override
  String get importSkipTrack => 'Salta questo brano';

  @override
  String get importMatchOptions => 'Opzioni di corrispondenza';

  @override
  String get importAutoMatched => 'Abbinato automaticamente';

  @override
  String get importUserSelected => 'Selezionato';

  @override
  String get importSkipped => 'Saltato';

  @override
  String get importNoMatch => 'Nessuna corrispondenza trovata';

  @override
  String get importReorderTip =>
      'Tieni premuta una playlist per iniziare a riordinare';

  @override
  String get importErrorCannotHandleUrl =>
      'Questo plugin non può gestire l\'URL fornito.';

  @override
  String get importErrorUnexpectedResponse => 'Risposta inattesa dal plugin.';

  @override
  String importErrorFailedToCheck(String error) {
    return 'Verifica dell\'URL non riuscita: $error';
  }

  @override
  String importErrorFailedToFetchInfo(String error) {
    return 'Recupero delle informazioni sulla raccolta non riuscito: $error';
  }

  @override
  String importErrorFailedToFetchTracks(String error) {
    return 'Recupero dei brani non riuscito: $error';
  }

  @override
  String importErrorFailedToSave(String error) {
    return 'Salvataggio della playlist non riuscito: $error';
  }

  @override
  String get playlistPinToTop => 'Fissa in alto';

  @override
  String get playlistUnpin => 'Rimuovi da fissati';

  @override
  String get snackbarImportingMedia =>
      'Importazione degli elementi multimediali..';

  @override
  String get snackbarPlaylistSaved => 'Playlist salvata in libreria!';

  @override
  String get snackbarInvalidFileFormat => 'Formato file non valido';

  @override
  String get snackbarMediaItemImported => 'Elemento multimediale importato';

  @override
  String get snackbarPlaylistImported => 'Playlist importata';

  @override
  String get snackbarOpenImportForUrl =>
      'Apri la schermata Importa in Libreria per importare da questo URL.';

  @override
  String get snackbarProcessingFile => 'Elaborazione del file...';

  @override
  String snackbarPreparingShare(String title) {
    return 'Preparazione di $title per la condivisione';
  }

  @override
  String snackbarPreparingExport(String title) {
    return 'Preparazione di $title per l\'esportazione.';
  }

  @override
  String get pluginManagerTabInstalled => 'Installati';

  @override
  String get pluginManagerTabStore => 'Store plugin';

  @override
  String get pluginManagerSelectPackage => 'Seleziona pacchetto plugin (.bex)';

  @override
  String get pluginManagerOutdatedManifest =>
      'Il plugin usa una versione obsoleta del manifest. Alcune funzioni potrebbero non funzionare. Valuta un aggiornamento.';

  @override
  String get pluginManagerStatusActive => 'Attivo';

  @override
  String get pluginManagerStatusInactive => 'Inattivo';

  @override
  String pluginRepositoryUpdatedOn(String date) {
    return 'Aggiornato il $date';
  }

  @override
  String pluginRepositoryAvailableCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count plugin disponibili',
      one: '1 plugin disponibile',
    );
    return '$_temp0';
  }

  @override
  String get pluginRepositoryOutdatedManifest =>
      'Manifest obsoleto. Alcune funzioni potrebbero non funzionare.';

  @override
  String get pluginRepositoryUnknownPublisher => 'Editore sconosciuto';

  @override
  String get pluginRepositoryActionRetry => 'Riprova';

  @override
  String get pluginRepositoryActionOutdated => 'Obsoleto';

  @override
  String get pluginRepositoryActionInstalled => 'Installato';

  @override
  String get pluginRepositoryActionInstall => 'Installa';

  @override
  String get pluginRepositoryActionUnavailable => 'Non disponibile';

  @override
  String get pluginRepositoryInstallFailed => 'Installazione non riuscita.';

  @override
  String pluginRepositoryDownloadFailed(String name) {
    return 'Download di $name non riuscito.';
  }

  @override
  String smartReplaceAppliedPlaylistsSummary(int count, String queue) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sostituito in $count playlist$queue.',
      one: 'Sostituito in 1 playlist$queue.',
    );
    return '$_temp0';
  }

  @override
  String get lyricsSearchFieldLabel => 'Cerca testi...';

  @override
  String get lyricsSearchEmptyPrompt =>
      'Digita un brano o un artista per trovare i testi.';

  @override
  String lyricsSearchNoResults(String query) {
    return 'Nessun testo trovato per \"$query\"';
  }

  @override
  String get lyricsSearchApplied => 'Testi applicati con successo';

  @override
  String get lyricsSearchFetchFailed => 'Impossibile recuperare i testi';

  @override
  String get lyricsSearchPreview => 'Anteprima';

  @override
  String get lyricsSearchPreviewTooltip => 'Anteprima testi';

  @override
  String get lyricsSearchSynced => 'SINCRONIZZATI';

  @override
  String get lyricsSearchPreviewLoadFailed => 'Impossibile caricare i testi.';

  @override
  String get lyricsSearchApplyAction => 'Applica testi';

  @override
  String get lyricsSettingsSearchTitle => 'Cerca testi personalizzati';

  @override
  String get lyricsSettingsSearchSubtitle =>
      'Trova versioni alternative online';

  @override
  String get lyricsSettingsSyncTitle =>
      'Regola sincronizzazione (ritardo/offset)';

  @override
  String get lyricsSettingsSyncSubtitle =>
      'Correggi testi troppo veloci o troppo lenti';

  @override
  String get lyricsSettingsSaveTitle => 'Salva offline';

  @override
  String get lyricsSettingsSaveSubtitle =>
      'Conserva questi testi sul dispositivo';

  @override
  String get lyricsSettingsDeleteTitle => 'Elimina testi salvati';

  @override
  String get lyricsSettingsDeleteSubtitle => 'Rimuovi i testi offline';

  @override
  String get lyricsSyncTapToReset => 'Tocca per ripristinare';

  @override
  String get upNextTitle => 'Prossimi';

  @override
  String upNextItemsInQueue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count elementi in coda',
      one: '1 elemento in coda',
    );
    return '$_temp0';
  }

  @override
  String get upNextAutoPlay => 'Riproduzione automatica';

  @override
  String get tooltipCopyToClipboard => 'Copia negli appunti';

  @override
  String get snackbarCopiedToClipboard => 'Copiato negli appunti';

  @override
  String get tooltipSongInfo => 'Info brano';

  @override
  String get snackbarCannotDeletePlayingSong =>
      'Impossibile eliminare il brano in riproduzione';

  @override
  String get playerLoopOff => 'Disattivato';

  @override
  String get playerLoopOne => 'Ripeti uno';

  @override
  String get playerLoopAll => 'Ripeti tutto';

  @override
  String get snackbarOpeningAlbumPage =>
      'Apertura della pagina dell\'album originale.';

  @override
  String updateAvailableBody(String ver, String build) {
    return 'È disponibile una nuova versione di Bloomee🌸!\n\nVersione: $ver+$build';
  }

  @override
  String pluginSnackbarInstalled(String id) {
    return 'Plugin \"$id\" installato con successo';
  }

  @override
  String pluginSnackbarLoaded(String id) {
    return 'Plugin \"$id\" caricato';
  }

  @override
  String pluginSnackbarDeleted(String id) {
    return 'Plugin \"$id\" eliminato con successo';
  }

  @override
  String get pluginBootstrapTitle => 'Configurazione di Bloomee TV';

  @override
  String pluginBootstrapProgress(int percent) {
    return 'Configurazione del nuovo motore plugin... $percent%';
  }

  @override
  String get pluginBootstrapHint => 'Accade solo una volta.';

  @override
  String get pluginBootstrapErrorTitle => 'Connessione troppo lenta';

  @override
  String get pluginBootstrapErrorBody =>
      'Alcuni plugin non è stato possibile installarli. Puoi comunque usare Bloomee — i plugin verranno riprovati al prossimo avvio.';

  @override
  String get pluginBootstrapContinue => 'Continua comunque';
}
