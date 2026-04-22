import 'dart:convert';

enum AppBridgeMessageType { authUser, unknown }

class AuthenticatedWebUser {
  const AuthenticatedWebUser({
    required this.userId,
    required this.username,
    required this.displayName,
  });

  factory AuthenticatedWebUser.fromMap(Map<String, dynamic> map) {
    return AuthenticatedWebUser(
      userId: '${map['user_id'] ?? map['id'] ?? ''}',
      username: '${map['username'] ?? map['email'] ?? ''}',
      displayName: '${map['display_name'] ?? map['username'] ?? ''}',
    );
  }

  final String userId;
  final String username;
  final String displayName;
}

class AppBridgeMessage {
  const AppBridgeMessage({required this.type, required this.user});

  factory AppBridgeMessage.authUser(AuthenticatedWebUser? user) {
    return AppBridgeMessage(type: AppBridgeMessageType.authUser, user: user);
  }

  static AppBridgeMessage? tryParse(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final type = decoded['type']?.toString();
    if (type == 'lr-pasti-auth-user') {
      final user = decoded['user'];
      return AppBridgeMessage.authUser(
        user is Map<String, dynamic>
            ? AuthenticatedWebUser.fromMap(user)
            : null,
      );
    }

    return const AppBridgeMessage(
      type: AppBridgeMessageType.unknown,
      user: null,
    );
  }

  final AppBridgeMessageType type;
  final AuthenticatedWebUser? user;
}
