import 'package:flutter/material.dart';

/// Mounted after the intro. The initializer is invoked once, never from build.
class FlowStartupGate extends StatefulWidget {
  final Future<void>? initialization;
  final Future<void> Function()? initialize;
  final Widget destination;
  final Widget Function(BuildContext context, Object error) errorBuilder;
  const FlowStartupGate({
    super.key,
    this.initialization,
    this.initialize,
    required this.destination,
    required this.errorBuilder,
  });
  @override
  State<FlowStartupGate> createState() => _FlowStartupGateState();
}

class _FlowStartupGateState extends State<FlowStartupGate> {
  late final Future<void> _ready;
  @override
  void initState() {
    super.initState();
    _ready =
        widget.initialization ??
        Future<void>.sync(() async {
          if (widget.initialize != null) await widget.initialize!();
        });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: _ready,
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return widget.errorBuilder(context, snapshot.error!);
      if (snapshot.connectionState != ConnectionState.done)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return widget.destination;
    },
  );
}
