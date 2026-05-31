import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web platform is not configured for Firebase.');
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
    apiKey: 'AIzaSyCbmbBmN052kGnIDxpQbmDIB_osA0bwE4k',
    appId: '1:274879524094:android:cb3d999c3e7a3e6e5f49af',
    messagingSenderId: '274879524094',
    projectId: 'myloop-6aefc',
    storageBucket: 'myloop-6aefc.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAfV2X7Tu86wHF4ySgNs-L1zPDCzW5F1p0',
    appId: '1:274879524094:ios:de4caa27f1cbb0965f49af',
    messagingSenderId: '274879524094',
    projectId: 'myloop-6aefc',
    storageBucket: 'myloop-6aefc.firebasestorage.app',
    iosClientId: '274879524094-j0tca4klgueb62lm0orbbiubvmihi5of.apps.googleusercontent.com',
    iosBundleId: 'com.promanxi.myloop',
  );
}
