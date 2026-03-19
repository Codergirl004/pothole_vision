import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/pothole_provider.dart';
import '../services/geocoding_service.dart';

class ReportCard extends StatefulWidget {
  final String? imageUrl;
  final String severity;
  final double? depthCm;
  final double? areaCm2;
  final double? volumeCm3;
  final double? estimatedCost;
  final String? pdfUrl;
  final String? analysisStatus;
  final String? timestamp;
  final int? potholesDetected;
  final VoidCallback? onViewPdf;
  final String? docId;
  final double? lat;
  final double? lng;
  final String? address;
 
  const ReportCard({
    super.key,
    this.imageUrl,
    this.severity = 'Unknown',
    this.depthCm,
    this.areaCm2,
    this.volumeCm3,
    this.estimatedCost,
    this.pdfUrl,
    this.analysisStatus,
    this.timestamp,
    this.potholesDetected,
    this.onViewPdf,
    this.docId,
    this.lat,
    this.lng,
    this.address,
  });

  @override
  State<ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<ReportCard> {
  String? _address;

  @override
  void initState() {
    super.initState();
    _loadAddress();
  }

  Future<void> _loadAddress() async {
    if (widget.lat != null && widget.lng != null) {
      final addr = await GeocodingService.getAddressFromCoordinates(
          widget.lat!, widget.lng!);
      if (mounted) {
        setState(() {
          _address = addr;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAnalyzed = widget.analysisStatus == 'analyzed';
    final isError = widget.analysisStatus == 'error';
    final isProcessing =
        widget.analysisStatus == 'uploading' || widget.analysisStatus == 'processing';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status Banner ────────────────────────
          if (!isAnalyzed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: isError
                  ? Colors.red.shade50
                  : isProcessing
                      ? Colors.orange.shade50
                      : Colors.blue.shade50,
              child: Row(
                children: [
                  Icon(
                    isError
                        ? Icons.error_outline
                        : isProcessing
                            ? Icons.hourglass_top
                            : Icons.info_outline,
                    size: 18,
                    color: isError
                        ? Colors.red
                        : isProcessing
                            ? Colors.orange
                            : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isError
                        ? 'Analysis failed'
                        : isProcessing
                            ? 'Processing...'
                            : widget.analysisStatus ?? 'Pending',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isError
                          ? Colors.red
                          : isProcessing
                              ? Colors.orange
                              : Colors.blue,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
                    onPressed: () => _confirmDelete(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

          // ── Image ────────────────────────────────
          if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
            SizedBox(
              height: 160,
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: widget.imageUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: Colors.grey.shade200,
                  child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: Colors.grey.shade200,
                  child:
                      const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                ),
              ),
            ),

          // ── Content ──────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Severity badge + cost
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.priorityColor(widget.severity),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.severity.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (widget.estimatedCost != null)
                      Text(
                        'Rs. ${widget.estimatedCost!.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),

                if (isAnalyzed && widget.depthCm != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _InfoItem('Depth', '${widget.depthCm!.toStringAsFixed(1)} cm'),
                      const SizedBox(width: 16),
                      _InfoItem('Area', '${widget.areaCm2?.toStringAsFixed(1)} cm²'),
                      const SizedBox(width: 16),
                      _InfoItem(
                          'Volume', '${widget.volumeCm3?.toStringAsFixed(1)} cm³'),
                    ],
                  ),
                ],

                if (widget.potholesDetected != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${widget.potholesDetected} pothole(s) detected',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],

                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                          _address ??
                              widget.address ??
                              'Coords: ${widget.lat?.toStringAsFixed(4)}, ${widget.lng?.toStringAsFixed(4)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey.shade500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),

                if (widget.timestamp != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(widget.timestamp!,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: Colors.grey.shade500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],

                // PDF button
                if (widget.pdfUrl != null && widget.pdfUrl!.isNotEmpty && widget.onViewPdf != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: widget.onViewPdf,
                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                        label: const Text('View PDF Report'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    if (widget.docId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Report'),
        content: const Text(
            'Are you sure you want to delete this report? This will remove it from your history and delete the image.'),
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

    if (confirmed == true) {
      if (!context.mounted) return;
      final provider = context.read<PotholeProvider>();
      await provider.deleteUserReport(widget.docId!, imageUrl: widget.imageUrl, pdfUrl: widget.pdfUrl);
    }
  }
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;

  const _InfoItem(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
