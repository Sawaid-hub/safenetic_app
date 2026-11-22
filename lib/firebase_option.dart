import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform, kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }


  // --- ANDROID CONFIGURATION (Crucial for your emulator/device) ---
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBJ77DaKeSipq25lzFQyaF9-nX99xm5iZo',
    appId: '1:1056760146509:android:9f500bd5096b5c655c0a04',
    messagingSenderId: '1056760146509',
    projectId: 'studio-3618135792-31638', // Replace with your real Project ID
    storageBucket: 'safenetic-app.appspot.com',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBJ77DaKeSipq25lzFQyaF9-nX99xm5iZo',
    appId: '1:1056760146509:web:9f500bd5096b5c655c0a04',
    messagingSenderId: '1056760146509',
    projectId: 'studio-3618135792-31638',
    authDomain: 'studio-3618135792-31638.firebaseapp.com',
    storageBucket: 'safenetic-app.appspot.com',
  );
}
