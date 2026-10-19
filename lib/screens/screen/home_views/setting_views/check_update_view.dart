import 'package:Bloomee/services/bloomee_updater_tools.dart';
import 'package:Bloomee/tv/tv_mode.dart';
import 'package:flutter/material.dart';
import 'package:Bloomee/core/theme/app_theme.dart';
import 'package:Bloomee/utils/url_launcher.dart';
import 'package:Bloomee/l10n/app_localizations.dart';
import 'package:icons_plus/icons_plus.dart';

class CheckUpdateView extends StatefulWidget {
  const CheckUpdateView({super.key});

  @override
  State<CheckUpdateView> createState() => _CheckUpdateViewState();
}

class _CheckUpdateViewState extends State<CheckUpdateView> {
  late Future<Map<String, dynamic>> _updates = getLatestVersion();
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(
          l10n.updateCheckTitle,
          style: const TextStyle(
                  color: Default_Theme.primaryColor1,
                  fontSize: 20,
                  fontWeight: FontWeight.bold)
              .merge(Default_Theme.secondoryTextStyle),
        ),
      ),
      body: Center(
        child: FutureBuilder(
          future: _updates,
          builder: (context, snapshot) {
            if (snapshot.hasError || snapshot.data?['error'] != null) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Verifica aggiornamenti non riuscita'),
                const SizedBox(height: 16),
                FilledButton(
                    autofocus: true,
                    onPressed: () =>
                        setState(() => _updates = getLatestVersion()),
                    child: const Text('Riprova')),
              ]);
            }
            if (snapshot.hasData) {
              if (!snapshot.data?["results"]) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Text(
                      l10n.updateUpToDate,
                      style: const TextStyle(
                              color: Default_Theme.accentColor2, fontSize: 20)
                          .merge(Default_Theme.secondoryTextStyleMedium),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(5.0),
                      child: FilledButton(
                        onPressed: () {
                          launch_Url(Uri.parse(TvMode.isTv
                              ? 'https://github.com/fabiodalez-dev/BloomeeTV/releases'
                              : 'https://github.com/HemantKArya/BloomeeTunes/releases'));
                        },
                        child: SizedBox(
                          // width: 150,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                FontAwesome.github_alt_brand,
                                size: 25,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(left: 5),
                                child: Text(
                                  l10n.updateViewPreRelease,
                                  style: const TextStyle(fontSize: 17).merge(
                                      Default_Theme.secondoryTextStyleMedium),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        l10n.updateCurrentVersion(
                            snapshot.data?["currVer"] ?? '',
                            snapshot.data?["currBuild"] ?? ''),
                        style: TextStyle(
                                color: Default_Theme.primaryColor2
                                    .withValues(alpha: 0.5),
                                fontSize: 12)
                            .merge(Default_Theme.tertiaryTextStyle),
                      ),
                    ),
                  ],
                );
              } else {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Text(
                      l10n.updateNewVersionAvailable,
                      style: const TextStyle(
                              color: Default_Theme.accentColor2, fontSize: 20)
                          .merge(Default_Theme.tertiaryTextStyle),
                      textAlign: TextAlign.center,
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        l10n.updateVersion(snapshot.data?["newVer"] ?? '',
                            snapshot.data?["newBuild"] ?? ''),
                        style: TextStyle(
                                color: Default_Theme.primaryColor1
                                    .withValues(alpha: 0.8),
                                fontSize: 16)
                            .merge(Default_Theme.tertiaryTextStyle),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: FilledButton(
                        onPressed: () {
                          launch_Url(
                              Uri.parse("https://bloomee.sourceforge.io/"));
                        },
                        child: SizedBox(
                          width: 150,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.open_in_browser_rounded,
                                  size: 25),
                              Text(
                                l10n.updateDownloadNow,
                                style: const TextStyle(fontSize: 17).merge(
                                    Default_Theme.secondoryTextStyleMedium),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Text(
                        l10n.updateCurrentVersion(
                            snapshot.data?["currVer"] ?? '',
                            snapshot.data?["currBuild"] ?? ''),
                        style: TextStyle(
                                color: Default_Theme.primaryColor2
                                    .withValues(alpha: 0.5),
                                fontSize: 12)
                            .merge(Default_Theme.tertiaryTextStyle),
                      ),
                    ),
                  ],
                );
              }
            } else {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Padding(
                    padding: EdgeInsets.all(15.0),
                    child: SizedBox(
                        height: 50,
                        width: 50,
                        child: CircularProgressIndicator(
                          color: Default_Theme.accentColor2,
                        )),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SizedBox(
                        width: constraints.maxWidth * 0.6,
                        child: Text(l10n.updateChecking,
                            style: const TextStyle(
                                    color: Default_Theme.accentColor2,
                                    fontSize: 20)
                                .merge(Default_Theme.tertiaryTextStyle),
                            textAlign: TextAlign.center),
                      );
                    },
                  )
                ],
              );
            }
          },
        ),
      ),
    );
  }
}
