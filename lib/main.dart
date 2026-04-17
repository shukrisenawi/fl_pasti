import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'web_redirect_stub.dart'
    if (dart.library.html) 'web_redirect_web.dart';

const String kAppTitle = 'PASTI SIK';
const String kInitialUrl = 'https://pastikawasansik.my.id';
const String kFrameTitle = 'PASTI KAWASAN SIK';
const Color kFrameColor = Color(0xFF15803D);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _enableFullscreenMode();
  runApp(const PastiApp());
}

Future<void> _enableFullscreenMode() {
  return SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );
}

class PastiApp extends StatelessWidget {
  const PastiApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: kAppTitle,
      theme: ThemeData(
        scaffoldBackgroundColor: kFrameColor,
      ),
      home: kIsWeb ? const WebRedirectScreen() : const WebAppScreen(),
    );
  }
}

class WebRedirectScreen extends StatefulWidget {
  const WebRedirectScreen({Key? key}) : super(key: key);

  @override
  State<WebRedirectScreen> createState() => _WebRedirectScreenState();
}

class _WebRedirectScreenState extends State<WebRedirectScreen> {
  bool _launchFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openWebsite();
    });
  }

  Future<void> _openWebsite() async {
    final opened = await openInSameTab(kInitialUrl);

    if (!opened && mounted) {
      setState(() {
        _launchFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _FrameScaffold(
      child: Center(
        child: _launchFailed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      'Tak dapat buka laman secara automatik.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _openWebsite,
                    child: const Text('Buka Laman'),
                  ),
                ],
              )
            : const _LoadingOverlay(),
      ),
    );
  }
}

class WebAppScreen extends StatefulWidget {
  const WebAppScreen({Key? key}) : super(key: key);

  @override
  State<WebAppScreen> createState() => _WebAppScreenState();
}

class _WebAppScreenState extends State<WebAppScreen>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!_isLoading && mounted) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          onPageFinished: (_) {
            if (_isLoading && mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _enableFullscreenMode();
          },
        ),
      )
      ..loadRequest(Uri.parse(kInitialUrl));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enableFullscreenMode();
    }
  }

  Future<bool> _handleBackPressed() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBackPressed,
      child: _FrameScaffold(
        child: Stack(
          fit: StackFit.expand,
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading) const _LoadingOverlay(),
          ],
        ),
      ),
    );
  }
}

class _FrameScaffold extends StatelessWidget {
  const _FrameScaffold({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return Scaffold(
      body: Stack(
        children: [
          Positioned(
            top: padding.top + 6,
            left: 12,
            right: 12,
            child: const _FrameHeader(),
          ),
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(top: padding.top + 28),
              child: SafeArea(
                top: false,
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FrameHeader extends StatefulWidget {
  const _FrameHeader();

  @override
  State<_FrameHeader> createState() => _FrameHeaderState();
}

class _FrameHeaderState extends State<_FrameHeader> {
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _scheduleNextTick();
  }

  void _scheduleNextTick() {
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted) {
        return;
      }

      setState(() {
        _now = DateTime.now();
      });

      _scheduleNextTick();
    });
  }

  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    const headerStyle = TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    );

    return Row(
      children: [
        const Expanded(
          child: Text(
            kFrameTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: headerStyle,
          ),
        ),
        Text(
          _formatTime(_now),
          style: headerStyle,
        ),
      ],
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: Opacity(
            opacity: 0.14,
            child: Image.asset(
              'assets/branding/logo-pasti.png',
              width: 190,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}
