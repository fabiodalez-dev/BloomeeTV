import 'package:Bloomee/tv/services/tv_remote_server.dart';
import 'package:Bloomee/tv/services/tv_remote_player.dart';
import 'package:Bloomee/tv/services/tv_image_privacy.dart';
import 'package:Bloomee/tv/services/tv_operations.dart';
import 'package:Bloomee/tv/services/tv_cast_service.dart';
import 'dart:async';
import 'dart:io' as io;
import 'package:Bloomee/tv/services/tv_workspace.dart';
import 'package:Bloomee/tv/services/tv_catalog_cache.dart';
import 'package:Bloomee/tv/services/tv_pairing_server.dart';
import 'package:Bloomee/tv/services/tv_diagnostics.dart';
import 'package:Bloomee/blocs/downloader/cubit/downloader_cubit.dart';
import 'package:Bloomee/blocs/global_events/global_events_cubit.dart';
import 'package:Bloomee/blocs/internet_connectivity/cubit/connectivity_cubit.dart';
import 'package:Bloomee/blocs/lastdotfm/lastdotfm_cubit.dart';
import 'package:Bloomee/blocs/local_music/cubit/local_music_cubit.dart';
import 'package:Bloomee/blocs/lyrics/lyrics_cubit.dart';
import 'package:Bloomee/blocs/mini_player/mini_player_cubit.dart';
import 'package:Bloomee/blocs/notification/notification_cubit.dart';
import 'package:Bloomee/blocs/history/cubit/history_cubit.dart';
import 'package:Bloomee/blocs/explore/cubit/recently_cubit.dart';
import 'package:Bloomee/blocs/player_overlay/player_overlay_cubit.dart';
import 'package:Bloomee/blocs/search_suggestions/search_suggestion_bloc.dart';
import 'package:Bloomee/blocs/settings_cubit/cubit/settings_cubit.dart';
import 'package:Bloomee/plugins/blocs/plugin/plugin_bloc.dart';
import 'package:Bloomee/plugins/blocs/plugin/plugin_event.dart';
import 'package:Bloomee/repository/bloomee/download_repository.dart';
import 'package:Bloomee/repository/bloomee/settings_repository.dart';
import 'package:Bloomee/services/db/dao/cache_dao.dart';
import 'package:Bloomee/services/db/dao/download_dao.dart';
import 'package:Bloomee/services/db/dao/history_dao.dart';
import 'package:Bloomee/services/db/dao/lyrics_dao.dart';
import 'package:Bloomee/services/db/dao/notification_dao.dart';
import 'package:Bloomee/services/db/dao/library_dao.dart';
import 'package:Bloomee/services/db/dao/playlist_dao.dart';
import 'package:Bloomee/services/db/dao/search_history_dao.dart';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/services/db/dao/track_dao.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:Bloomee/blocs/timer/timer_bloc.dart';
import 'package:Bloomee/screens/widgets/global_event_listener.dart';
import 'package:Bloomee/screens/widgets/shortcut_indicator_overlay.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/services/bootstrap.dart';
import 'package:Bloomee/services/audio_service_initializer.dart';
import 'package:Bloomee/services/keyboard_shortcuts_service.dart';
import 'package:Bloomee/services/shortcut_indicator_service.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/services/import_export_service.dart';
import 'package:Bloomee/utils/ticker.dart';
import 'package:Bloomee/utils/url_checker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:Bloomee/blocs/add_to_playlist/cubit/add_to_playlist_cubit.dart';
import 'package:Bloomee/blocs/library/cubit/library_items_cubit.dart';
import 'package:Bloomee/plugins/blocs/import/content_import_cubit.dart';
import 'package:Bloomee/routes/app_router.dart';
import 'package:Bloomee/screens/screen/library_views/cubit/current_playlist_cubit.dart';
import 'package:media_kit/media_kit.dart';
import 'package:share_handler/share_handler.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'blocs/media_player/bloomee_player_cubit.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:Bloomee/services/discord_service.dart';
import 'package:Bloomee/services/db/legacy/legacy_migration_service.dart'
    as legacy_migration;
import 'package:Bloomee/screens/widgets/legacy_migration_overlay.dart';
import 'package:Bloomee/screens/widgets/onboarding_overlay.dart';
import 'package:Bloomee/screens/widgets/plugin_bootstrap_overlay.dart';
import 'package:Bloomee/services/onboarding_service.dart';
import 'package:Bloomee/services/plugin_bootstrap_service.dart';
import 'package:Bloomee/plugins/services/plugin_repository_service.dart';
import 'package:Bloomee/services/shared_url_resolver_service.dart';
import 'package:Bloomee/tv/tv_focus.dart';
import 'package:Bloomee/tv/tv_mode.dart';
import 'package:Bloomee/tv/tv_config.dart';

