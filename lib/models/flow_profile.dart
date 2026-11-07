import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

class FlowProfile {
  static const sections = [
    'weekly',
    'categories',
    'plans',
    'recent',
    'insights',
  ];
  final String fullName, displayName, bio, country, appearance;
  final int cover;
  final Uint8List? photo;
  final List<String> order, hidden;
  const FlowProfile({
    this.fullName = '',
    this.displayName = '',
    this.bio = '',
    this.country = 'Sri Lanka',
    this.appearance = 'system',
    this.cover = 0,
    this.photo,
    this.order = sections,
    this.hidden = const [],
  });
  factory FlowProfile.fromMap(Map<String, dynamic> data) {
    final order =
        (data['order'] as List?)
            ?.whereType<String>()
            .where(sections.contains)
            .toSet()
            .toList() ??
        <String>[];
    return FlowProfile(
      fullName: data['fullName'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      bio: data['bio'] as String? ?? '',
      country: data['country'] as String? ?? 'Sri Lanka',
      appearance: data['appearance'] as String? ?? 'system',
      cover: data['cover'] as int? ?? 0,
      photo: (data['photo'] as Blob?)?.bytes,
      order: [...order, ...sections.where((s) => !order.contains(s))],
      hidden:
          (data['hidden'] as List?)
              ?.whereType<String>()
              .where(sections.contains)
              .toList() ??
          [],
    );
  }
  Map<String, dynamic> toMap() => {
    'fullName': fullName.trim(),
    'displayName': displayName.trim(),
    'bio': bio.trim(),
    'country': country.trim(),
    'appearance': appearance,
    'cover': cover,
    'photo': photo == null ? null : Blob(photo!),
    'order': order,
    'hidden': hidden,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}
