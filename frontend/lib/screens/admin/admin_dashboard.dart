import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pothole_provider.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/pothole_model.dart';
import 'pothole_details_screen.dart';
import 'admin_map_screen.dart';
import '../../services/geocoding_service.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          _PotholesListTab(),
          AdminMapScreen(),
          _AdminProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) =>
            setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Potholes',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outlined),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// POTHOLES LIST TAB
// ═══════════════════════════════════════════════════════
enum _SortOption { date, complaints, severity }

class _PotholesListTab extends StatefulWidget {
  const _PotholesListTab();

  @override
  State<_PotholesListTab> createState() => _PotholesListTabState();
}

class _PotholesListTabState extends State<_PotholesListTab> {
  _SortOption _currentSort = _SortOption.date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.read<PotholeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<_SortOption>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            onSelected: (option) => setState(() => _currentSort = option),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _SortOption.date,
                child: Text('Sort by Date'),
              ),
              const PopupMenuItem(
                value: _SortOption.complaints,
                child: Text('Sort by Complaints'),
              ),
              const PopupMenuItem(
                value: _SortOption.severity,
                child: Text('Sort by Severity'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {});
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: provider.getAggregatedPotholesStream(),
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
                  Text('Error loading potholes',
                      style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    'No pothole reports yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            );
          }

          // Parse and sort potholes
          final potholes = docs.map((doc) {
            return PotholeModel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
          }).toList();

          switch (_currentSort) {
            case _SortOption.date:
              potholes.sort((a, b) =>
                  (b.lastUpdated ?? DateTime(0)).compareTo(a.lastUpdated ?? DateTime(0)));
              break;
            case _SortOption.complaints:
              potholes.sort((a, b) => b.complaintCount.compareTo(a.complaintCount));
              break;
            case _SortOption.severity:
              potholes.sort((a, b) =>
                  (b.priorityScore ?? 0).compareTo(a.priorityScore ?? 0));
              break;
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: potholes.length,
            itemBuilder: (context, index) {
              return _PotholeListItem(pothole: potholes[index]);
            },
          );
        },
      ),
    );
  }
}

class _PotholeListItem extends StatefulWidget {
  final PotholeModel pothole;

  const _PotholeListItem({required this.pothole});

  @override
  State<_PotholeListItem> createState() => _PotholeListItemState();
}

class _PotholeListItemState extends State<_PotholeListItem> {
  String? _resolvedAddress;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  Future<void> _resolveAddress() async {
    if (widget.pothole.address != null) return;
    
    // Attempt geocoding from locationId (lat_lng)
    try {
      final parts = widget.pothole.locationId.split('_');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0]);
        final lng = double.tryParse(parts[1]);
        if (lat != null && lng != null) {
          final addr = await GeocodingService.getAddressFromCoordinates(lat, lng);
          if (mounted) {
            setState(() => _resolvedAddress = addr);
          }
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pothole = widget.pothole;
    final status = pothole.status;
    final statusColor = status == AppConstants.statusFixed
        ? AppTheme.statusFixed
        : status == AppConstants.statusInProgress
            ? AppTheme.severityMedium
            : AppTheme.severityHigh;

    final formattedDate = pothole.lastUpdated != null
        ? DateFormat('MMM dd, yyyy • hh:mm a').format(pothole.lastUpdated!)
        : 'Unknown';

    final displayAddress = pothole.address ?? _resolvedAddress ?? 'Location: ${pothole.locationId}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PotholeDetailsScreen(pothole: pothole),
          ),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  status == AppConstants.statusFixed
                      ? Icons.check_circle
                      : Icons.warning_rounded,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayAddress,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.report, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${pothole.complaintCount} complaint(s) • Severity: ${pothole.priorityScore?.toStringAsFixed(1) ?? 'N/A'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Status chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
// ADMIN PROFILE TAB
// ═══════════════════════════════════════════════════════
class _AdminProfileTab extends StatelessWidget {
  const _AdminProfileTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 48,
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  (auth.userModel?.name ?? 'A')[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 36,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                auth.userModel?.name ?? 'Admin',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                auth.userModel?.email ?? '',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'ADMIN',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => auth.logout(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
