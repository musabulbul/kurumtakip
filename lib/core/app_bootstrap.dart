import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:kurum_takip/firebase_options.dart';

class AppBootstrap {
  static Future<void> initialize({bool initHive = true}) async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}

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
