import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'src/app_bridge_message.dart';
import 'src/fcm_sync_message.dart';
import 'src/notification_id_mapper.dart';
import 'web_redirect_stub.dart' if (dart.library.html) 'web_redirect_web.dart';

const String kAppTitle = 'PASTI SIK';
const String kInitialUrl = 'https://pastikawasansik.my.id';

final ValueNotifier<String?> _pendingNotificationUrl = ValueNotifier(null);

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await AppNotificationService.initialize();
  await AppNotificationService.handleRemoteMessage(message);
}

@pragma('vm:entry-point')
void _onBackgroundNotificationTap(NotificationResponse response) {
  final url = AppNotificationService.extractUrlFromPayload(response.payload);
  if (url != null && url.isNotEmpty) {
    _pendingNotificationUrl.value = url;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await AppNotificationService.initialize();
  }

  runApp(const PastiApp());
}

class PastiApp extends StatelessWidget {
  const PastiApp({super.key, this.homeOverride});

  final Widget? homeOverride;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: kAppTitle,
      theme: ThemeData(scaffoldBackgroundColor: Colors.white),
      home:
          homeOverride ??
          (kIsWeb ? const WebRedirectScreen() : const WebAppScreen()),
    );
  }
}

class WebRedirectScreen extends StatefulWidget {
  const WebRedirectScreen({super.key});

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
  const WebAppScreen({super.key});

  @override
  State<WebAppScreen> createState() => _WebAppScreenState();
}

class _WebAppScreenState extends State<WebAppScreen> {
  late final WebViewController _controller;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  AuthenticatedWebUser? _authenticatedUser;
  String? _fcmToken;
  String? _lastSyncedRegistration;
  bool _isLoading = true;
  bool _pageLoaded = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'ReactNativeWebView',
        onMessageReceived: (JavaScriptMessage message) {
          _handleBridgeMessage(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _pageLoaded = false;
            if (!_isLoading && mounted) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          onPageFinished: (_) async {
            _pageLoaded = true;
            if (_isLoading && mounted) {
              setState(() {
                _isLoading = false;
              });
            }

            await _syncRegisteredToken();
            await _consumePendingNotificationUrl();
          },
        ),
      )
      ..loadRequest(Uri.parse(kInitialUrl));

    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      platformController.setOnShowFileSelector(_handleShowFileSelector);
    }

    _pendingNotificationUrl.addListener(_consumePendingNotificationUrl);
    _initializePushMessaging();
  }

  Future<void> _initializePushMessaging() async {
    if (kIsWeb) {
      return;
    }

    await AppNotificationService.requestPermissions();

    _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(
      AppNotificationService.handleRemoteMessage,
    );

    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen((String nextToken) async {
          final previousToken = _fcmToken;
          _fcmToken = nextToken;
          _lastSyncedRegistration = null;

          if (previousToken != null && previousToken != nextToken) {
            await _unregisterToken(previousToken);
          }

          await _syncRegisteredToken();
        });

    _fcmToken = await FirebaseMessaging.instance.getToken();
    await _syncRegisteredToken();
  }

  void _handleBridgeMessage(String rawMessage) {
    AppBridgeMessage? message;

    try {
      message = AppBridgeMessage.tryParse(rawMessage);
    } catch (_) {
      return;
    }

    if (message == null || message.type != AppBridgeMessageType.authUser) {
      return;
    }

    _authenticatedUser = message.user;
    _lastSyncedRegistration = null;

    if (_authenticatedUser == null) {
      final token = _fcmToken;
      if (token != null) {
        unawaited(_unregisterToken(token));
      }
      return;
    }

    unawaited(_syncRegisteredToken());
  }

  Future<void> _syncRegisteredToken() async {
    final token = _fcmToken;
    final user = _authenticatedUser;
    if (!_pageLoaded || token == null || token.isEmpty || user == null) {
      return;
    }

    final registrationKey = '${user.userId}:$token';
    if (_lastSyncedRegistration == registrationKey) {
      return;
    }

    await _sendTokenMutation(
      method: 'POST',
      payload: <String, String>{
        'fcm_token': token,
        'device_name': 'PASTI Android WebView',
        'platform': 'android-webview',
      },
    );

    _lastSyncedRegistration = registrationKey;
  }

  Future<void> _unregisterToken(String token) async {
    if (!_pageLoaded || token.isEmpty) {
      return;
    }

    await _sendTokenMutation(
      method: 'DELETE',
      payload: <String, String>{'fcm_token': token},
    );
  }

  Future<void> _sendTokenMutation({
    required String method,
    required Map<String, String> payload,
  }) async {
    final requestBody = jsonEncode(payload);
    final script =
        '''
      (() => {
        const csrf = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') ?? '';
        return fetch('/mobile/fcm-token', {
          method: ${jsonEncode(method)},
          credentials: 'same-origin',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-CSRF-TOKEN': csrf,
            'X-Requested-With': 'XMLHttpRequest'
          },
          body: ${jsonEncode(requestBody)}
        }).then(() => true).catch(() => false);
      })();
    ''';

    try {
      await _controller.runJavaScriptReturningResult(script);
    } catch (_) {
      // Abaikan kegagalan sementara; kita akan cuba lagi pada muatan halaman seterusnya.
    }
  }

  Future<void> _consumePendingNotificationUrl() async {
    final pendingUrl = _pendingNotificationUrl.value;
    if (pendingUrl == null || pendingUrl.isEmpty) {
      return;
    }

    _pendingNotificationUrl.value = null;

    try {
      await _controller.loadRequest(Uri.parse(_resolveUrl(pendingUrl)));
    } catch (_) {
      // Kekalkan pengalaman asas walaupun URL notifikasi tidak sah.
    }
  }

  String _resolveUrl(String url) {
    final parsed = Uri.tryParse(url);
    if (parsed != null && parsed.hasScheme) {
      return parsed.toString();
    }

    return Uri.parse(kInitialUrl).resolve(url).toString();
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

    return _PickerConfig(type: FileType.custom, allowedExtensions: extensions);
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
  void dispose() {
    _foregroundMessageSubscription?.cancel();
    _tokenRefreshSubscription?.cancel();
    _pendingNotificationUrl.removeListener(_consumePendingNotificationUrl);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) {
          return;
        }

        final shouldPop = await _handleBackPressed();
        if (shouldPop) {
          await SystemNavigator.pop();
        }
      },
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

