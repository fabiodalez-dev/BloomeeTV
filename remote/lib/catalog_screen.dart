import 'package:flutter/material.dart';
import 'remote_client.dart';

typedef RemoteAction = Future<bool> Function(String action, [Object? value]);

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.remote,
    required this.command,
    this.playlists = false,
    this.active = true,
  });
  final RemoteClient remote;
  final RemoteAction command;
  final bool playlists;
  final bool active;
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _query = TextEditingController();
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _items = [];
  List<String> _warnings = [];
  Map<String, dynamic>? _collection, _home;
  String? _next, _error;
  String _source = 'all', _filter = 'songs';
  bool _loading = false, _acting = false, _searched = false;
  int _epoch = 0;
  int? _total;
  @override
  void initState() {
    super.initState();
    if (widget.playlists && widget.active && widget.remote.hasCatalog) {
      _loadRoot();
    }
  }

  @override
  void didUpdateWidget(covariant CatalogScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playlists &&
        widget.active &&
        !_searched &&
        widget.remote.hasCatalog) {
      _loadRoot();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic> _rootRequest() => widget.playlists
      ? {'kind': 'playlists', 'source': _source}
      : {
          'kind': 'search',
          'query': _query.text.trim(),
          'filter': _filter,
          'source': _source,
        };
  Future<void> _loadRoot() async {
    if (!widget.playlists && _query.text.trim().isEmpty) return;
    _collection = null;
    _home = null;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _load(_rootRequest());
  }

  Future<void> _load(Map<String, dynamic> body, {bool append = false}) async {
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
      if (!append) {
        _items = [];
        _next = null;
        _warnings = [];
      }
    });
    try {
      final data = await widget.remote.browse(body);
      if (!mounted || epoch != _epoch) return;
      final items = (data['items'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        if (append) {
          _items.addAll(items);
        } else {
          _items = items;
        }
        _next = data['next'] as String?;
        _warnings = (data['errors'] as List? ?? [])
            .whereType<String>()
            .toList();
        _total = (data['total'] as num?)?.toInt();
        if (_collection != null) {
          _collection = {
            ..._collection!,
            if (data['title'] != null) 'title': data['title'],
            if (data['editable'] != null) 'editable': data['editable'],
          };
        }
      });
    } catch (e) {
      if (mounted && epoch == _epoch) setState(() => _error = e.toString());
    } finally {
      if (mounted && epoch == _epoch) setState(() => _loading = false);
    }
  }

  Future<void> _open(Map<String, dynamic> item) async {
    if (_loading || _acting) return;
    _home = {
      'items': List<Map<String, dynamic>>.from(_items),
      'next': _next,
      'warnings': List<String>.from(_warnings),
      'offset': _scroll.hasClients ? _scroll.offset : 0.0,
    };
    _collection = Map<String, dynamic>.from(item);
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _load({'kind': 'collection', 'id': item['id']});
  }

  void _back() {
    _epoch++;
    setState(() {
      _items = List<Map<String, dynamic>>.from(_home?['items'] as List? ?? []);
      _next = _home?['next'] as String?;
      _warnings = List<String>.from(_home?['warnings'] as List? ?? []);
      _collection = _home = null;
      _error = null;
      _total = null;
      _loading = false;
    });
  }

  Future<bool> _act(String action, [Object? value]) async {
    if (_acting) return false;
    setState(() => _acting = true);
    try {
      final ok = await widget.command(action, value);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'enqueueItem'
                  ? 'Aggiunto alla coda sulla TV'
                  : ['playItem', 'shuffleItem'].contains(action)
                  ? 'Riproduzione avviata sulla TV'
                  : 'Comando inviato alla TV',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return ok;
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _menu(String action, Map<String, dynamic> item) async {
    if (action == 'open') {
      await _open(item);
      return;
    }
    await _act(action, item['id']);
  }

  Widget _row(Map<String, dynamic> item) {
    final playlist = item['kind'] == 'playlist';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      enabled: !_loading && !_acting,
      leading: Icon(playlist ? Icons.playlist_play : Icons.music_note_outlined),
      title: Text(
        item['title'] as String? ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          item['artist'],
          item['source'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => playlist ? _open(item) : _act('playItem', item['id']),
      trailing: PopupMenuButton<String>(
        tooltip: 'Azioni',
        enabled: !_loading && !_acting,
        onSelected: (v) => _menu(v, item),
        itemBuilder: (_) => [
          if (playlist)
            const PopupMenuItem(value: 'open', child: Text('Apri playlist')),
          const PopupMenuItem(value: 'playItem', child: Text('Riproduci ora')),
          if (playlist)
            const PopupMenuItem(
              value: 'shuffleItem',
              child: Text('Riproduci casuale'),
            ),
          const PopupMenuItem(
            value: 'enqueueItem',
            child: Text('Aggiungi alla coda'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.remote.hasCatalog) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'Aggiorna Bloomee sulla TV per usare ricerca e playlist dal telefono.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return PopScope(
      canPop: !widget.active || _collection == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && widget.active && _collection != null) _back();
      },
      child: CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverList(
            delegate: SliverChildListDelegate([
              if (_collection != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Torna all’elenco',
                        onPressed: _back,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Text(
                          _collection!['title'] as String? ?? 'Playlist',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Aggiorna playlist',
                        onPressed: _loading
                            ? null
                            : () => _load({
                                'kind': 'collection',
                                'id': _collection!['id'],
                              }),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Column(
                    children: [
                      if (!widget.playlists)
                        TextField(
                          controller: _query,
                          maxLength: 160,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _loadRoot(),
                          decoration: InputDecoration(
                            labelText: 'Cerca brani o playlist',
                            counterText: '',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: IconButton(
                              tooltip: 'Cerca',
                              onPressed: _loading ? null : _loadRoot,
                              icon: const Icon(Icons.arrow_forward),
                            ),
                          ),
                        ),
                      if (widget.playlists)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Le tue playlist',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Aggiorna playlist',
                              onPressed: _loading ? null : _loadRoot,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<String>(
                            isExpanded: true,
                            value: _source,
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text(
                                  'Tutte le sorgenti',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'youtube',
                                child: Text(
                                  'YouTube Music',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'jellyfin',
                                child: Text(
                                  'Jellyfin',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'local',
                                child: Text(
                                  'Locale',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                            onChanged: _loading
                                ? null
                                : (v) {
                                    setState(() => _source = v!);
                                    if (widget.playlists ||
                                        _query.text.trim().isNotEmpty) {
                                      _loadRoot();
                                    }
                                  },
                          ),
                          if (!widget.playlists)
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final option in {
                                  'songs': 'Brani',
                                  'playlists': 'Playlist',
                                }.entries)
                                  ChoiceChip(
                                    label: Text(option.value),
                                    selected: _filter == option.key,
                                    onSelected: _loading
                                        ? null
                                        : (_) {
                                            setState(
                                              () => _filter = option.key,
                                            );
                                            if (_query.text.trim().isNotEmpty) {
                                              _loadRoot();
                                            }
                                          },
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (_collection != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: (_acting || _loading || _total == 0)
                            ? null
                            : () => _act('playItem', _collection!['id']),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Riproduci tutto'),
                      ),
                      IconButton(
                        tooltip: 'Riproduci casuale',
                        onPressed: (_acting || _loading || _total == 0)
                            ? null
                            : () => _act('shuffleItem', _collection!['id']),
                        icon: const Icon(Icons.shuffle),
                      ),
                      OutlinedButton.icon(
                        onPressed: (_acting || _loading || _total == 0)
                            ? null
                            : () => _act('enqueueItem', _collection!['id']),
                        icon: const Icon(Icons.queue_music),
                        label: const Text('In coda'),
                      ),
                    ],
                  ),
                ),
              if (_loading || _acting)
                const LinearProgressIndicator(minHeight: 2),
              if (_error != null || _warnings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      for (final warning in _warnings) Text(warning),
                      if (_error != null)
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => _collection != null
                                    ? _load({
                                        'kind': 'collection',
                                        'id': _collection!['id'],
                                      })
                                    : _loadRoot(),
                          child: const Text('Riprova'),
                        ),
                    ],
                  ),
                ),
              if (_total != null && _collection != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('$_total ${_total == 1 ? 'brano' : 'brani'}'),
                  ),
                ),
            ]),
          ),
          if (_items.isEmpty && !_loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    _error != null
                        ? ''
                        : !_searched
                        ? 'Cerca un titolo o un artista e scegli cosa ascoltare sulla TV.'
                        : widget.playlists && _collection == null
                        ? 'Nessuna playlist disponibile. Collega il tuo account YouTube Music o Jellyfin nelle impostazioni della TV.'
                        : _collection != null
                        ? 'Questa playlist è vuota.'
                        : 'Nessun risultato. Prova un’altra ricerca o sorgente.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => i < _items.length
                    ? _row(_items[i])
                    : Padding(
                        padding: const EdgeInsets.all(20),
                        child: OutlinedButton(
                          onPressed: _loading
                              ? null
                              : () => _load({'cursor': _next}, append: true),
                          child: const Text('Altri risultati'),
                        ),
                      ),
                childCount: _items.length + (_next != null ? 1 : 0),
              ),
            ),
        ],
      ),
    );
  }
}
