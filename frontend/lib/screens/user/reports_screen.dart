import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pothole_provider.dart';
import '../../widgets/report_card.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final potholeProvider = context.read<PotholeProvider>();
    final userId = auth.userModel?.uid ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Reports'),
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: potholeProvider.getUserReports(userId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('Error loading reports',
                      style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      snapshot.error.toString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          // Sort client-side and ensure document actually exists before showing
          final validDocs = docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>?;
            if (data == null) return false;
            // Additional check if there is a soft delete mechanism
            if (data['isDeleted'] == true) return false;
            return true;
          }).toList();

          final sortedDocs = validDocs
            ..sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = aData['createdAt'] as Timestamp?;
              final bTime = bData['createdAt'] as Timestamp?;
              if (aTime == null && bTime == null) return 0;
              if (aTime == null) return 1;
              if (bTime == null) return -1;
              return bTime.compareTo(aTime);
            });

          if (sortedDocs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'No reports yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Upload a pothole image to get started',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: sortedDocs.length,
            itemBuilder: (context, index) {
              final data = sortedDocs[index].data() as Map<String, dynamic>;

              final timestamp = data['createdAt'] as Timestamp?;
              final formattedDate = timestamp != null
                  ? DateFormat('MMM dd, yyyy • hh:mm a')
                      .format(timestamp.toDate())
                  : null;

              return ReportCard(
                imageUrl: data['imageUrl'] as String?,
                severity: data['severity'] as String? ?? 'Pending',
                depthCm: (data['depthCm'] as num?)?.toDouble(),
                areaCm2: (data['areaCm2'] as num?)?.toDouble(),
                volumeCm3: (data['volumeCm3'] as num?)?.toDouble(),
                estimatedCost: (data['estimatedCost'] as num?)?.toDouble(),
                pdfUrl: data['pdfUrl'] as String?,
                analysisStatus:
                    data['analysisStatus'] as String? ?? 'uploading',
                timestamp: formattedDate,
                potholesDetected: data['potholesDetected'] as int?,
                onViewPdf: data['pdfUrl'] != null
                    ? () => _openPdfViewer(context, data['pdfUrl'] as String)
                    : null,
              );
            },
          );
        },
      ),
    );
  }

  void _openPdfViewer(BuildContext context, String pdfUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('PDF Report')),
          body: SfPdfViewer.network(pdfUrl),
        ),
      ),
    );
  }
}
