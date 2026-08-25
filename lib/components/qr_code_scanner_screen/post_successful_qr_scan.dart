/*
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

class PostSuccessfulQRScanScreen extends StatelessWidget {
  final Barcode result;
  const PostSuccessfulQRScanScreen({Key? key, required this.result})
      : super(key: key);



  @override
  Widget build(BuildContext context) {
    dynamic tests = 'untouched';
    try {
      
      tests = json.decode(result.code!);
    } catch (e) {
      tests = e.toString();
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: Padding(
          padding: EdgeInsets.symmetric(horizontal: 48),
          child: Text("QR Scan Result",
              style: TextStyle(color: AppColors.ink)),
        ),
      ),
      body: Column(
        children: [
          Expanded(
              child: Container(
            child: Text('Data: ${tests}'),
          ))
        ],
      ),
    );
  }
}
*/