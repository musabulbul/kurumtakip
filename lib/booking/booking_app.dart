import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/booking_theme.dart';
import 'pages/booking_home_page.dart';
import 'pages/org_booking_page.dart';

class BookingApp extends StatelessWidget {
  const BookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mebs Online Randevu',
      theme: buildBookingTheme(),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');
        final segments = uri.pathSegments;

        if (segments.isEmpty) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const BookingHomePage(),
          );
        }

        final slug = segments.first;
        return MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => OrgBookingPage(slug: slug),
        );
      },
      initialRoute: Uri.base.path.isEmpty ? '/' : Uri.base.path,
    );
  }
}
