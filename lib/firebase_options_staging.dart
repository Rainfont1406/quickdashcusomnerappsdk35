// STAGING Firebase options.
//
// Verified REAL (not placeholder) on 2026-07-10 via `firebase apps:list
// --project=quickdash-staging` + `firebase apps:sdkconfig ios ... --project=
// quickdash-staging` — both android/ios appId and apiKey below match the
// live registered apps exactly. The header comment here previously claimed
// these were unconfigured placeholders; that was stale, not accurate — this
// file does not need to be regenerated. If it ever needs regenerating anyway:
//
//   flutterfire configure --project=quickdash-staging --out=lib/firebase_options_staging.dart
// ignore_for_file: lines_longer_than_80_chars, avoid_classes_with_only_static_members
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDgF-6rQUl4o-6F1jcIlFFDxa57vzSrZYM',
    appId: '1:812164926263:android:4868598ed9f699b19f28b2',
    messagingSenderId: '812164926263',
    projectId: 'quickdash-staging',
    storageBucket: 'quickdash-staging.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBjLceW_bGCBgS7pYqERZFvldghqByj0kM',
    appId: '1:812164926263:ios:0af5c14857cae5729f28b2',
    messagingSenderId: '812164926263',
    projectId: 'quickdash-staging',
    storageBucket: 'quickdash-staging.firebasestorage.app',
    iosBundleId: 'com.quickdash.customer.staging',
  );
}
