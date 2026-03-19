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
class _PotholesListTab extends StatelessWidget {
  const _PotholesListTab();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.read<PotholeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Force re-render by triggering a rebuild
              (context as Element).markNeedsBuild();
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

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final pothole = PotholeModel.fromMap(data, docs[index].id);
              final status = pothole.status;
              final statusColor = status == AppConstants.statusFixed
                  ? AppTheme.statusFixed
                  : status == AppConstants.statusInProgress
                      ? AppTheme.severityMedium
                      : AppTheme.severityHigh;

              final formattedDate = pothole.lastUpdated != null
                  ? DateFormat('MMM dd, yyyy • hh:mm a')
                      .format(pothole.lastUpdated!)
                  : 'Unknown';

              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PotholeDetailsScreen(pothole: pothole),
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
                                'Location: ${pothole.locationId}',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.report,
                                      size: 14, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      '${pothole.complaintCount} complaint(s)',
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
                                  Icon(Icons.access_time,
                                      size: 14, color: Colors.grey.shade500),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
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
            },
          );
        },
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
