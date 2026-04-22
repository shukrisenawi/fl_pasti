import 'package:flutter_test/flutter_test.dart';
import 'package:pasti/src/fcm_sync_message.dart';

void main() {
  test('creates local notification payload from create sync data', () {
    final payload = FcmSyncMessage.fromData({
      'sync_action': 'create',
      'notification_id': 'notif-123',
      'notification_title': 'Tajuk',
      'notification_message': 'Mesej',
      'url': '/claims',
    });

    expect(payload, isNotNull);
    expect(payload!.action, FcmSyncAction.create);
    expect(payload.notificationId, 'notif-123');
    expect(payload.title, 'Tajuk');
    expect(payload.body, 'Mesej');
    expect(payload.url, '/claims');
  });

  test('creates removal payload from read sync data', () {
    final payload = FcmSyncMessage.fromData({
      'sync_action': 'read',
      'notification_id': 'notif-123',
    });

    expect(payload, isNotNull);
    expect(payload!.action, FcmSyncAction.read);
    expect(payload.notificationId, 'notif-123');
  });
}
