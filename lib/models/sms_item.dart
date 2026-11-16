class SmsItem {
  const SmsItem({
    required this.index,
    required this.status,
    required this.sender,
    required this.timestamp,
    required this.body,
  });

  final int index;
  final String status;
  final String sender;
  final String timestamp;
  final String body;
}
