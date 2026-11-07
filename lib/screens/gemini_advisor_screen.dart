import 'package:flutter/material.dart';

import '../controllers/gemini_advisor_controller.dart';
import '../widgets/gemini_advisor_panel.dart';

class GeminiAdvisorScreen extends StatefulWidget {
  final String userId;
  final GeminiAdvisorController? controller;

  const GeminiAdvisorScreen({super.key, required this.userId, this.controller});

  @override
  State<GeminiAdvisorScreen> createState() => _GeminiAdvisorScreenState();
}

class _GeminiAdvisorScreenState extends State<GeminiAdvisorScreen> {
  late final GeminiAdvisorController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller =
        widget.controller ?? GeminiAdvisorController.forUser(widget.userId);
    assert(_controller.userId == widget.userId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ripple')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: GeminiAdvisorPanel(controller: _controller),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }
}
