import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '../../providers/pothole_provider.dart';
import '../../models/pothole_model.dart';
import '../../widgets/pothole_card.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/geocoding_service.dart';

class PotholeDetailsScreen extends StatefulWidget {
  final PotholeModel pothole;

  const PotholeDetailsScreen({super.key, required this.pothole});

  @override
  State<PotholeDetailsScreen> createState() => _PotholeDetailsScreenState();
}

class _PotholeDetailsScreenState extends State<PotholeDetailsScreen> {
  late String _currentStatus;
  String? _address;

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.pothole.status;
    _loadAddress();
    // Load reports
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PotholeProvider>().loadReports(widget.pothole.locationId);
    });
  }

  Future<void> _loadAddress() async {
    final addr = await GeocodingService.getAddressFromCoordinates(
        widget.pothole.lat, widget.pothole.lng);
    if (mounted) {
      setState(() {
        _address = addr;
      });
    }
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

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text(
            'Are you sure you want to delete this pothole report? This will permanently remove all data and images.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final provider = context.read<PotholeProvider>();
      
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );

      await provider.deletePothole(widget.pothole.locationId);

      if (mounted) {
        Navigator.pop(context); // Pop loading
        Navigator.pop(context); // Go back to dashboard
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report deleted successfully')),
        );
      }
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
        title: Text(_address ?? 'Location ${widget.pothole.locationId}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _confirmDelete(context),
            tooltip: 'Delete report',
          ),
        ],
      ),
      body: provider.loadingReports
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
                                  _address ?? 'Location: ${widget.pothole.locationId}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              _InfoChip(
                                  Icons.report, '${widget.pothole.complaintCount} complaints'),
                              _InfoChip(Icons.gps_fixed,
                                  '${widget.pothole.lat.toStringAsFixed(4)}, ${widget.pothole.lng.toStringAsFixed(4)}'),
                               if (_address != null)
                                 _InfoChip(Icons.map, _address!),
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
                                   // ── Reports Header ───────────────────────────────
                  Text(
                    'PDF Reports',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Historical analysis reports for this location',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
 
                  // ── Reports List ─────────────────
                  if (provider.reports.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.description_outlined,
                              size: 40, color: Colors.grey.shade400),
                          const SizedBox(height: 8),
                          Text('No PDF reports available',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  else
                    ...provider.reports.map((report) {
                      final formattedDate = report.timestamp != null
                          ? DateFormat('MMM dd, yyyy • hh:mm a')
                              .format(report.timestamp!)
                          : 'Unknown Date';
 
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.picture_as_pdf, color: Colors.red),
                          ),
                          title: Text('Report - $formattedDate'),
                          subtitle: Text('Severity: ${report.severity} • ${report.detectionCount} detections'),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                          onTap: () => _openPdfViewer(context, report.pdfUrl),
                        ),
                      );
                    }).toList(),
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
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
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
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}
