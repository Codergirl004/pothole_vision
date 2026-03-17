import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/theme.dart';

class PotholeCard extends StatelessWidget {
  final String? imageUrl;
  final double areaCm2;
  final double depthCm;
  final double volumeCm3;
  final double totalCost;
  final String priorityLabel;
  final double? priorityScore;
  final String? timestamp;
  final VoidCallback? onTap;
  final VoidCallback? onViewPdf;
  final Widget? trailing;

  const PotholeCard({
    super.key,
    this.imageUrl,
    required this.areaCm2,
    required this.depthCm,
    required this.volumeCm3,
    required this.totalCost,
    required this.priorityLabel,
    this.priorityScore,
    this.timestamp,
    this.onTap,
    this.onViewPdf,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColor = AppTheme.priorityColor(priorityLabel);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image ──────────────────────────────
            if (imageUrl != null && imageUrl!.isNotEmpty)
              SizedBox(
                height: 180,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: Colors.grey.shade200,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image,
                            size: 48, color: Colors.grey),
                      ),
                    ),
                    // Priority badge
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: badgeColor.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          priorityLabel.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Metrics ────────────────────────────
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cost header
                  Row(
                    children: [
                      Icon(Icons.currency_rupee,
                          size: 20, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        totalCost.toStringAsFixed(2),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      if (trailing != null) trailing!,
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Metric chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _MetricChip(
                        icon: Icons.square_foot,
                        label: 'Area',
                        value: '${areaCm2.toStringAsFixed(1)} cm²',
                      ),
                      _MetricChip(
                        icon: Icons.height,
                        label: 'Depth',
                        value: '${depthCm.toStringAsFixed(1)} cm',
                      ),
                      _MetricChip(
                        icon: Icons.view_in_ar,
                        label: 'Volume',
                        value: '${volumeCm3.toStringAsFixed(1)} cm³',
                      ),
                    ],
                  ),
                  if (priorityScore != null) ...[
                    const SizedBox(height: 8),
                    _MetricChip(
                      icon: Icons.speed,
                      label: 'Score',
                      value: priorityScore!.toStringAsFixed(1),
                    ),
                  ],
                  if (timestamp != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.access_time,
                            size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          timestamp!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],

                  // PDF button
                  if (onViewPdf != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onViewPdf,
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
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            '$label: $value',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
