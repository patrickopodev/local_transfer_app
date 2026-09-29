import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app/app_controller.dart';
import 'app/app_shell.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Ads are optional: never let a failed Mobile Ads init (no Play Services,
  // no network, inactive App ID) prevent the app from starting. An unguarded
  // await here throws before runApp() and looks like "crash on open".
  try {
    await MobileAds.instance.initialize();
  } catch (_) {
    // Ignore — AdBanner already shows an empty placeholder when ads fail.
  }
  runApp(const LocalDropApp());
}

class LocalDropApp extends StatelessWidget {
  const LocalDropApp({super.key, this.autoStart = true});

  /// Whether to begin receiving/advertising on launch. Disable in tests.
  final bool autoStart;

  @override
  Widget build(BuildContext context) {
    return LocalDropAppRoot(autoStart: autoStart);
  }
}

/// Wires the [AppController] (services + state) into the widget tree.
class LocalDropAppRoot extends StatefulWidget {
  const LocalDropAppRoot({super.key, this.autoStart = true});

  final bool autoStart;

  @override
  State<LocalDropAppRoot> createState() => _LocalDropAppRootState();
}

class _LocalDropAppRootState extends State<LocalDropAppRoot> {
  final AppController _controller = AppController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _controller.init();
    } catch (_) {
      // init() already swallows per-step failures, but never let anything
      // here escape as an unhandled async exception on launch.
      return;
    }
    if (widget.autoStart) {
      _controller.start().catchError((Object _) {
        // Networking may be unavailable (e.g. bad permissions); the UI
        // still works and RECEIVE can be retried from the home screen.
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalDrop',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: AppShell(controller: _controller),
    );
  }
}