import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A deliberately tall scrollable screen whose only purpose is to exercise
/// the exploration agent's `core.scroll` tool on-device (lenny-cx6.56).
///
/// The "Accept Terms" switch lives at the very bottom of a list of
/// fixed-height sections that overflow any phone or tablet viewport, so the
/// switch is reachable only after scrolling down. Success is observable the
/// same way the Dark Theme scenario is: the switch's semantics node reports
/// `on` once toggled.
class TermsScreen extends StatefulWidget {
  const TermsScreen({super.key});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      // 12 × 200px sections (~2400px) guarantee the body overflows the
      // viewport on phone and iPad alike, forcing a scroll to reach the
      // switch below them.
      body: ListView(
        children: <Widget>[
          for (var i = 0; i < 12; i++)
            SizedBox(
              height: 200,
              child: Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Center(child: Text('Section ${i + 1}')),
              ),
            ),
          const Divider(),
          SwitchListTile(
            title: const Text('Accept Terms'),
            value: _accepted,
            onChanged: (bool v) => setState(() => _accepted = v),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
