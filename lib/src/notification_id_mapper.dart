class NotificationIdMapper {
  static int fromNotificationId(String notificationId) {
    var hash = 0;

    for (final codeUnit in notificationId.codeUnits) {
      hash = ((hash * 31) + codeUnit) & 0x7fffffff;
    }

    return hash;
  }
}
