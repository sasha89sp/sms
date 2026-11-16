class OperationRecord {
  const OperationRecord({
    required this.startedAt,
    required this.finishedAt,
    required this.phoneResponse,
    required this.balanceBefore,
    required this.smsStatus,
    required this.balanceAfter,
    required this.success,
    required this.details,
  });

  final DateTime startedAt;
  final DateTime finishedAt;
  final String phoneResponse;
  final String balanceBefore;
  final String smsStatus;
  final String balanceAfter;
  final bool success;
  final String details;

  Map<String, Object?> toMap() => {
        'started_at': startedAt.toIso8601String(),
        'finished_at': finishedAt.toIso8601String(),
        'phone_response': phoneResponse,
        'balance_before': balanceBefore,
        'sms_status': smsStatus,
        'balance_after': balanceAfter,
        'success': success ? 1 : 0,
        'details': details,
      };
}
