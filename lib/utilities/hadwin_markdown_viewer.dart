import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown_widget/markdown_widget.dart';

import 'package:dutch_remit/utilities/url_external_launcher.dart';
import 'package:dutch_remit/utilities/app_theme.dart';

/// Renders one of Dutch Remit's own legal documents (see
/// legal_documents.dart) as styled markdown. Takes the document content
/// directly as a string — no network fetch, no external URL, no
/// dependency on any server (Dutch Remit's own or anyone else's) being
/// reachable. A legal document should never be allowed to fail to load.
class DutchRemitMarkdownViewer extends StatelessWidget {
  final String screenName;
  final String content;
  const DutchRemitMarkdownViewer(
      {Key? key, required this.screenName, required this.content})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            screenName,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.ink,
          elevation: 0,
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                width: MediaQuery.of(context).size.width - 20,
                padding: EdgeInsets.only(
                    left: 16.18, right: 16.18, bottom: 16.18, top: 6.18),
                child: MarkdownWidget(
                  data: content,
                  styleConfig: StyleConfig(
                      blockQuoteConfig: BlockQuoteConfig(
                        backgroundColor: Color(0xffcaf0f8),
                        blockColor: Color(0xff0077b6),
                        blockStyle: GoogleFonts.sora(color: AppColors.inkMuted),
                      ),
                      tableConfig: TableConfig(
                          headerTextConfig: TextConfig(textAlign: TextAlign.left),
                          headChildWrapper: (columnHeader) => Padding(
                                padding: EdgeInsets.all(7.2),
                                child: columnHeader,
                              ),
                          headerStyle: GoogleFonts.ubuntu(fontWeight: FontWeight.w700),
                          bodyChildWrapper: (cellBody) => Padding(
                                padding: EdgeInsets.all(7.2),
                                child: cellBody,
                              ),
                          bodyTextConfig: TextConfig(textAlign: TextAlign.center)),
                      titleConfig:
                          TitleConfig(commonStyle: GoogleFonts.ubuntu(), showDivider: false),
                      ulConfig: UlConfig(
                        ulWrapper: (ul) => Padding(
                          padding: EdgeInsets.all(5),
                          child: ul,
                        ),
                        textStyle: GoogleFonts.workSans(),
                        dotWidget: (deep, index) => Text(
                          "${index + 1}.\t",
                          style: GoogleFonts.ubuntu(),
                        ),
                      ),
                      olConfig: OlConfig(
                        olWrapper: (ul) => Padding(
                          padding: EdgeInsets.all(5),
                          child: ul,
                        ),
                        textStyle: GoogleFonts.workSans(),
                        indexWidget: (deep, index) => Text(
                          "${index + 1}.\t",
                          style: GoogleFonts.ubuntu(),
                        ),
                      ),
                      pConfig: PConfig(
                          textStyle: GoogleFonts.workSans(),
                          onLinkTap: (url) {
                            launchExternalURL(url!)
                                .then((value) => debugPrint("requested to access $url"));
                          },
                          emStyle: TextStyle(
                              fontWeight: FontWeight.w600,
                              backgroundColor: Color(0xffccff33),
                              fontStyle: FontStyle.italic)),
                      codeConfig: CodeConfig(
                          codeStyle: GoogleFonts.spaceMono(
                              backgroundColor: Color(0xff4a4e69),
                              fontWeight: FontWeight.w600,
                              color: Colors.white))),
                ),
              ),
            )
          ],
        ));
  }
}
