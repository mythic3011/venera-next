part of 'reader.dart';

enum ReaderWindowClass { compact, medium, wide }

ReaderWindowClass classifyReaderWidth(double width) {
  if (width < 600) return ReaderWindowClass.compact;
  if (width < 840) return ReaderWindowClass.medium;
  return ReaderWindowClass.wide;
}

enum ReaderPanelType { none, chapters, quickControls, info, downloads }

class ReaderPanelState extends ChangeNotifier {
  ReaderPanelType _panel = ReaderPanelType.none;

  ReaderPanelType get panel => _panel;

  bool get hasOpenPanel => _panel != ReaderPanelType.none;

  void open(ReaderPanelType panel) {
    if (_panel == panel) return;
    _panel = panel;
    notifyListeners();
  }

  void close() {
    if (_panel == ReaderPanelType.none) return;
    _panel = ReaderPanelType.none;
    notifyListeners();
  }
}

enum AutoTurnState { off, running, paused, blocked }

enum AutoTurnBlockReason {
  panelOpen,
  pageLoading,
  zooming,
  panning,
  dragging,
  appInactive,
  chapterEnded,
}

enum AutoTurnChapterEndPolicy { stop, continueNextChapter, ask }

class AutoTurnController extends ChangeNotifier {
  AutoTurnController({
    required TickerProvider vsync,
    required this.intervalSeconds,
    required this.canTurnPage,
    required this.onTurnPage,
  }) : _animation = AnimationController(vsync: vsync) {
    _animation.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      if (_state != AutoTurnState.running) return;
      if (_blockReasons.isNotEmpty) return;
      if (!canTurnPage()) return;
      onTurnPage();
      _startCountdown();
    });
    _animation.addListener(notifyListeners);
  }

  final int Function() intervalSeconds;
  final bool Function() canTurnPage;
  final VoidCallback onTurnPage;

  final AnimationController _animation;
  final Set<AutoTurnBlockReason> _blockReasons = <AutoTurnBlockReason>{};
  AutoTurnState _state = AutoTurnState.off;
  AutoTurnChapterEndPolicy chapterEndPolicy = AutoTurnChapterEndPolicy.stop;

  AutoTurnState get state => _state;

  Set<AutoTurnBlockReason> get blockReasons => Set.unmodifiable(_blockReasons);

  bool get isActive =>
      _state == AutoTurnState.running || _state == AutoTurnState.blocked;

  double get progress => _animation.value;

  void toggle() {
    if (_state == AutoTurnState.off) {
      start();
    } else {
      stop();
    }
  }

  void start() {
    if (_state == AutoTurnState.running || _state == AutoTurnState.blocked) {
      return;
    }
    _state = _blockReasons.isEmpty
        ? AutoTurnState.running
        : AutoTurnState.blocked;
    _startCountdown();
    notifyListeners();
  }

  void stop() {
    _animation.stop();
    _animation.value = 0;
    _state = AutoTurnState.off;
    _blockReasons.remove(AutoTurnBlockReason.chapterEnded);
    notifyListeners();
  }

  void pause() {
    if (_state != AutoTurnState.running) return;
    _animation.stop();
    _state = AutoTurnState.paused;
    notifyListeners();
  }

  void resume() {
    if (_state != AutoTurnState.paused) return;
    _state = _blockReasons.isEmpty
        ? AutoTurnState.running
        : AutoTurnState.blocked;
    if (_state == AutoTurnState.running) {
      _animation.forward();
    }
    notifyListeners();
  }

  void resetCountdown() {
    if (_state != AutoTurnState.running) return;
    _startCountdown();
  }

  void setBlocked(AutoTurnBlockReason reason, bool blocked) {
    final changed = blocked
        ? _blockReasons.add(reason)
        : _blockReasons.remove(reason);
    if (!changed) return;
    if (_state == AutoTurnState.running && _blockReasons.isNotEmpty) {
      _state = AutoTurnState.blocked;
      _animation.stop();
    } else if (_state == AutoTurnState.blocked && _blockReasons.isEmpty) {
      _state = AutoTurnState.running;
      _animation.forward();
    }
    notifyListeners();
  }

  void setChapterEnd() {
    switch (chapterEndPolicy) {
      case AutoTurnChapterEndPolicy.stop:
      case AutoTurnChapterEndPolicy.ask:
        setBlocked(AutoTurnBlockReason.chapterEnded, true);
      case AutoTurnChapterEndPolicy.continueNextChapter:
        break;
    }
  }

  void _startCountdown() {
    final seconds = intervalSeconds().clamp(1, 120);
    _animation
      ..duration = Duration(seconds: seconds)
      ..value = 0
      ..forward();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }
}
