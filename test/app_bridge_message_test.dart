import 'package:flutter_test/flutter_test.dart';
import 'package:pasti/src/app_bridge_message.dart';

void main() {
  test('parses authenticated user payload from webview message', () {
    final message = AppBridgeMessage.tryParse(
      '{"type":"lr-pasti-auth-user","user":{"user_id":42,"username":"guru@app.test","display_name":"Guru Test"}}',
    );

    expect(message, isNotNull);
    expect(message!.type, AppBridgeMessageType.authUser);
    expect(message.user, isNotNull);
    expect(message.user!.userId, '42');
    expect(message.user!.username, 'guru@app.test');
    expect(message.user!.displayName, 'Guru Test');
  });

  test('parses logout style payload when user is null', () {
    final message = AppBridgeMessage.tryParse(
      '{"type":"lr-pasti-auth-user","user":null}',
    );

    expect(message, isNotNull);
    expect(message!.type, AppBridgeMessageType.authUser);
    expect(message.user, isNull);
  });
}
