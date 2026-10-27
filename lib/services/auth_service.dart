import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // GoogleSignIn is a singleton in version 7.
  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // Initialize only once, even if AuthService is created again.
  static Future<void>? _googleInitialization;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> _initializeGoogle() {
    return _googleInitialization ??= _googleSignIn.initialize();
  }

  Future<UserCredential?> signInWithGoogle() async {
    // Firebase handles the browser popup on web.
    if (kIsWeb) {
      return _auth.signInWithPopup(GoogleAuthProvider());
    }

    // Our current native testing target is Android.
    await _initializeGoogle();

    try {
      final googleUser = await _googleSignIn.authenticate();

      final googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw StateError('Google did not return an ID token.');
      }

      final credential = GoogleAuthProvider.credential(idToken: idToken);

      return await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return null;
      }

      rethrow;
    }
  }

  Future<void> signOut() async {
    // End the Firebase session first.
    await _auth.signOut();

    if (!kIsWeb) {
      await _initializeGoogle();
      await _googleSignIn.signOut();
    }
  }
}
