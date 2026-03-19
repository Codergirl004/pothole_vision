import 'package:cloud_firestore/cloud_firestore.dart';

class ReportModel {
  final String reportId;
  final String pdfUrl;
  final DateTime? timestamp;
  final int detectionCount;
  final double totalCost;
  final String severity;

  ReportModel({
    required this.reportId,
    required this.pdfUrl,
    this.timestamp,
    required this.detectionCount,
    required this.totalCost,
    required this.severity,
  });

  factory ReportModel.fromMap(Map<String, dynamic> map, String id) {
    return ReportModel(
      reportId: id,
      pdfUrl: map['pdf_url'] ?? '',
      timestamp: map['timestamp'] != null
          ? (map['timestamp'] as Timestamp).toDate()
          : null,
      detectionCount: map['detection_count'] ?? 0,
      totalCost: (map['total_cost'] ?? 0).toDouble(),
      severity: map['severity'] ?? 'Unknown',
    );
  }
}
