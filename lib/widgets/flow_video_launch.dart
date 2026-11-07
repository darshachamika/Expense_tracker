import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'flow_app_water.dart';

/// Small injectable boundary so launch behavior can be tested without a codec.
abstract class FlowIntroPlayback extends ChangeNotifier {
  bool get ready;
  bool get completed;
  bool get failed;
  Size get size;
  Future<void> prepare();
  Future<void> play();
  Future<void> pause();
  Widget video();
}

class FlowAssetPlayback extends FlowIntroPlayback {
  final VideoPlayerController _controller = VideoPlayerController.asset(
    'assets/videos/flow_intro.mp4',
  );
  bool _disposed = false;
  FlowAssetPlayback() {
    _controller.addListener(_changed);
  }
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  bool get ready => _controller.value.isInitialized;
  @override
  bool get completed =>
      ready &&
      _controller.value.duration > Duration.zero &&
      _controller.value.position >= _controller.value.duration;
  @override
  bool get failed => _controller.value.hasError;
  @override
  Size get size => _controller.value.size;
  @override
  Future<void> prepare() async {
    await _controller.initialize();
    if (_disposed) return;
    await _controller.setVolume(0);
    if (_disposed) return;
    await _controller.setLooping(false);
  }

  @override
  Future<void> play() => _disposed ? Future<void>.value() : _controller.play();
  @override
  Future<void> pause() =>
      _disposed ? Future<void>.value() : _controller.pause();
  @override
  Widget video() => VideoPlayer(_controller);
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _controller.removeListener(_changed);
    unawaited(_controller.dispose());
    super.dispose();
  }
}

class FlowVideoLaunch extends StatefulWidget {
  final Widget child;
  final FlowIntroPlayback Function()? createPlayback;
  final Duration timeout;
  const FlowVideoLaunch({
    super.key,
    required this.child,
    this.createPlayback,
    this.timeout = const Duration(seconds: 30),
  });
  @override
  State<FlowVideoLaunch> createState() => _FlowVideoLaunchState();
}

class _FlowVideoLaunchState extends State<FlowVideoLaunch>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  FlowIntroPlayback? _playback;
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );
  Timer? _watchdog;
  bool _started = false;
  bool _ready = false;
  bool _finishing = false;
  bool _showIntro = true;
  bool _released = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FlowWaterMotion.setIntroVisible(true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    const forceIntro = bool.fromEnvironment('FLOW_FORCE_INTRO');
    if (MediaQuery.disableAnimationsOf(context) && !forceIntro) {
      _showIntro = false;
      FlowWaterMotion.setIntroVisible(false);
      _finishing = true;
      _fade.value = 1;
      _watchdog?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) => _release());
      return;
    }
    if (!_started && !_finishing) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_finishing) unawaited(_start());
      });
    }
  }

  Future<void> _start() async {
    try {
      _playback = (widget.createPlayback ?? FlowAssetPlayback.new)();
      _playback!.addListener(_changed);
      _watchdog = Timer(widget.timeout, () => unawaited(_finish()));
      await _playback!.prepare();
      if (!mounted || _finishing) return;
      setState(() => _ready = _playback!.ready);
      await _playback!.play();
    } catch (_) {
      if (mounted) unawaited(_finish());
    }
  }

  void _changed() {
    if (!mounted || _finishing || _released) return;
    if (_playback!.failed || _playback!.completed) {
      unawaited(_finish());
    } else if (_ready != _playback!.ready) {
      setState(() => _ready = _playback!.ready);
    }
  }

  Future<void> _finish() async {
    if (!mounted || _finishing) return;
    _finishing = true;
    _watchdog?.cancel();
    unawaited(_pause());
    await _fade.forward();
    if (!mounted) return;
    setState(() => _showIntro = false);
    FlowWaterMotion.setIntroVisible(false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _release());
  }

  Future<void> _pause() async {
    try {
      await _playback?.pause();
    } catch (_) {
      /* A failed decoder must not block the destination. */
    }
  }

  void _release() {
    if (_released) return;
    _released = true;
    _playback?.removeListener(_changed);
    _playback?.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_finishing || !_ready || _released) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_resume());
    } else {
      unawaited(_pause());
    }
  }

  Future<void> _resume() async {
    try {
      await _playback?.play();
    } catch (_) {
      if (mounted) unawaited(_finish());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlowWaterMotion.setIntroVisible(false);
    _watchdog?.cancel();
    _release();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _fade,
    child: widget.child,
    builder: (context, child) => Stack(
      fit: StackFit.expand,
      children: [
        // The destination has no Element/State until playback has finished.
        if (!_showIntro) child!,
        if (_showIntro)
          const Positioned.fill(child: ColoredBox(color: Color(0xFF031D41))),
        if (_showIntro)
          Positioned.fill(
            child: Opacity(
              opacity: 1 - _fade.value,
              child: Material(
                color: const Color(0xFF031D41),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_ready && _playback != null && !_released)
                      ClipRect(
                        child: SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _playback!.size.width,
                              height: _playback!.size.height,
                              child: _playback!.video(),
                            ),
                          ),
                        ),
                      )
                    else
                      const ColoredBox(color: Color(0xFF031D41)),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