class AppNotificationService {
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'pasti_notifications',
    'Notifikasi PASTI',
    description: 'Notifikasi utama untuk aplikasi PASTI.',
    importance: Importance.high,
  );

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final url = extractUrlFromPayload(response.payload);
        if (url != null && url.isNotEmpty) {
          _pendingNotificationUrl.value = url;
        }
      },
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_channel);

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final launchUrl = extractUrlFromPayload(
      launchDetails?.notificationResponse?.payload,
    );
    if (launchUrl != null && launchUrl.isNotEmpty) {
      _pendingNotificationUrl.value = launchUrl;
    }

    _initialized = true;
  }

  static Future<void> requestPermissions() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.requestNotificationsPermission();
  }

  static Future<void> handleRemoteMessage(RemoteMessage message) async {
    final syncMessage = FcmSyncMessage.fromData(message.data);
    if (syncMessage == null) {
      return;
    }

    await initialize();

    switch (syncMessage.action) {
      case FcmSyncAction.create:
        if (syncMessage.title.isEmpty && syncMessage.body.isEmpty) {
          return;
        }

        await _plugin.show(
          NotificationIdMapper.fromNotificationId(syncMessage.notificationId),
          syncMessage.title,
          syncMessage.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          payload: jsonEncode({
            'url': syncMessage.url,
            'notification_id': syncMessage.notificationId,
          }),
        );
        return;
      case FcmSyncAction.read:
      case FcmSyncAction.remove:
        await _plugin.cancel(
          NotificationIdMapper.fromNotificationId(syncMessage.notificationId),
        );
        return;
      case FcmSyncAction.unknown:
        return;
    }
  }

  static String? extractUrlFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded['url']?.toString();
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}

class _PickerConfig {
  const _PickerConfig({required this.type, this.allowedExtensions});

  final FileType type;
  final List<String>? allowedExtensions;
}

class _FrameScaffold extends StatelessWidget {
  const _FrameScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: child));
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
        const Center(child: CircularProgressIndicator(color: Colors.white)),
      ],
    );
  }
}
