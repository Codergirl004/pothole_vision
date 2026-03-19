import 'package:cloud_firestore/cloud_firestore.dart';

class PotholeModel {
  final String locationId;
  final double lat;
  final double lng;
  final int complaintCount;
  final String status;
  final String? address;
  final double? priorityScore;
  final DateTime? lastUpdated;

  PotholeModel({
    required this.locationId,
    required this.lat,
    required this.lng,
    required this.complaintCount,
    this.status = 'Pending',
    this.lastUpdated,
    this.address,
    this.priorityScore,
  });

  factory PotholeModel.fromMap(Map<String, dynamic> map, String docId) {
    final coords = map['coords'] as Map<String, dynamic>? ?? {};
    return PotholeModel(
      locationId: docId,
      lat: (coords['lat'] ?? 0).toDouble(),
      lng: (coords['lng'] ?? 0).toDouble(),
      complaintCount: map['complaint_count'] ?? 0,
      status: map['status'] ?? 'Pending',
      lastUpdated: map['last_updated'] != null
          ? (map['last_updated'] as Timestamp).toDate()
          : null,
      address: map['address'] as String?,
      priorityScore: (map['priority_score'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'coords': {'lat': lat, 'lng': lng},
      'complaint_count': complaintCount,
      'status': status,
      'last_updated': FieldValue.serverTimestamp(),
      'address': address,
      'priority_score': priorityScore,
    };
  }
}
