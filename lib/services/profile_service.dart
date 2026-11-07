import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/flow_profile.dart';

class ProfileService {
  final String userId;
  ProfileService(this.userId);
  DocumentReference<Map<String, dynamic>> get _ref => FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('profile')
      .doc('main');
  Stream<FlowProfile> watch() =>
      _ref.snapshots().map((s) => FlowProfile.fromMap(s.data() ?? {}));
  Future<void> save(FlowProfile p) async {
    if (FirebaseAuth.instance.currentUser?.uid != userId)
      throw StateError('Please sign in again.');
    if (p.fullName.trim().isEmpty ||
        p.fullName.length > 80 ||
        p.displayName.trim().isEmpty ||
        p.displayName.length > 40 ||
        p.bio.length > 180 ||
        p.country.trim().isEmpty ||
        p.country.length > 60 ||
        (p.photo?.length ?? 0) > 300000 ||
        !['light', 'dark', 'system'].contains(p.appearance) ||
        p.cover < 0 ||
        p.cover > 2)
      throw ArgumentError('Check your profile details.');
    await _ref.set(p.toMap(), SetOptions(merge: true));
  }
}
