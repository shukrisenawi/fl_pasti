import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'web_redirect_stub.dart'
    if (dart.library.html) 'web_redirect_web.dart';

const String kAppTitle = 'PASTI SIK';
const String kInitialUrl = 'https://pastikawasansik.my.id';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PastiApp());
}

class PastiApp extends StatelessWidget {
  const PastiApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: kAppTitle,
      theme: ThemeData(
        scaffoldBackgroundColor: Colors.white,
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

class _WebAppScreenState extends State<WebAppScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

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
          },
        ),
      )
      ..loadRequest(Uri.parse(kInitialUrl));

    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      platformController.setOnShowFileSelector(_handleShowFileSelector);
    }
  }

  Future<List<String>> _handleShowFileSelector(
    FileSelectorParams params,
  ) async {
    final pickerConfig = _buildPickerConfig(params.acceptTypes);
    final result = await FilePicker.pickFiles(
      allowMultiple: params.mode == FileSelectorMode.openMultiple,
      type: pickerConfig.type,
      allowedExtensions: pickerConfig.allowedExtensions,
    );

    if (result == null) {
      return <String>[];
    }

    return result.files
        .map((file) => file.identifier ?? file.path)
        .whereType<String>()
        .toList();
  }

  _PickerConfig _buildPickerConfig(List<String> acceptTypes) {
    final normalizedTypes = acceptTypes
        .map((type) => type.trim().toLowerCase())
        .where((type) => type.isNotEmpty)
        .toList();

    if (normalizedTypes.isEmpty) {
      return const _PickerConfig(type: FileType.any);
    }

    final onlyImages = normalizedTypes.every(
      (type) => type == 'image/*' || type.startsWith('image/'),
    );
    if (onlyImages) {
      return const _PickerConfig(type: FileType.image);
    }

    final extensions = normalizedTypes
        .map(_acceptTypeToExtension)
        .whereType<String>()
        .toSet()
        .toList();

    if (extensions.isEmpty) {
      return const _PickerConfig(type: FileType.any);
    }

    return _PickerConfig(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
  }

  String? _acceptTypeToExtension(String acceptType) {
    if (acceptType.startsWith('.')) {
      return acceptType.substring(1);
    }

    switch (acceptType) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'application/pdf':
        return 'pdf';
    }

    return null;
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

class _PickerConfig {
  const _PickerConfig({
    required this.type,
    this.allowedExtensions,
  });

  final FileType type;
  final List<String>? allowedExtensions;
}

class _FrameScaffold extends StatelessWidget {
  const _FrameScaffold({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: child,
      ),
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
