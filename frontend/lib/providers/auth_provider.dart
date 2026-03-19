import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../core/constants.dart';

enum AuthStatus { uninitialized, authenticated, unauthenticated, loading }

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();

  AuthStatus _status = AuthStatus.uninitialized;
  UserModel? _userModel;
  String _errorMessage = '';

  AuthStatus get status => _status;
  UserModel? get userModel => _userModel;
  String get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;
  bool get isAdmin => _userModel?.isAdmin ?? false;

  AuthProvider() {
    _authService.authStateChanges.listen(_onAuthStateChanged);
  }

  Future<void> _onAuthStateChanged(User? user) async {
    if (user == null) {
      _status = AuthStatus.unauthenticated;
      _userModel = null;
    } else {
      try {
        _userModel = await _firestoreService.getUserProfile(user.uid);
        _status = AuthStatus.authenticated;
      } catch (e) {
        _status = AuthStatus.authenticated;
        _userModel = UserModel(
          uid: user.uid,
          name: user.displayName ?? '',
          email: user.email ?? '',
          role: AppConstants.roleUser,
        );
      }
    }
    notifyListeners();
  }

  // ── Register ──────────────────────────────────────
  Future<bool> register({
    required String name,
    required String email,
    required String password,
    String role = 'user',
  }) async {
    try {
      _status = AuthStatus.loading;
      _errorMessage = '';
      notifyListeners();

      final credential = await _authService.register(email, password);
      await _authService.updateDisplayName(name);

      final user = UserModel(
        uid: credential.user!.uid,
        name: name,
        email: email,
        role: role,
      );
      await _firestoreService.createUserProfile(user);
      _userModel = user;

      // Sign out so user logs in explicitly
      await _authService.logout();
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _mapAuthError(e.code);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Server issue or connection error. Please try again later.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ── Login ─────────────────────────────────────────
  Future<bool> login({
    required String email,
    required String password,
  }) async {
    try {
      _status = AuthStatus.loading;
      _errorMessage = '';
      notifyListeners();

      final credential = await _authService.login(email, password);
      _userModel =
          await _firestoreService.getUserProfile(credential.user!.uid);

      _status = AuthStatus.authenticated;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _errorMessage = _mapAuthError(e.code);
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Server issue or connection error. Please try again later.';
      _status = AuthStatus.unauthenticated;
      notifyListeners();
      return false;
    }
  }

  // ── Logout ────────────────────────────────────────
  Future<void> logout() async {
    await _authService.logout();
    _userModel = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  // ── Error mapping ─────────────────────────────────
  String _mapAuthError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'invalid-credential':
        return 'Invalid credentials. Please check your password or sign up if you haven\'t registered.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'An error occurred during authentication. Please try again.';
    }
  }
}
