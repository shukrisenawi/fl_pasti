enum FcmSyncAction { create, read, remove, unknown }

class FcmSyncMessage {
  const FcmSyncMessage({
    required this.action,
    required this.notificationId,
    required this.title,
    required this.body,
    required this.url,
  });

  static FcmSyncMessage? fromData(Map<String, dynamic> data) {
    final notificationId = data['notification_id']?.toString() ?? '';
    if (notificationId.isEmpty) {
      return null;
    }

    final action = switch (data['sync_action']?.toString()) {
      'create' => FcmSyncAction.create,
      'read' => FcmSyncAction.read,
      'remove' => FcmSyncAction.remove,
      _ => FcmSyncAction.unknown,
    };

    if (action == FcmSyncAction.unknown) {
      return null;
    }

    return FcmSyncMessage(
      action: action,
      notificationId: notificationId,
      title: data['notification_title']?.toString() ?? '',
      body: data['notification_message']?.toString() ?? '',
      url: data['url']?.toString() ?? '',
    );
  }

  final FcmSyncAction action;
  final String notificationId;
  final String title;
  final String body;
  final String url;
}
