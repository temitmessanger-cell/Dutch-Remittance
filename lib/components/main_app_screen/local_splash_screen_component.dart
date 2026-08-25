import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

class LocalSplashScreenComponent extends StatelessWidget {
  const LocalSplashScreenComponent({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Dutch Remit",
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
