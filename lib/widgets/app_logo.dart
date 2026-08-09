import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// "Local" in blue + "Drop" in black — the LocalDrop wordmark.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.fontSize = AppText.logo});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Local'),
          TextSpan(
            text: 'Drop',
            style: TextStyle(color: AppColors.text),
          ),
        ],
        style: TextStyle(
          color: AppColors.primary,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      maxLines: 1,
    );
  }
}