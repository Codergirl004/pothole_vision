import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/pothole_provider.dart';
import '../../models/detection_model.dart';
import '../../core/theme.dart';

class AdminMapScreen extends StatefulWidget {
  const AdminMapScreen({super.key});

  @override
  State<AdminMapScreen> createState() => _AdminMapScreenState();
}

class _AdminMapScreenState extends State<AdminMapScreen> {
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  bool _loading = true;

  // Default center (Bangalore)
  static const LatLng _defaultCenter = LatLng(12.9716, 77.5946);

  @override
  void initState() {
    super.initState();
    _loadMarkers();
  }

  Future<void> _loadMarkers() async {
    final provider = context.read<PotholeProvider>();
    await provider.loadAllPotholes();
    if (!mounted) return;

    final potholes = provider.adminPotholes;
    final markers = <Marker>{};

    for (final pothole in potholes) {
      // Get latest detection for info window details
      DetectionModel? latestDetection;
      try {
        latestDetection = await provider.getLatestDetection(pothole.locationId);
      } catch (_) {}

      final priorityLabel =
          latestDetection?.priorityLabel.toLowerCase() ?? 'low';
      final markerColor = _getMarkerHue(priorityLabel);

      markers.add(
        Marker(
          markerId: MarkerId(pothole.locationId),
          position: LatLng(pothole.lat, pothole.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(markerColor),
          infoWindow: InfoWindow(
            title:
                '${pothole.complaintCount} complaint(s) • ${latestDetection?.priorityLabel ?? 'Unknown'}',
            snippet: latestDetection != null
                ? 'Cost: ${latestDetection.currency} ${latestDetection.totalCost.toStringAsFixed(2)}'
                : 'No analysis yet',
          ),
        ),
      );
    }

    setState(() {
      _markers.addAll(markers);
      _loading = false;
    });

    // Move camera to fit markers
    if (potholes.isNotEmpty && _mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(potholes.first.lat, potholes.first.lng),
          12,
        ),
      );
    }
  }

  double _getMarkerHue(String priorityLabel) {
    switch (priorityLabel) {
      case 'severe':
      case 'high':
        return BitmapDescriptor.hueRed;
      case 'medium':
      case 'moderate':
        return BitmapDescriptor.hueOrange;
      case 'low':
        return BitmapDescriptor.hueYellow;
      default:
        return BitmapDescriptor.hueBlue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pothole Map'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _markers.clear();
                _loading = true;
              });
              _loadMarkers();
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: const CameraPosition(
                target: _defaultCenter,
                zoom: 12,
              ),
              markers: _markers,
              onMapCreated: (controller) {
                _mapController = controller;
              },
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: true,
              mapToolbarEnabled: false,
            ),
          ),
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(strokeWidth: 3),
                        SizedBox(width: 16),
                        Text('Loading potholes...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // ── Legend ──────────────────────────────
          Positioned(
            bottom: 16,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: theme.cardTheme.color,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LegendItem(AppTheme.severityHigh, 'Severe'),
                  const SizedBox(width: 12),
                  _LegendItem(AppTheme.severityMedium, 'Medium'),
                  const SizedBox(width: 12),
                  _LegendItem(AppTheme.severityLow, 'Low'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem(this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}
