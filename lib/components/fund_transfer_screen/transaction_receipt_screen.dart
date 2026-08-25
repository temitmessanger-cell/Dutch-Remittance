import 'package:dotted_line/dotted_line.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dutch_remit/providers/live_transactions_provider.dart';

import 'package:provider/provider.dart';
import 'package:dutch_remit/hadwin_components.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

class TransactionReceiptScreen extends StatelessWidget {
  final Map<String, dynamic> transactionReceipt;
  final String transactionStatus;
  TransactionReceiptScreen(
      {Key? key,
      required this.transactionReceipt,
      required this.transactionStatus})
      : super(key: key);


  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance!.addPostFrameCallback((timeStamp) =>
        Provider.of<LiveTransactionsProvider>(context, listen: false)
            .removeUnreadTransaction(transactionReceipt['transactionID']));

    double screenWidth=MediaQuery.of(context).size.width;
// double screenWidth=360;

TextStyle _receiptHeaders =
      GoogleFonts.manrope(color: AppColors.textMuted, fontSize: screenWidth<380? 14 :16);
  TextStyle _receiptValues = GoogleFonts.manrope(
      fontSize: screenWidth<380? 15 : 19, color: AppColors.inkMuted, fontWeight: FontWeight.bold);

    Widget transactionMemberImage = FutureBuilder<int>(
      future: checkUrlValidity(
          "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${transactionReceipt['transactionMemberAvatar']}"),
      builder: (context, snapshot) {
        if (transactionReceipt
                .containsKey('transactionMemberBusinessWebsite') &&
            transactionReceipt.containsKey('transactionMemberAvatar')) {
          return ClipOval(
            child: AspectRatio(
              aspectRatio: 1.0 / 1.0,
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
             
                  AppColors.ink,
                  BlendMode.color,
                ),
                child: ColorFiltered(
                  colorFilter: ColorFilter.mode(
                    Colors.grey,
                    BlendMode.saturation,
              
                  ),
                  child: Image.network(
                    "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${transactionReceipt['transactionMemberAvatar']}",
                    height: 56,
                    width: 56,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          );
        } else if (transactionReceipt.containsKey('transactionMemberEmail') &&
            transactionReceipt.containsKey('transactionMemberAvatar') &&
            snapshot.hasData) {
          if (snapshot.data == 404) {
            return ClipOval(
              child: AspectRatio(
                aspectRatio: 1.0 / 1.0,
                child: Image.network(
                  "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/Dutch Remit_users/${transactionReceipt['transactionMemberGender']?.toString().toLowerCase() ?? ''}/${transactionReceipt['transactionMemberAvatar']}",
                  height: 56,
                  width: 56,
                  fit: BoxFit.contain,
                ),
              ),
            );
          } else {
            return ClipOval(
              child: AspectRatio(
                aspectRatio: 1.0 / 1.0,
                child: Image.network(
                  "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/brands_and_businesses/${transactionReceipt['transactionMemberAvatar']}",
                  height: 56,
                  width: 56,
                  fit: BoxFit.contain,
                ),
              ),
            );
          }
        } else {
          return Text(
            transactionReceipt['transactionMemberName'][0].toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: 18,
              color: AppColors.ink,
            ),
          );
        }
      },
    );

    return Scaffold(
        backgroundColor: AppColors.primaryDark,
        body: SingleChildScrollView(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [AppColors.primaryDark, AppColors.primary],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter),
            ),
            child: Column(
              children: [
                SizedBox(
                  height: 72,
                ),
                Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    ClipPath(
                      clipper: ReceiptClipper(),
                      child: Container(
                        // height: MediaQuery.of(context).size.height -36,
                        height:618,
                        width: screenWidth - 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          color: Colors.white,
                        ),
                      ),
                    ),

                    Positioned(
                        top: -36,
                        child: CircleAvatar(
                          backgroundColor: Colors.white,
                          radius: 39,
                          child: CircleAvatar(
                            child: Image.asset(
                              'assets/images/checkmark.png',
                             
                            ),
                            radius: 36,
                          ),
                        )),

                    Positioned(
                      top:
                          155, 
                      child: DottedLine(
                        direction: Axis.horizontal,
                        lineLength: screenWidth - 120,
                        lineThickness: 2.4,
                        dashLength: 12,
                        dashColor: Colors.grey.shade500,
                 
                        dashRadius: 0.0,
                        dashGapLength: 3.0,
                        dashGapColor: Colors.transparent,
                    
                        dashGapRadius: 0.0,
                      ),
                    ),

                    //? RECEIPT HEADER ↴
                    Positioned(
                        top: 70,
                        child: Wrap(
                          direction: Axis.vertical,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 3.6,
                          children: [
                            Text(
                                transactionReceipt['transactionType'] == 'debit'
                                    ? 'Congratulations!'
                                    : "Surprise!",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.manrope(
                                    fontSize: 24,
                                    color: AppColors.inkMuted,
                                    fontWeight: FontWeight.bold)),
                            Text(
                              transactionReceipt['transactionType'] == 'debit'
                                  ? 'your transaction was successful'
                                  : 'apparently someone still cares\nabout you',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.manrope(
                                color: AppColors.textMuted,
                              ),
                            )
                          ],
                        )),

                    //? RECEIPT BODY ↴
                    Positioned(
                        top: 200,
                        child: Container(
                          width: screenWidth - 120,
                          color: Colors.transparent,
                          child: Wrap(
                            direction: Axis.vertical,
                            spacing: 24,
                            children: [
                              //? DATE AND TIME OF TRANSACTION ↴
                              Container(
                                width: screenWidth - 120,
                                color: Colors.transparent,
                                child: Wrap(
                                  direction: Axis.horizontal,
                                  alignment: WrapAlignment.spaceBetween,
                                  children: [
                                    Wrap(
                                      direction: Axis.vertical,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.start,
                                      spacing: 3.6,
                                      children: [
                                        Text('DATE', style: _receiptHeaders),
                                 
                                        SizedBox(
                                          width: MediaQuery.of(context)
                                                  .size
                                                  .width /
                                              2.4,
                                          child: Text(
                                            dateToWords(DateTime.parse(
                                                transactionReceipt[
                                                    'transactionDate'])),
                                            style: _receiptValues,
                                          ),
                                        ),
                                     
                                      ],
                                    ),
                                    Wrap(
                                      direction: Axis.vertical,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.end,
                                      spacing: 3.6,
                                      children: [
                                        Text(
                                          'TIME',
                                          style: _receiptHeaders,
                                        ),
                                        Text(
                                          formatTime3(transactionReceipt[
                                              'transactionDate']),
                                          style: _receiptValues,
                                        )
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              //? INFO AND SENDER OR RECEIPIENT ↴
                              Container(
                                width: screenWidth - 120,
                                color: Colors.transparent,
                                child: Wrap(
                                  direction: Axis.horizontal,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  alignment: WrapAlignment.spaceBetween,
                                 
                                  children: [
                                    Wrap(
                                      direction: Axis.vertical,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.start,
                                      spacing: 3.6,
                                      children: [
                                        Text(
                                            transactionReceipt[
                                                        'transactionType'] ==
                                                    'debit'
                                                ? 'TO'
                                                : 'FROM',
                                            style: _receiptHeaders),
                                       
                                        SizedBox(
                                          width: MediaQuery.of(context)
                                                  .size
                                                  .width /
                                              2.4,
                                          child: Text(
                                            _formatParticipantName(
                                                transactionReceipt[
                                                    'transactionMemberName']),
                                            style: _receiptValues,
                                          ),
                                        ),
                                     
                                        SizedBox(
                                            width: MediaQuery.of(context)
                                                    .size
                                                    .width /
                                                2.4,
                                            child: Text(
                                          
                                              transactionReceipt.containsKey(
                                                      'transactionMemberBusinessWebsite')
                                                  ? transactionReceipt[
                                                      'transactionMemberBusinessWebsite']
                                                  : transactionReceipt.containsKey(
                                                          'transactionMemberEmail')
                                                      ? transactionReceipt[
                                                          'transactionMemberEmail']
                                                      : 'contact details unavailable',
                                              style: GoogleFonts.manrope(
                                                  color: AppColors.textMuted,
                                                  fontSize: 12),
                                            ))
                                      ],
                                    ),
                                    Wrap(
                                      direction: Axis.vertical,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.end,
                                      spacing: 3.6,
                                      children: [
                                        CircleAvatar(
                                            radius: 30,
                                            backgroundColor: AppColors.surfaceAlt,
                                            child: transactionMemberImage),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              //? TRANSACTION AMOUNT ---  ↔  --- TRANSACTION STATUS ↴
                              Container(
                                width: screenWidth - 120,
                                color: Colors.transparent,
                                child: Wrap(
                                  direction: Axis.horizontal,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  alignment: WrapAlignment.spaceBetween,
                                  children: [
                                    Wrap(
                                      direction: Axis.vertical,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.start,
                                      spacing: 3.6,
                                      children: [
                                        Text('AMOUNT', style: _receiptHeaders),
                                        Text(
                                          '\$ ${transactionReceipt['transactionAmount']}',
                                          style: GoogleFonts.manrope(
                                              fontSize: 32,
                                              color: AppColors.ink,
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                    Wrap(
                                      direction: Axis.vertical,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.end,
                                      spacing: 3.6,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                              color: AppColors.successBg,
                                              borderRadius:
                                                  BorderRadius.circular(AppRadii.sm)),
                                          child: Text(
                                            'COMPLETED',
                                            style: GoogleFonts.manrope(
                                                color: AppColors.success,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 12),
                                          ),
                                        )
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
                    Positioned(
                        bottom: 14,
                        child: Container(
                          height: 100,
                      
                          width: screenWidth - 96,
                          decoration: BoxDecoration(
                             
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(AppRadii.sm)),
                          // child: Padding(
                              padding: const EdgeInsets.all(6.0),
                              child: FutureBuilder<Map<String, dynamic>>(
                                future: CardsStorage().randomCard,
                                builder: _financialInstrumentsBuilder,
                              )
                              // ),
                        ))
                  ],
                ),
                SizedBox(
                  height: 48,
                ),
                FloatingActionButton(
                  elevation: 0,
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Icon(
                    Icons.close,
                    color: Colors.white,
                  ),
                  backgroundColor: Colors.white24,
                ),
                SizedBox(
                  height: 48,
                )
              ],
            ),
          ),
        ));
  }

  String _formatCardBrandName(String brand) {
    String formattedVersion = brand
        .toLowerCase()
        .split(' ')
        .map((e) => "${e[0].toUpperCase()}${e.substring(1)}")
        .toList()
        .join(' ');
    return formattedVersion;
  }

  Widget _financialInstrumentsBuilder(
      BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
    if (snapshot.hasData) {
      final cardUsedInTransaction = snapshot.data!;
      double screenWidth=MediaQuery.of(context).size.width;

      return Wrap(
        spacing: 12,
        runSpacing: 6.4,
        crossAxisAlignment: WrapCrossAlignment.center,
    
        runAlignment: WrapAlignment.center,
        direction: Axis.horizontal,
        children: [
          Container(
            margin: EdgeInsets.only(left: 8.4),
            child: Image.network(
              "${ApiConstants.baseUrl}/dist/images/Dutch Remit_images/Dutch Remit_payment_system/square_card_brands/${cardUsedInTransaction['cardBrand'].replaceAll(' ', '-').toLowerCase()}.png",
              height: 72,
              width: 72,
            ),
          ),
          Container(
            height: 72,
            child: Wrap(
              direction: Axis.vertical,
            
              alignment: WrapAlignment.spaceEvenly,
              children: [
                Text(
                  'Credit/Debit Card',
                  style: GoogleFonts.roboto(
                      fontSize: screenWidth<400? 16:18,
                      color: AppColors.inkMuted,
                      fontWeight: FontWeight.bold),
                ),
                Text(
                  "${_formatCardBrandName(cardUsedInTransaction['cardBrand'])} ending ${_formatCardNumber(cardUsedInTransaction['cardNumber'])}",
                  style: GoogleFonts.manrope(fontSize: screenWidth<400? 11: 13, color: AppColors.textMuted),
                )
              ],
            ),
          )
        ],
      );
    } else {
      return Wrap(
        spacing: 6.4,
        runSpacing: 6.4,
        crossAxisAlignment: WrapCrossAlignment.center,
    
        runAlignment: WrapAlignment.center,
        direction: Axis.horizontal,
        children: [
          Image.asset(
            'assets/images/piggy-bank.png',
            height: 48,
            width: 48,
          ),
          Wrap(
            direction: Axis.vertical,
            spacing: 7.2,
            children: [
              Text(
                'Credit/Debit Card',
                style: GoogleFonts.manrope(
                    fontSize: 18, fontWeight: FontWeight.w500),
              ),
              Text(
                "Loading Card Number...",
                style: GoogleFonts.manrope(fontSize: 13, color: Colors.grey),
              )
            ],
          )
        ],
      );
    }
  }

  String _formatCardNumber(String cardNumber) {
    String formattedVersion = cardNumber.replaceAll(' ', '');
    int lastTwoPlaces = formattedVersion.length - 2;
    return "**${formattedVersion.substring(lastTwoPlaces)}";
  }

  String _formatParticipantName(String name) {
    String formattedVersion = name;
    if (name.length > 26) {
      formattedVersion = name.substring(0, 23) + "...";
    }
    return formattedVersion;
  }
}

class ReceiptClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    

    path
    
      ..lineTo(size.width, 0)
     
      ..lineTo(size.width, 140)
      
      ..cubicTo(size.width * .92, 140, size.width * .92, 170, size.width, 170)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, 170)
     
      ..cubicTo(size.width * .08, 170, size.width * .08, 140, 0, 140)
      ..lineTo(0, 0)
    
      ..close();

    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) {
    return false;
   
  }
}

