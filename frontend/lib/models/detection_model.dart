import 'package:cloud_firestore/cloud_firestore.dart';

class DetectionModel {
  final String detectionId;
  final String locationId;
  final double areaCm2;
  final double depthCm;
  final double volumeCm3;
  final double priorityScore;
  final String priorityLabel;
  final double totalCost;
  final String currency;
  final String imageUrl;
  final int complaintInstance;
  final DateTime? timestamp;
  final String? pdfUrl;

  DetectionModel({
    required this.detectionId,
    required this.locationId,
    required this.areaCm2,
    required this.depthCm,
    required this.volumeCm3,
    required this.priorityScore,
    required this.priorityLabel,
    required this.totalCost,
    this.currency = 'Rs.',
    required this.imageUrl,
    required this.complaintInstance,
    this.timestamp,
    this.pdfUrl,
  });

  factory DetectionModel.fromMap(Map<String, dynamic> map) {
    final metrics = map['metrics'] as Map<String, dynamic>? ?? {};
    final priority = map['priority'] as Map<String, dynamic>? ?? {};
    final estimation = map['estimation'] as Map<String, dynamic>? ?? {};

    return DetectionModel(
      detectionId: map['detection_id'] ?? '',
      locationId: map['location_id'] ?? '',
      areaCm2: (metrics['area_cm2'] ?? 0).toDouble(),
      depthCm: (metrics['depth_cm'] ?? 0).toDouble(),
      volumeCm3: (metrics['volume_cm3'] ?? 0).toDouble(),
      priorityScore: (priority['score'] ?? 0).toDouble(),
      priorityLabel: priority['label'] ?? 'Unknown',
      totalCost: (estimation['total_cost'] ?? 0).toDouble(),
      currency: estimation['currency'] ?? 'Rs.',
      imageUrl: map['image_url'] ?? '',
      complaintInstance: map['complaint_instance'] ?? 0,
      timestamp: map['timestamp'] != null
          ? (map['timestamp'] as Timestamp).toDate()
          : null,
      pdfUrl: map['pdf_url'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'detection_id': detectionId,
      'location_id': locationId,
      'metrics': {
        'area_cm2': areaCm2,
        'depth_cm': depthCm,
        'volume_cm3': volumeCm3,
      },
      'priority': {
        'score': priorityScore,
        'label': priorityLabel,
      },
      'estimation': {
        'total_cost': totalCost,
        'currency': currency,
      },
      'image_url': imageUrl,
      'complaint_instance': complaintInstance,
      'pdf_url': pdfUrl,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }
}
