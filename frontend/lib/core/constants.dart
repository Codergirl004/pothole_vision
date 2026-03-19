class AppConstants {
  // ── API ──────────────────────────────────────────────
  // Change this to your Flask backend URL.
  // For Android emulator use 10.0.2.2, for physical device use your PC's LAN IP.
  static const String apiBaseUrl = 'http://192.168.50.110:5000/api/';

  // ── Firestore Collections ───────────────────────────
  static const String usersCollection = 'users';
  static const String potholesCollection = 'potholes';
  static const String aggregatedPotholesCollection = 'aggregated_potholes';
  static const String detectionsSubcollection = 'detections';

  // ── Firebase Storage paths ──────────────────────────
  static const String detectionsStoragePath = 'detections/';
  static const String reportsStoragePath = 'reports/';

  // ── Roles ───────────────────────────────────────────
  static const String roleUser = 'user';
  static const String roleAdmin = 'admin';

  // ── Pothole Statuses ────────────────────────────────
  static const String statusPending = 'Pending';
  static const String statusInProgress = 'In Progress';
  static const String statusFixed = 'Fixed';

  static const List<String> potholeStatuses = [
    statusPending,
    statusInProgress,
    statusFixed,
  ];

  // ── App Strings ─────────────────────────────────────
  static const String appName = 'PotholeVision';
  static const String appTagline = 'AI-Powered Road Safety';
}
