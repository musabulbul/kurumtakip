import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:kurum_takip/firebase_options.dart';

class AppBootstrap {
  static Future<void> initialize({bool initHive = true}) async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

    if (initHive) {
      await Hive.initFlutter();
    }
  }
}
