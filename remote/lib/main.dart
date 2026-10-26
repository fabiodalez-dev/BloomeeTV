import 'catalog_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'remote_client.dart';

void main() => runApp(const RemoteApp());

class RemoteApp extends StatelessWidget {
  const RemoteApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bloomee Remote',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffee98bf),
        brightness: Brightness.dark,
        surface: const Color(0xff19161d),
      ),
      scaffoldBackgroundColor: const Color(0xff19161d),
      useMaterial3: true,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
    ),
    home: const RemoteHome(),
  );
}

class RemoteHome extends StatefulWidget {
  const RemoteHome({super.key});
  @override
  State<RemoteHome> createState() => _RemoteHomeState();
}

class _RemoteHomeState extends State<RemoteHome> with WidgetsBindingObserver {
  final _address = TextEditingController();
  final _code = TextEditingController();
  RemoteClient? _remote;
  Map<String, dynamic>? _state;
  Timer? _poll;
  bool _busy = false, _polling = false, _fresh = false;
  String? _error;
  int _tab = 0;
  double? _seek, _volume;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreAddress();
  }

  Future<void> _restoreAddress() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted && _address.text.isEmpty) {
      _address.text = prefs.getString('tvAddress') ?? '';
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _remote?.close();
    _address.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _poll?.cancel();
    if (state == AppLifecycleState.resumed && _remote != null) {
      _refresh();
      _startPolling();
    } else {
      _fresh = false;
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  Future<void> _connect() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    RemoteClient? candidate;
    try {
      candidate = RemoteClient(parseTvAddress(_address.text));
      await candidate.pair(_code.text);
      final state = await candidate.state();
      if (!mounted) {
        candidate.close();
        return;
      }
      _remote = candidate;
      setState(() {
        _state = state;
        _fresh = true;
        _tab = 0;
      });
      _code.clear();
      _startPolling();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tvAddress', candidate.address.toString());
    } catch (e) {
      if (_remote != candidate) candidate?.close();
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _disconnect() {
    _poll?.cancel();
    _remote?.close();
    setState(() {
      _remote = null;
      _state = null;
      _fresh = false;
      _error = null;
      _seek = _volume = null;
    });
  }

  Future<void> _refresh() async {
    final remote = _remote;
    if (remote == null || _polling) return;
    _polling = true;
    try {
      final data = await remote.state();
      if (mounted && _remote == remote) {
        setState(() {
          _state = data;
          if (!_fresh) _error = null;
          _fresh = true;
        });
      }
    } catch (e) {
      if (mounted && _remote == remote) {
        if (e is RemoteException && e.unauthorized) _disconnect();
        setState(() {
          _fresh = false;
          _error = e.toString();
        });
      }
    } finally {
      _polling = false;
    }
  }

  Future<bool> _command(String action, [Object? value]) async {
    final remote = _remote;
    if (_busy || remote == null || !_fresh) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await remote.command(action, value);
      await _refresh();
      return true;
    } catch (e) {
      if (mounted && _remote == remote) {
        if (e is RemoteException && e.unauthorized) _disconnect();
        setState(() => _error = e.toString());
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _seek = _volume = null;
        });
      }
    }
  }

  String _time(num ms) {
    final seconds = (ms / 1000).floor().clamp(0, 604800);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  double _number(String key, [double fallback = 0]) =>
      (_state?[key] as num?)?.toDouble() ?? fallback;
  bool get _enabled => _fresh && !_busy;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Bloomee Remote'),
      actions: [
        if (_remote != null)
          IconButton(
            tooltip: 'Cambia TV',
            onPressed: _busy ? null : _disconnect,
            icon: const Icon(Icons.tv),
          ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (_error != null)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    if (_remote != null)
                      IconButton(
                        tooltip: 'Riprova',
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
              ),
            ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _remote == null
                ? _connection()
                : IndexedStack(
                    index: _tab,
                    children: [
                      _player(),
                      CatalogScreen(
                        key: ValueKey('${identityHashCode(_remote)}-search'),
                        active: _tab == 1,
                        remote: _remote!,
                        command: _command,
                      ),
                      CatalogScreen(
                        key: ValueKey('${identityHashCode(_remote)}-playlists'),
                        remote: _remote!,
                        command: _command,
                        playlists: true,
                        active: _tab == 2,
                      ),
                      _queue(),
                    ],
                  ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: _remote == null
        ? null
        : NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.album_outlined),
                selectedIcon: Icon(Icons.album),
                label: 'In ascolto',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: 'Cerca'),
              NavigationDestination(
                icon: Icon(Icons.playlist_play),
                label: 'Playlist',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music),
                label: 'Coda',
              ),
            ],
          ),
  );

  Widget _connection() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Icon(
                  Icons.speaker_group_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'La musica sulla tua TV.',
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Cellulare e TV devono essere sulla stessa rete Wi-Fi. Apri Bloomee sulla TV e attiva il telecomando.',
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _address,
                enabled: !_busy,
                keyboardType: TextInputType.url,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Indirizzo TV',
                  hintText: '192.168.1.50:18794',
                  prefixIcon: Icon(Icons.tv),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _code,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                maxLength: 7,
                onSubmitted: (_) => _connect(),
                decoration: const InputDecoration(
                  labelText: 'Codice di 6 cifre',
                  counterText: '',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: const Icon(Icons.link),
                label: Text(_busy ? 'Collegamento…' : 'Collega TV'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
              ),
              const SizedBox(height: 28),
              const Text(
                'Android TV: Centro TV → telefono → Collega Bloomee Remote.\n\nLG webOS: Impostazioni → Telecomando dal cellulare. Usa l’indirizzo e il codice mostrati dalla TV.',
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _player() {
    final duration = _number('durationMs').clamp(0.0, 604800000.0);
    final position = (_seek ?? _number('positionMs')).clamp(0.0, duration);
    final playing = _state?['playing'] == true;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    _fresh ? Icons.wifi : Icons.wifi_off,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_remote!.name)),
                  Text(
                    _fresh ? 'Collegata' : 'Non raggiungibile',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Center(
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    size: 86,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                _state?['title'] as String? ?? 'Nessun brano',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _state?['artist'] as String? ?? '',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              Slider(
                value: position,
                max: duration > 0 ? duration : 1,
                label: _time(position),
                semanticFormatterCallback: _time,
                onChanged: _enabled && duration > 0
                    ? (v) => setState(() => _seek = v)
                    : null,
                onChangeEnd: (v) => _command('seek', v.round()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text(_time(position)), Text(_time(duration))],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    tooltip: 'Casuale',
                    isSelected: _state?['shuffle'] == true,
                    onPressed: _enabled
                        ? () => _command('shuffle', _state?['shuffle'] != true)
                        : null,
                    icon: const Icon(Icons.shuffle),
                  ),
                  IconButton(
                    tooltip: 'Brano precedente',
                    iconSize: 36,
                    onPressed: _enabled ? () => _command('previous') : null,
                    icon: const Icon(Icons.skip_previous),
                  ),
                  IconButton.filled(
                    tooltip: playing ? 'Pausa' : 'Riproduci',
                    iconSize: 44,
                    padding: const EdgeInsets.all(16),
                    onPressed: _enabled
                        ? () => _command(playing ? 'pause' : 'play')
                        : null,
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  ),
                  IconButton(
                    tooltip: 'Brano successivo',
                    iconSize: 36,
                    onPressed: _enabled ? () => _command('next') : null,
                    icon: const Icon(Icons.skip_next),
                  ),
                  IconButton(
                    tooltip: 'Ripeti coda',
                    isSelected: _state?['repeat'] == 'all',
                    onPressed: _enabled
                        ? () => _command(
                            'repeat',
                            _state?['repeat'] == 'all' ? 'off' : 'all',
                          )
                        : null,
                    icon: const Icon(Icons.repeat),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Icon(Icons.volume_down_outlined),
                  Expanded(
                    child: Slider(
                      value: (_volume ?? _number('volume', 1)).clamp(0.0, 1.0),
                      label:
                          '${((_volume ?? _number('volume', 1)) * 100).round()}%',
                      semanticFormatterCallback: (v) =>
                          'Volume ${(v * 100).round()} per cento',
                      onChanged: _enabled
                          ? (v) => setState(() => _volume = v)
                          : null,
                      onChangeEnd: (v) => _command('volume', v),
                    ),
                  ),
                  const Icon(Icons.volume_up_outlined),
                ],
              ),
              const Text('Volume di Bloomee', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _queue() {
    final items = (_state?['queue'] as List?) ?? [];
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'La coda è vuota. Scegli un album o una playlist in Bloomee sulla TV.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Text(
              'In coda · ${_state?['queueTotal'] ?? items.length} brani${items.length < (_state?['queueTotal'] as num? ?? items.length) ? ' · primi 500' : ''}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          );
        }
        final item = items[i - 1] as Map;
        final selected = _state?['index'] == i - 1;
        return ListTile(
          selected: selected,
          enabled: _enabled,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 4,
          ),
          leading: SizedBox(
            width: 28,
            child: selected ? const Icon(Icons.equalizer) : Text('$i'),
          ),
          title: Text(
            item['title'] as String? ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            item['artist'] as String? ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _command('queue', i - 1),
        );
      },
    );
  }
}