void processIncomingIntent(SharedMedia sharedMedia) {
  if (sharedMedia.content != null && isUrl(sharedMedia.content!)) {
    final urlType = getUrlType(sharedMedia.content!);
    switch (urlType) {
      case UrlType.youtubeVideo:
        _handleYoutubeVideoIntent(sharedMedia.content!);
        break;
      case UrlType.youtubePlaylist:
      case UrlType.spotifyTrack:
      case UrlType.spotifyPlaylist:
      case UrlType.spotifyAlbum:
      case UrlType.other:
        SnackbarService.showMessage(
            'Open the Import screen in Library to import from this URL.');
        break;
    }
  } else if (sharedMedia.attachments != null &&
      sharedMedia.attachments!.isNotEmpty) {
    final attachment = sharedMedia.attachments!.first;
    if (attachment != null) {
      SnackbarService.showMessage('Processing File...');
      importItems(attachment.path);
    }
  }
}

Future<void> _handleYoutubeVideoIntent(String url) async {
  if (extractVideoId(url) == null) {
    SnackbarService.showMessage('Invalid YouTube URL');
    return;
  }
  SnackbarService.showMessage('Getting YouTube Audio...');

  final result = await SharedUrlResolverService.resolveYoutubeVideo(url);
  if (result.status == SharedUrlResolveStatus.invalidUrl) {
    SnackbarService.showMessage('Invalid YouTube URL');
    return;
  }

  if (result.status == SharedUrlResolveStatus.noResolver) {
    SnackbarService.showMessage(
        'No loaded content resolver can handle this URL.');
    return;
  }

  final track = result.track;
  if (result.status == SharedUrlResolveStatus.success && track != null) {
    final player = await PlayerInitializer().getBloomeeMusicPlayer();
    await player.updateQueueTracks([track], doPlay: true);
    SnackbarService.showMessage('Playing: ${track.title}');
    return;
  }

  if (result.status == SharedUrlResolveStatus.failed) {
    SnackbarService.showMessage('Failed to get YouTube audio.');
  }
}

Future<void> importItems(String path) async {
  final context = GlobalRoutes.globalRouterKey.currentContext;
  if (context == null) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      importItems(path);
    });
    return;
  }

  await ImportExportService.handleImportOrRestore(context, path);
}

Future<void> setHighRefreshRate() async {
  if (io.Platform.isAndroid) {
    await FlutterDisplayMode.setHighRefreshRate();
  }
}

late BloomeePlayerCubit bloomeePlayerCubit;
Future<void> setupPlayerCubit() async {
  await setupAudioSession();
  final player = await PlayerInitializer().getBloomeeMusicPlayer();
  bloomeePlayerCubit = BloomeePlayerCubit(player);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GestureBinding.instance.resamplingEnabled = true;
  await TvMode.init();
  runApp(const _AppRuntime());
}

class _AppRuntime extends StatefulWidget {
  const _AppRuntime();
  @override
  State<_AppRuntime> createState() => _AppRuntimeState();
}

