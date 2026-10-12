class AuditEvent {
  final String id;
  final String? actorId;
  final String? actorEmail;
  final String action;
  final String resourceType;
  final String? resourceId;
  final Map<String, dynamic> details;
  final DateTime timestamp;

  const AuditEvent({
    required this.id,
    this.actorId,
    this.actorEmail,
    required this.action,
    required this.resourceType,
    this.resourceId,
    required this.details,
    required this.timestamp,
  });

  factory AuditEvent.fromMap(Map<String, dynamic> map) {
    return AuditEvent(
      id: map['id'] as String,
      actorId: map['actor_id'] as String?,
      actorEmail: map['actor_email'] as String?,
      action: map['action'] as String? ?? 'unknown',
      resourceType: map['resource_type'] as String? ?? 'system',
      resourceId: map['resource_id'] as String?,
      details: map['details'] is Map ? Map<String, dynamic>.from(map['details'] as Map) : {},
      timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
