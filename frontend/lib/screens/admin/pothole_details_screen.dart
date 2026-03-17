import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../providers/pothole_provider.dart';
import '../../models/pothole_model.dart';
import '../../widgets/pothole_card.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';

class PotholeDetailsScreen extends StatefulWidget {
  final PotholeModel pothole;

  const PotholeDetailsScreen({super.key, required this.pothole});

  @override
  State<PotholeDetailsScreen> createState() => _PotholeDetailsScreenState();
}

class _PotholeDetailsScreenState extends State<PotholeDetailsScreen> {
  late String _currentStatus;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.pothole.status;
    // Load detections
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PotholeProvider>().loadDetections(widget.pothole.locationId);
    });
  }

  Future<void> _updateStatus(String newStatus) async {
    final provider = context.read<PotholeProvider>();
    setState(() => _currentStatus = newStatus);
    await provider.updatePotholeStatus(widget.pothole.locationId, newStatus);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to $newStatus'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<PotholeProvider>();
    final statusColor = _currentStatus == AppConstants.statusFixed
        ? AppTheme.statusFixed
        : _currentStatus == AppConstants.statusInProgress
            ? AppTheme.severityMedium
            : AppTheme.severityHigh;

    return Scaffold(
      appBar: AppBar(
        title: Text('Location ${widget.pothole.locationId}'),
      ),
      body: provider.loadingDetections
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Location Info Card ──────────────
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.location_on,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Location: ${widget.pothole.locationId}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _InfoChip(
                                  Icons.report, '${widget.pothole.complaintCount} complaints'),
                              const SizedBox(width: 10),
                              _InfoChip(Icons.gps_fixed,
                                  '${widget.pothole.lat.toStringAsFixed(4)}, ${widget.pothole.lng.toStringAsFixed(4)}'),
                            ],
                          ),
                          const SizedBox(height: 14),

                          // Status update dropdown
                          Row(
                            children: [
                              Text('Status:',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color:
                                            statusColor.withValues(alpha: 0.3)),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _currentStatus,
                                      isExpanded: true,
                                      items: AppConstants.potholeStatuses
                                          .map((s) => DropdownMenuItem(
                                                value: s,
                                                child: Text(s),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        if (val != null &&
                                            val != _currentStatus) {
                                          _updateStatus(val);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Detections Header ───────────────
                  Text(
                    'Detections (${provider.detections.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sorted by priority score (highest first)',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 12),

                  // ── Detections List ─────────────────
                  if (provider.detections.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.search_off,
                              size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text('No detections found',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  else
                    ...provider.detections.map((detection) {
                      final formattedDate = detection.timestamp != null
                          ? DateFormat('MMM dd, yyyy • hh:mm a')
                              .format(detection.timestamp!)
                          : null;

                      return PotholeCard(
                        imageUrl: detection.imageUrl,
                        areaCm2: detection.areaCm2,
                        depthCm: detection.depthCm,
                        volumeCm3: detection.volumeCm3,
                        totalCost: detection.totalCost,
                        priorityLabel: detection.priorityLabel,
                        priorityScore: detection.priorityScore,
                        timestamp: formattedDate,
                        onViewPdf: detection.pdfUrl != null
                            ? () => _openPdfViewer(context, detection.pdfUrl!)
                            : null,
                      );
                    }),
                ],
              ),
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoChip(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Text(text,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ],
      ),
    );
  }
}
