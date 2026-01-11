import 'package:flutter/material.dart';

class HomeIconButton extends StatelessWidget {
  const HomeIconButton({
    super.key,
    this.color,
  });

  final Color? color;

  void _handleTap(BuildContext context) {
    final navigator = Navigator.of(context);
    var reachedHome = false;

    navigator.popUntil((route) {
      final isHome = route.settings.name == '/homepage';
      if (isHome) {
        reachedHome = true;
      }
      return isHome || route.isFirst;
    });

    if (!reachedHome) {
      navigator.pushNamedAndRemoveUntil('/homepage', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Anasayfa',
      icon: Icon(Icons.home, color: color),
      onPressed: () => _handleTap(context),
    );
  }
}
