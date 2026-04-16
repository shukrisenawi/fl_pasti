import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'web_redirect_stub.dart'
    if (dart.library.html) 'web_redirect_web.dart';

const String kAppTitle = 'Pasti Kawasan Sik';
const String kInitialUrl = 'https://pastikawasansik.my.id';

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
        scaffoldBackgroundColor: Colors.black,
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
    return Scaffold(
      body: ColoredBox(
        color: Colors.black,
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
              : const CircularProgressIndicator(
                  color: Colors.white,
                ),
        ),
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
  final Completer<WebViewController> _controller =
      Completer<WebViewController>();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    final controller = await _controller.future;
    if (await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBackPressed,
      child: Scaffold(
        body: Stack(
          children: [
            WebView(
              initialUrl: kInitialUrl,
              javascriptMode: JavascriptMode.unrestricted,
              backgroundColor: Colors.black,
              gestureNavigationEnabled: true,
              onWebViewCreated: (controller) {
                if (!_controller.isCompleted) {
                  _controller.complete(controller);
                }
              },
              onPageStarted: (_) {
                if (!_isLoading) {
                  setState(() {
                    _isLoading = true;
                  });
                }
              },
              onPageFinished: (_) {
                if (_isLoading) {
                  setState(() {
                    _isLoading = false;
                  });
                }
                _enableFullscreenMode();
              },
            ),
            if (_isLoading)
              const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
