import 'package:flutter/material.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/utilities/app_theme.dart';



class NewSettingsScreen extends StatelessWidget {
  NewSettingsScreen({Key? key}) : super(key: key);

  final AppBar appBar = AppBar(
    title: Text('Settings', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
    centerTitle: true,
    backgroundColor: Colors.transparent,
    foregroundColor: AppColors.ink,
    elevation: 0,
  );


  @override
  Widget build(BuildContext context) {
    Column appSettings = Column(
      children: [
        Expanded(
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height - 180,
            child: AppSettingsComponent(),
          ),
        )
      ],
    );
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: appBar,
      body: appSettings,
    );
  }
}

