import 'package:Bloomee/screens/screen/home_views/setting_view.dart';
import 'package:Bloomee/screens/screen/plugin_manager_screen.dart';
import 'package:Bloomee/tv/connectors/jellyfin_client.dart';
import 'package:Bloomee/tv/connectors/lidarr_client.dart';
import 'package:Bloomee/tv/tv_config.dart';
import 'package:Bloomee/tv/screens/tv_youtube_screen.dart';
import 'package:Bloomee/screens/widgets/snackbar.dart';
import 'package:Bloomee/tv/ui/tv_widgets.dart';
import 'package:flutter/material.dart';

/// Impostazioni TV: collegamento a Jellyfin e Lidarr, più accesso alle
/// impostazioni complete dell'app.
class TvSettingsScreen extends StatefulWidget {
  const TvSettingsScreen({super.key});

  @override
  State<TvSettingsScreen> createState() => _TvSettingsScreenState();
}

class _TvSettingsScreenState extends State<TvSettingsScreen> {
  late final _jfUrl = TextEditingController(text: TvConfig.jellyfinUrl);
  late final _jfUser = TextEditingController(text: TvConfig.jellyfinUser);
  final _jfPass = TextEditingController();
  final _jfKey = TextEditingController();
  late final _ldUrl = TextEditingController(text: TvConfig.lidarrUrl);
  late final _ldKey = TextEditingController(text: TvConfig.lidarrKey);

  String? _jfStatus;
  String? _ldStatus;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (TvConfig.hasJellyfin) _jfStatus = 'Collegato come ${TvConfig.jellyfinUser}';
    if (TvConfig.hasLidarr) _ldStatus = 'Chiave salvata';
  }

  @override
  void dispose() {
    for (final c in [_jfUrl, _jfUser, _jfPass, _jfKey, _ldUrl, _ldKey]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _connectJellyfin() async {
    setState(() {
      _busy = true;
      _jfStatus = 'Collegamento…';
    });
    final url = _jfUrl.text.trim();
    final user = _jfUser.text.trim();
    try {
      final c = JellyfinClient(baseUrl: url);
      String token;
      String userId;
      if (_jfKey.text.trim().isNotEmpty) {
        c.token = _jfKey.text.trim();
        final id = await c.userIdByName(user);
        if (id == null) throw Exception('utente "$user" non trovato');
        token = c.token!;
        userId = id;
      } else {
        await c.login(user, _jfPass.text);
        token = c.token!;
        userId = c.userId!;
      }
      c.userId = userId;
      final name = await c.serverName();
      final albums = await c.recentAlbums(limit: 1);
      await TvConfig.saveJellyfin(url: url, user: user, token: token, userId: userId);
      _jfPass.clear();
      _jfKey.clear();
      setState(() => _jfStatus =
          'Collegato a "$name" come $user${albums.isEmpty ? ' (nessun album trovato)' : ''}');
    } on JellyfinAuthException {
      setState(() => _jfStatus = 'Credenziali non valide');
    } catch (e) {
      setState(() => _jfStatus = 'Errore: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _connectLidarr() async {
    setState(() {
      _busy = true;
      _ldStatus = 'Verifica…';
    });
    try {
      final c = LidarrClient(baseUrl: _ldUrl.text.trim(), apiKey: _ldKey.text.trim());
      final v = await c.ping();
      await TvConfig.saveLidarr(url: _ldUrl.text.trim(), key: _ldKey.text.trim());
      setState(() => _ldStatus = 'Collegato: $v');
    } catch (e) {
      setState(() => _ldStatus = 'Errore: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Widget _field(String label, TextEditingController c, {bool obscure = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TvTextField(controller: c, label: label, obscure: obscure),
    );
  }

  Widget _section({required IconData icon, required String title, required String hint, required List<Widget> children, String? status}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(color: TvColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: TvColors.accent, size: 28),
            const SizedBox(width: 12),
            Text(title, style: TvText.title),
          ]),
          const SizedBox(height: 6),
          Text(hint, style: TvText.body),
          const SizedBox(height: 16),
          ...children,
          if (status != null) ...[
            const SizedBox(height: 10),
            Text(status, style: TvText.body.copyWith(color: status.startsWith('Errore') || status.startsWith('Credenziali') ? Colors.redAccent : const Color(0xFF7BE495))),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TvColors.bg,
      body: FocusTraversalGroup(
        policy: OrderedTraversalPolicy(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(48, 40, 48, 60),
          children: [
            const Text('Impostazioni', style: TvText.hero),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _section(
                    icon: Icons.dns_rounded,
                    title: 'Jellyfin',
                    hint: 'La tua musica dal server. Usa utente e password, oppure una chiave API.',
                    status: _jfStatus,
                    children: [
                      _field('Indirizzo server (es. https://casa.example/jellyfin)', _jfUrl),
                      _field('Utente', _jfUser),
                      _field('Password', _jfPass, obscure: true),
                      _field('Oppure chiave API', _jfKey),
                      TvPillButton(icon: Icons.link_rounded, label: 'Collega Jellyfin', primary: true, onTap: _busy ? null : _connectJellyfin),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                Expanded(
                  child: _section(
                    icon: Icons.cloud_download_rounded,
                    title: 'Lidarr',
                    hint: 'Per "Scarica questo album": la chiave è in Lidarr → Settings → General.',
                    status: _ldStatus,
                    children: [
                      _field('Indirizzo Lidarr (es. http://192.168.1.10:8686)', _ldUrl),
                      _field('Chiave API', _ldKey),
                      TvPillButton(icon: Icons.check_rounded, label: 'Verifica e salva', primary: true, onTap: _busy ? null : _connectLidarr),
                    ],
                  ),
                ),
              ],
            ),
            _section(
              icon: Icons.smart_display_rounded,
              title: 'Account YouTube Music',
              hint: 'Collega il tuo account Google per avere cronologia, Mi piace, playlist e artisti seguiti (menu "Il mio YouTube" e Home). Puoi scrivere anche con la tastiera del Mac dalla finestra scrcpy.',
              status: TvConfig.hasYouTube ? 'Collegato come ${TvConfig.ytName}' : null,
              children: [
                Wrap(spacing: 14, children: [
                  TvPillButton(
                    icon: Icons.login_rounded,
                    label: TvConfig.hasYouTube ? 'Accedi con un altro account' : 'Accedi con Google',
                    primary: true,
                    onTap: () async {
                      final ok = await loginYouTube();
                      if (mounted) setState(() {});
                      if (ok) SnackbarService.showMessage('YouTube Music collegato: ${TvConfig.ytName}');
                    },
                  ),
                  if (TvConfig.hasYouTube)
                    TvPillButton(
                      icon: Icons.logout_rounded,
                      label: 'Esci',
                      onTap: () async {
                        await logoutYouTube();
                        if (mounted) setState(() {});
                      },
                    ),
                ]),
              ],
            ),
            Wrap(spacing: 16, runSpacing: 16, children: [
              TvPillButton(
                icon: Icons.tune_rounded,
                label: 'Impostazioni avanzate dell\'app',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsView())),
              ),
              TvPillButton(
                icon: Icons.extension_rounded,
                label: 'Sorgenti (plugin)',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PluginManagerScreen())),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