class _AppRuntimeState extends State<_AppRuntime> {
  bool _ready = false;
  Object? _error;
  int _epoch = 0;
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _ready = false;
    });
    try {
      MediaKit.ensureInitialized();
      await bootstrapApp();
      if (TvMode.isTv) {
        TvConfig.profileId = TvProfiles.instance.selectedId;
        await TvConfig.load();
        await TvOperations.instance.reconcileInterrupted();
        await TvConfig.importFromFile();
        TvProfiles.instance.onSwitch = _switch;
      }
      await setupPlayerCubit();
      if (TvMode.isTv) attachTvRemote(bloomeePlayerCubit.bloomeePlayer);
      if (TvMode.isTv)
        await TvCastService.initialize((id, position) async {
          var track = await TrackDAO(DBProvider.db).getTrackByMediaId(id);
          if (track == null) {
            final uri = Uri.tryParse(id);
            final host = uri?.host.toLowerCase();
            if (uri?.scheme == 'https' &&
                [
                  'youtube.com',
                  'www.youtube.com',
                  'music.youtube.com',
                  'youtu.be'
                ].contains(host)) {
              track = (await SharedUrlResolverService.resolveYoutubeVideo(id))
                  .track;
            }
          }
          if (track == null) throw StateError('Contenuto Cast non supportato');
          final player = bloomeePlayerCubit.bloomeePlayer;
          await player.updateQueueTracks([track], doPlay: true);
          if (position > Duration.zero) await player.seek(position);
        });
      DiscordService.initialize();
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      TvDiagnostics.instance.record('Avvio', e);
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _switch(TvProfile profile) async {
    final old = TvProfiles.instance.selected;
    final player = bloomeePlayerCubit.bloomeePlayer;
    final routeContext = GlobalRoutes.globalRouterKey.currentContext;
    final downloader = routeContext?.read<DownloaderCubit>();
    await TvOperations.instance.cancelAll();
    await downloader?.prepareProfileSwitch();
    setState(() {
      _ready = false;
      _error = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    try {
      await tvPairing.close();
      await tvRemote.close();
      await player.prepareProfileSwitch();
      await TvImagePrivacy.clear();
      await ServiceLocator.prepareProfileSwitch();
      await TvConfig.flush();
      await TvWorkspace.instance.flush();
      await DBProvider.switchDirectory(
          TvProfiles.instance.directoryFor(profile.id).path);
      await TvWorkspace.instance
          .open(TvProfiles.instance.directoryFor(profile.id));
      await ServiceLocator.resetForProfile();
      TvConfig.profileId = profile.id;
      await TvConfig.load();
      TvCatalogCache.instance.resetSession();
      TvDiagnostics.instance.clear();
      await player.reloadProfile();
      await setupPlayerCubit();
      if (TvMode.isTv) attachTvRemote(bloomeePlayerCubit.bloomeePlayer);
      GlobalRoutes.globalRouter.go('/Explore');
      if (old.guest) await TvConfig.secretStore.write(old.id, {});
      if (mounted)
        setState(() {
          _epoch++;
          _ready = true;
        });
    } catch (e) {
      TvDiagnostics.instance.record('Cambio profilo', e);
      await DBProvider.switchDirectory(
          TvProfiles.instance.directoryFor(old.id).path);
      await TvWorkspace.instance.open(TvProfiles.instance.directoryFor(old.id));
      await ServiceLocator.resetForProfile();
      TvConfig.profileId = old.id;
      await TvConfig.load();
      await player.reloadProfile();
      await setupPlayerCubit();
      if (TvMode.isTv) attachTvRemote(bloomeePlayerCubit.bloomeePlayer);
      if (mounted)
        setState(() {
          _epoch++;
          _ready = true;
        });
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready)
      return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: Default_Theme().defaultThemeData,
          home: Scaffold(
              body: Center(
                  child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Bloomee TV',
                            style: TextStyle(fontSize: 32)),
                        const SizedBox(height: 20),
                        if (_error == null) ...[
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          const Text('Preparo musica e profilo…')
                        ] else ...[
                          const Text(
                              'Avvio non riuscito. I dati sono conservati.'),
                          const SizedBox(height: 16),
                          FilledButton(
                              autofocus: true,
                              onPressed: _start,
                              child: const Text('Riprova'))
                        ],
                      ])))));
    return ListenableBuilder(
        listenable: TvWorkspace.instance,
        builder: (_, __) => TvRoot(child: MyApp(key: ValueKey(_epoch))));
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  // Initialize the player
  // This widget is the root of your application.
  StreamSubscription<SharedMedia>? _intentSub;
  SharedMedia? sharedMedia;

  // TODO: remove this after one or two releases.
  // Legacy migration — set to true when a default.isar file is found.
  // Remove this field (and the overlay block in build) once no users
  // need legacy migration.
  bool _migrationPending = false;
  bool _onboardingPending = false;
  bool _pluginBootstrapPending = false;
  // ------------------

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Check once at startup; DBProvider.appSuppDir is set by bootstrapApp().
    _migrationPending =
        (!TvMode.isTv || TvProfiles.instance.selectedId == 'default') &&
            legacy_migration.needsMigration(
              DBProvider.appSuppDir,
              DBProvider.appDocDir,
            );

    _onboardingPending = !TvMode.isTv && !OnboardingService.onboardingDone;
    _pluginBootstrapPending = !PluginBootstrapService.bootstrapDone;
    //--------------------------------------------------------------------

    if (io.Platform.isAndroid) {
      initPlatformState();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(tvPairing.close());
      unawaited(tvRemote.close());
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_ensurePlayerHealthyOnResume());
      // Check for plugin updates when app resumes (30-min cooldown enforced).
      unawaited(_checkPluginUpdatesOnResume());
    }
  }

  Future<void> _ensurePlayerHealthyOnResume() async {
    try {
      final player = await PlayerInitializer().getBloomeeMusicPlayer();
      if (!player.isPlayerHealthy) {
        await player.revive();
      }
      player.syncPublicState();
    } catch (error, stackTrace) {
      debugPrint('Player health check on resume failed: $error\n$stackTrace');
    }
  }

  Future<void> _checkPluginUpdatesOnResume() async {
    try {
      final settingsDao = SettingsDAO(DBProvider.db);
      final repositoryService =
          PluginRepositoryService(settingsDao: settingsDao);
      await PluginBootstrapService.syncOnAppOpenIfDue(
        pluginService: ServiceLocator.pluginService,
        repositoryService: repositoryService,
        settingsDao: settingsDao,
      );
    } catch (error, stackTrace) {
      debugPrint('Plugin update check on resume failed: $error\n$stackTrace');
    }
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    try {
      final handler = ShareHandlerPlatform.instance;
      sharedMedia = await handler.getInitialSharedMedia();

      _intentSub = handler.sharedMediaStream.listen((SharedMedia media) {
        if (!mounted) return;
        setState(() {
          sharedMedia = media;
        });
        if (sharedMedia != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            processIncomingIntent(sharedMedia!);
          });
        }
      });
      if (!mounted) return;

      setState(() {
        // If there's initial shared media, process it
        if (sharedMedia != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            processIncomingIntent(sharedMedia!);
          });
        }
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to initialize share handler: $error\n$stackTrace');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _intentSub?.cancel();
    bloomeePlayerCubit.close();
    if (io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS) {
      DiscordService.clearPresence();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Legacy migration guard ────────────────────────────────────────────
    // If a default.isar (legacy DB) exists, show the non-dismissible
    // migration overlay before starting the normal app. Once migration
    // finishes successfully the overlay removes itself.
    //
    // To remove this feature in future: delete the `if` block below AND the
    // import at the top of this file AND lib/services/db/legacy/.
    if (_migrationPending) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: LegacyMigrationOverlay(
          appSuppDir: DBProvider.appSuppDir,
          appDocDir: DBProvider.appDocDir,
          onComplete: (result) {
            if (!result.success) return;
            setState(() => _migrationPending = false);
          },
        ),
      );
    }

    if (_onboardingPending) {
      return OnboardingOverlay(
        onComplete: () {
          if (!mounted) return;
          setState(() {
            _onboardingPending = false;
            _pluginBootstrapPending = !PluginBootstrapService.bootstrapDone;
          });
        },
      );
    }

    if (_pluginBootstrapPending) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: PluginBootstrapOverlay(
          onComplete: () {
            if (!mounted) return;
            setState(() => _pluginBootstrapPending = false);
          },
        ),
      );
    }
    // ─────────────────────────────────────────────────────────────────────

    final trackDao = TrackDAO(DBProvider.db);
    final playlistDao = PlaylistDAO(DBProvider.db, trackDao);
    final historyDao = HistoryDAO(DBProvider.db, trackDao);

    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => PluginBloc(
            pluginService: ServiceLocator.pluginService,
            eventBus: ServiceLocator.pluginEventBus,
            repositoryService: ServiceLocator.pluginRepositoryService,
            settingsDao: SettingsDAO(DBProvider.db),
          )..add(const InitializePluginSystem()),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => bloomeePlayerCubit,
          lazy: false,
        ),
        BlocProvider(
            create: (context) =>
                MiniPlayerCubit(playerCubit: bloomeePlayerCubit),
            lazy: true),
        BlocProvider(
          create: (context) => SettingsCubit(
            SettingsRepository(SettingsDAO(DBProvider.db)),
          ),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => NotificationCubit(
            notificationDao: NotificationDAO(DBProvider.db),
          ),
          lazy: false,
        ),
        BlocProvider(
            create: (context) => TimerBloc(
                ticker: const Ticker(),
                timer: bloomeePlayerCubit.bloomeePlayer.sleepTimer)),
        BlocProvider(
          create: (context) => ConnectivityCubit(),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => CurrentPlaylistCubit(playlistDao: playlistDao),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => RecentlyCubit(historyDao),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => HistoryCubit(historyDao: historyDao),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => LibraryItemsCubit(
            playlistDao: playlistDao,
            libraryDao: LibraryDAO(DBProvider.db),
          ),
        ),
        BlocProvider(
          create: (context) => ContentImportCubit(),
          lazy: true,
        ),
        BlocProvider(
          create: (context) => AddToPlaylistCubit(),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => SearchSuggestionBloc(
            searchHistoryDao: SearchHistoryDAO(DBProvider.db),
            pluginService: ServiceLocator.pluginService,
            settingsDao: SettingsDAO(DBProvider.db),
          ),
        ),
        BlocProvider(
          create: (context) => LyricsCubit(
            bloomeePlayerCubit,
            lyricsDao: LyricsDAO(DBProvider.db),
            settingsDao: SettingsDAO(DBProvider.db),
            pluginService: ServiceLocator.pluginService,
          ),
        ),
        BlocProvider(
          create: (context) => LastdotfmCubit(
            playerCubit: bloomeePlayerCubit,
            cacheDao: CacheDAO(DBProvider.db),
            settingsDao: SettingsDAO(DBProvider.db),
            pluginService: ServiceLocator.pluginService,
          ),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => DownloaderCubit(
            connectivityCubit: context.read<ConnectivityCubit>(),
            libraryItemsCubit: context.read<LibraryItemsCubit>(),
            downloadRepo: DownloadRepository(
              DownloadDAO(DBProvider.db, trackDao, playlistDao),
            ),
            settingsDao: SettingsDAO(DBProvider.db),
            pluginService: ServiceLocator.pluginService,
          ),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => GlobalEventsCubit(
            settingsDao: SettingsDAO(DBProvider.db),
          ),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => PlayerOverlayCubit(),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => ShortcutIndicatorCubit(),
          lazy: false,
        ),
        BlocProvider(
          create: (context) => LocalMusicCubit(),
          lazy: true,
        ),
      ],
      child: BlocBuilder<BloomeePlayerCubit, BloomeePlayerState>(
        builder: (context, state) {
          if (state is BloomeePlayerInitial) {
            return const Center(
              child: SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(
                  color: Default_Theme.accentColor2,
                ),
              ),
            );
          } else {
            return BlocBuilder<SettingsCubit, SettingsState>(
              builder: (context, settingsState) {
                final locale = settingsState.languageCode.isEmpty
                    ? null
                    : Locale(settingsState.languageCode);

                return KeyboardShortcutsHandler(
                  child: ShortcutIndicatorOverlay(
                    child: MaterialApp.router(
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      locale: locale,
                      builder: (context, child) =>
                          ResponsiveBreakpoints.builder(
                        breakpoints: [
                          const Breakpoint(start: 0, end: 450, name: MOBILE),
                          const Breakpoint(start: 451, end: 800, name: TABLET),
                          const Breakpoint(
                              start: 801, end: 1920, name: DESKTOP),
                          const Breakpoint(
                              start: 1921, end: double.infinity, name: '4K'),
                        ],
                        child: MediaQuery(
                            data: MediaQuery.of(context).copyWith(
                                textScaler: TextScaler.linear(((TvWorkspace
                                                    .instance['textScale']
                                                as num? ??
                                            1)
                                        .toDouble()
                                        .clamp(1, 1.5)) *
                                    MediaQuery.textScalerOf(context).scale(16) /
                                    16),
                                disableAnimations:
                                    MediaQuery.of(context).disableAnimations ||
                                        TvWorkspace.instance['reduceMotion'] ==
                                            true,
                                highContrast: MediaQuery.of(context)
                                        .highContrast ||
                                    TvWorkspace.instance['highContrast'] == true),
                            child: GlobalEventListener(
                              navigatorKey: GlobalRoutes.globalRouterKey,
                              child: TvWorkspace.instance['highContrast'] ==
                                      true
                                  ? ColorFiltered(
                                      colorFilter: const ColorFilter.matrix([
                                        1.2,
                                        0,
                                        0,
                                        0,
                                        -16,
                                        0,
                                        1.2,
                                        0,
                                        0,
                                        -16,
                                        0,
                                        0,
                                        1.2,
                                        0,
                                        -16,
                                        0,
                                        0,
                                        0,
                                        1,
                                        0
                                      ]),
                                      child: child!)
                                  : child!,
                            )),
                      ),
                      scaffoldMessengerKey: SnackbarService.messengerKey,
                      routerConfig: GlobalRoutes.globalRouter,
                      theme: tvTheme(Default_Theme().defaultThemeData),
                      actions: tvActions(),
                      scrollBehavior: CustomScrollBehavior(),
                      debugShowCheckedModeBanner: false,
                    ),
                  ),
                );
              },
            );
          }
        },
      ),
    );
  }
}

class CustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}
