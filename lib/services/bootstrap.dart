import 'package:Bloomee/tv/services/tv_image_privacy.dart';
import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'package:Bloomee/tv/services/tv_workspace.dart';
import 'package:Bloomee/tv/tv_mode.dart';
import 'package:Bloomee/tv/tv_config.dart';

import 'package:Bloomee/core/constants/setting_keys.dart';
import 'package:Bloomee/core/di/service_locator.dart';
import 'package:Bloomee/services/db/dao/settings_dao.dart';
import 'package:Bloomee/services/local_music_service.dart';
import 'package:Bloomee/services/plugin_bootstrap_service.dart';
import 'package:Bloomee/services/onboarding_service.dart';
import 'package:Bloomee/src/rust/frb_generated.dart';
import 'package:Bloomee/services/db/db_provider.dart';
import 'package:path_provider/path_provider.dart';

/// Application bootstrap — run once before [runApp].
///
/// Responsibilities:
/// - Initialize platform path constants.
/// - Open the Isar database via [DBProvider].
/// - Schedule periodic DB maintenance tasks.
/// - Wire the [ServiceLocator] and initialize the plugin system.
Future<void> bootstrapApp() async {
  // Initialize flutter_rust_bridge before any Rust API call.
  if (!RustLib.instance.initialized) await RustLib.init();

  final String appDocPath = (await getApplicationDocumentsDirectory()).path;
  final String appSuppPath = (await getApplicationSupportDirectory()).path;

  if (TvMode.isTv) {
    TvProfiles.instance.onDiscardGuest = (id) async {
      await TvConfig.secretStore.write(id, {});
      await TvImagePrivacy.clear();
    };
    await TvProfiles.instance.open(Directory(appSuppPath));
  }
  // Open DB and schedule maintenance.
  await DBProvider.init(
      appSupportPath: TvMode.isTv
          ? TvProfiles.instance
              .directoryFor(TvProfiles.instance.selectedId)
              .path
          : appSuppPath,
      appDocumentsPath: appDocPath,
      allowLegacyRecovery:
          !TvMode.isTv || TvProfiles.instance.selectedId == 'default');
  await DBProvider.scheduleMaintenance();

  // DI wiring (registers singletons).
  await ServiceLocator.setup();

  // Ensure hosted repositories are persisted in settings (idempotent).
  // Missing URLs are added, existing ones are left untouched.
  try {
    unawaited(PluginBootstrapService.ensureHostedRepositoriesPresent(
      repositoryService: ServiceLocator.pluginRepositoryService,
    ).catchError((Object e) {
      log('Repository reconciliation postponed', name: 'Bootstrap');
    }));
  } catch (e) {
    log('Hosted repository reconciliation skipped',
        error: e, name: 'Bootstrap');
  }

  // Initialize plugin system:
  //   Creates Rust PluginManager → connects event bus →
  //   preloads storage from Isar → starts storage event handler.
  try {
    await ServiceLocator.initializePluginSystem();
    log('Plugin system initialized successfully', name: 'Bootstrap');
  } catch (e, stack) {
    // Plugin system failure is non-fatal — the app can still run
    // with degraded functionality (no plugin content).
    log('Plugin system initialization failed (non-fatal)',
        error: e, stackTrace: stack, name: 'Bootstrap');
  }

  // Auto-scan local music folders if enabled (fire-and-forget).
  try {
    final settingsDao = SettingsDAO(DBProvider.db);
    final autoScan =
        await settingsDao.getSettingBool(SettingKeys.localMusicAutoScan) ??
            true;
    if (autoScan && !TvMode.isTv) {
      unawaited(LocalMusicService.create().scanAndPersist().then<void>((_) {},
          onError: (Object e) {
        log('Local scan postponed', name: 'Bootstrap');
      }));
    }
  } catch (e) {
    log('Local music auto-scan skipped', error: e, name: 'Bootstrap');
  }

  // Pre-load the plugin-bootstrap done-flag so that _MyAppState can check
  // it synchronously in initState() without an async call.
  try {
    final settingsDao = SettingsDAO(DBProvider.db);
    await OnboardingService.checkAndCacheDone(settingsDao);
    await PluginBootstrapService.checkAndCacheDone(settingsDao);
  } catch (e) {
    log('Could not load bootstrap flag (will re-run bootstrap)',
        error: e, name: 'Bootstrap');
  }
}
