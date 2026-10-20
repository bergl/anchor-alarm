import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'remote_models.dart';
import 'remote_store.dart';

/// [RemoteWatchStore] on Cloud Firestore with anonymous Firebase Auth.
/// Data model and rules: firebase/firestore.rules, DESIGN.md.
class FirestoreRemoteStore implements RemoteWatchStore {
  FirestoreRemoteStore({required this.firestore, required this.auth});

  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  static const watches = 'watches';
  static const watchers = 'watchers';

  DocumentReference<Map<String, dynamic>> _watch(String id) =>
      firestore.collection(watches).doc(id);

  @override
  Future<String> signIn() async {
    final current = auth.currentUser;
    if (current != null) return current.uid;
    final cred = await auth.signInAnonymously();
    final user = cred.user;
    if (user == null) throw const RemoteException(RemoteErrorKind.other, 'No user after sign-in');
    return user.uid;
  }

  static Object? _convert(Object? v) {
    if (v is DateTime) return Timestamp.fromDate(v);
    if (v is Map) return {for (final e in v.entries) e.key as String: _convert(e.value)};
    if (v is List) return [for (final x in v) _convert(x)];
    return v;
  }

  static Map<String, Object?> _toDart(Map<String, dynamic> m) =>
      {for (final e in m.entries) e.key: _fromFirestore(e.value)};

  static Object? _fromFirestore(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is Map) return {for (final e in v.entries) e.key as String: _fromFirestore(e.value)};
    if (v is List) return [for (final x in v) _fromFirestore(x)];
    return v;
  }

  static RemoteException _wrap(Object e) {
    if (e is RemoteException) return e;
    if (e is FirebaseException) {
      return switch (e.code) {
        'permission-denied' || 'not-found' || 'unauthenticated' =>
          RemoteException(RemoteErrorKind.accessDenied, e.message ?? e.code),
        'unavailable' || 'deadline-exceeded' || 'network-request-failed' =>
          RemoteException(RemoteErrorKind.offline, e.message ?? e.code),
        _ => RemoteException(RemoteErrorKind.other, e.message ?? e.code),
      };
    }
    return RemoteException(RemoteErrorKind.other, '$e');
  }

  @override
  Future<void> putWatch(String watchId, RemoteWatchWrite data) async {
    final fields = <String, Object?>{
      for (final e in data.toFields().entries) e.key: _convert(e.value),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      await _watch(watchId).set(fields, SetOptions(merge: true));
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> stopSharing(String watchId,
      {required String newShareKey, required DateTime endedAt}) async {
    try {
      // One write: rotating the key locks every watcher out immediately;
      // setting endedAt makes the function tell watchers the watch ended.
      await _watch(watchId).update({
        'shareKey': newShareKey,
        'endedAt': Timestamp.fromDate(endedAt),
        'ringing': false,
        'state': 'inactive',
        'reasons': <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final list = await _watch(watchId).collection(watchers).get();
      final batch = firestore.batch();
      for (final d in list.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> join(String watchId, String shareKey,
      {required List<String> fcmTokens, required String platform, String? name}) async {
    await signIn();
    final uid = auth.currentUser!.uid;
    try {
      await _watch(watchId).collection(watchers).doc(uid).set({
        'key': shareKey,
        'fcmTokens': fcmTokens.take(10).toList(),
        'platform': platform,
        'addedAt': FieldValue.serverTimestamp(),
        if (name != null && name.isNotEmpty) 'name': name.length > 60 ? name.substring(0, 60) : name,
      }).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const RemoteException(RemoteErrorKind.offline, 'No connection');
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> leave(String watchId) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _watch(watchId).collection(watchers).doc(uid).delete();
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Future<void> setTokens(String watchId, List<String> fcmTokens) async {
    final uid = auth.currentUser?.uid;
    if (uid == null) return;
    try {
      await _watch(watchId)
          .collection(watchers)
          .doc(uid)
          .update({'fcmTokens': fcmTokens.take(10).toList()});
    } catch (e) {
      throw _wrap(e);
    }
  }

  @override
  Stream<RemoteWatch> watch(String watchId) async* {
    await signIn();
    yield* _watch(watchId).snapshots().handleError((Object e) => throw _wrap(e)).where((s) {
      if (!s.exists) throw const RemoteException(RemoteErrorKind.accessDenied, 'Watch not found');
      return true;
    }).map((s) => RemoteWatch.fromFields(watchId, _toDart(s.data()!)));
  }
}
