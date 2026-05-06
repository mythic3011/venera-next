import 'package:flutter/material.dart';
import 'package:venera/features/reader_next/presentation/shell_controller.dart';
import 'package:venera/features/reader_next/runtime/runtime.dart';
import 'package:venera/foundation/diagnostics/diagnostics.dart';

class ReaderNextShellPage extends StatefulWidget {
  const ReaderNextShellPage({
    super.key,
    required this.runtime,
    required this.sourceKey,
  });

  final ReaderNextRuntime runtime;
  final String sourceKey;

  @override
  State<ReaderNextShellPage> createState() => _ReaderNextShellPageState();
}

class _ReaderNextShellPageState extends State<ReaderNextShellPage> {
  late final ReaderNextShellController _controller;
  final TextEditingController _keywordController = TextEditingController();
  String? _routeNameSnapshot;

  @override
  void initState() {
    super.initState();
    _controller = ReaderNextShellController(
      runtime: widget.runtime,
      sourceKey: widget.sourceKey,
    )..addListener(_onStateChanged);
    _recordShellPageLifecycle('reader.shell.page.init');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeNameSnapshot = ModalRoute.of(context)?.settings.name;
  }

  @override
  void dispose() {
    _recordShellPageLifecycle('reader.shell.page.dispose');
    _controller.removeListener(_onStateChanged);
    _controller.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    _recordShellPageLifecycle('reader.shell.page.stateChanged');
    if (mounted) {
      setState(() {});
    }
  }

  void _recordShellPageLifecycle(String event) {
    AppDiagnostics.trace(
      'reader.lifecycle',
      event,
      data: {
        'owner': 'ReaderNextShellPage',
        'sourceKey': widget.sourceKey,
        'routeName': _routeNameSnapshot,
        'mounted': mounted,
        'widgetHashCode': widget.hashCode,
        'stateHashCode': hashCode,
        'phase': _controller.state.phase.name,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    return Scaffold(
      appBar: AppBar(title: const Text('Reader Next')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('reader-next-search-input'),
                    controller: _keywordController,
                    decoration: const InputDecoration(
                      hintText: 'Search keyword',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const Key('reader-next-search-button'),
                  onPressed: () => _controller.search(_keywordController.text),
                  child: const Text('Search'),
                ),
              ],
            ),
          ),
          if (state.phase == ReaderNextShellPhase.loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  key: Key('reader-next-loading'),
                ),
              ),
            )
          else if (state.phase == ReaderNextShellPhase.error &&
              state.error != null)
            Expanded(
              child: Center(
                child: Text(
                  '${state.error!.title}: ${state.error!.userMessage}',
                  key: const Key('reader-next-error'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                children: [
                  ...state.searchResults.map(
                    (item) => ListTile(
                      key: Key('reader-next-result-${item.upstreamComicRefId}'),
                      title: Text(item.title),
                      subtitle: Text(item.upstreamComicRefId),
                      onTap: () => _controller.selectComic(item),
                    ),
                  ),
                  if (state.selectedDetail != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            state.selectedDetail!.title,
                            key: const Key('reader-next-detail-title'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Chapters: ${state.selectedDetail!.chapters.length}',
                            key: const Key('reader-next-detail-chapter-count'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'First page images: ${state.pageImages.length}',
                            key: const Key(
                              'reader-next-first-page-image-count',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
