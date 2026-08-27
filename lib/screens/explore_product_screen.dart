import 'package:flutter/material.dart';
import 'package:dutch_remit/utilities/app_theme.dart';
import 'package:dutch_remit/utilities/slide_right_route.dart';
import 'package:dutch_remit/utilities/african_country_data.dart';
import 'package:dutch_remit/utilities/url_external_launcher.dart';
import 'package:dutch_remit/components/international_transfer/african_country_picker_sheet.dart';
import 'package:dutch_remit/screens/africa_corridor_screen.dart';
import 'package:dutch_remit/screens/top_up_screen.dart';
import 'package:dutch_remit/screens/wire_transfer_request_screen.dart';

class _Persona {
  final IconData icon;
  final String title;
  final String subtitle;
  final String ctaLabel;
  const _Persona(
      {required this.icon, required this.title, required this.subtitle, required this.ctaLabel});
}

class _Category {
  final String name;
  final String description;
  final IconData sectionIcon;
  final List<_Persona> personas;
  const _Category(
      {required this.name, required this.description, required this.sectionIcon, required this.personas});
}

const List<_Category> _kCategories = [
  _Category(
    name: "For individuals",
    description: "Sending or getting paid across borders, for yourself or family.",
    sectionIcon: Icons.person_rounded,
    personas: [
      _Persona(
        icon: Icons.family_restroom_rounded,
        title: "The diaspora",
        subtitle: "Support family back home, every month.",
        ctaLabel: "Send to a country",
      ),
      _Persona(
        icon: Icons.school_rounded,
        title: "Students abroad",
        subtitle: "Get money from home without the pickup queue.",
        ctaLabel: "Send to a country",
      ),
      _Persona(
        icon: Icons.laptop_mac_rounded,
        title: "Freelancers & remote workers",
        subtitle: "Get paid by clients abroad, in dollars.",
        ctaLabel: "Get paid",
      ),
    ],
  ),
  _Category(
    name: "For business",
    description: "Moving money in and out for a company, not a person.",
    sectionIcon: Icons.storefront_rounded,
    personas: [
      _Persona(
        icon: Icons.public_rounded,
        title: "Exporters & global sellers",
        subtitle: "Get paid by buyers worldwide, like a local.",
        ctaLabel: "Get paid",
      ),
      _Persona(
        icon: Icons.local_shipping_rounded,
        title: "Importers & traders",
        subtitle: "Pay overseas suppliers before competitors do.",
        ctaLabel: "Pay a supplier",
      ),
    ],
  ),
  _Category(
    name: "For developers",
    description: "Building payouts, collections or FX into your own product.",
    sectionIcon: Icons.api_rounded,
    personas: [
      _Persona(
        icon: Icons.integration_instructions_rounded,
        title: "Builders",
        subtitle: "Embed payouts, collections and FX.",
        ctaLabel: "Request API access",
      ),
    ],
  ),
];

/// A "who is this for" explorer, organized into named categories
/// (individuals / business / developers) rather than one flat list —
/// each section has its own framing and a quick-input tailored to
/// what that category actually needs before it routes into the real
/// flow, instead of every persona funnelling through an identical
/// generic tile.
class ExploreProductScreen extends StatefulWidget {
  final Map<String, dynamic> user;
  final String userAuthKey;
  const ExploreProductScreen({Key? key, required this.user, required this.userAuthKey}) : super(key: key);

  @override
  State<ExploreProductScreen> createState() => _ExploreProductScreenState();
}

class _ExploreProductScreenState extends State<ExploreProductScreen> {
  AfricanCountryInfo _individualsDestination = kAfricanCountries.first;
  String _businessInvoiceCurrency = 'USD';

  void _openPersona(_Persona persona) {
    switch (persona.title) {
      case "Freelancers & remote workers":
      case "Exporters & global sellers":
        Navigator.push(context,
            SlideRightRoute(page: TopUpScreen(user: widget.user, userAuthKey: widget.userAuthKey)));
        break;
      case "The diaspora":
      case "Students abroad":
        Navigator.push(
          context,
          SlideRightRoute(
            page: Scaffold(
              backgroundColor: AppColors.scaffold,
              appBar: AppBar(
                title: Text(persona.title),
                backgroundColor: Colors.transparent,
                elevation: 0,
                foregroundColor: AppColors.ink,
              ),
              body: SafeArea(
                child: AfricaCorridorScreen(
                  user: widget.user,
                  userAuthKey: widget.userAuthKey,
                  title: persona.title,
                  subtitle: persona.subtitle,
                  variant: AfricaCorridorVariant.diaspora,
                  initialDestination: _individualsDestination,
                ),
              ),
            ),
          ),
        );
        break;
      case "Importers & traders":
        Navigator.push(
          context,
          SlideRightRoute(
            page: WireTransferRequestScreen(
              user: widget.user,
              userAuthKey: widget.userAuthKey,
            ),
          ),
        );
        break;
      case "Builders":
        Navigator.push(context, SlideRightRoute(page: _BuildersApiRequestScreen()));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text("Explore Dutch Remit",
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.ink)),
        const SizedBox(height: 6),
        Text("Find the flow that looks like yours.",
            style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
        const SizedBox(height: 22),
        for (final category in _kCategories) ...[
          _buildCategorySection(category),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _buildCategorySection(_Category category) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(category.sectionIcon, color: AppColors.primary, size: 17),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(category.name,
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.ink)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(category.description,
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4)),
          const SizedBox(height: 14),
          _buildCategoryInput(category.name),
          const SizedBox(height: 14),
          ...category.personas.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  onTap: () => _openPersona(p),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Row(
                      children: [
                        Icon(p.icon, color: AppColors.primary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.title,
                                  style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink)),
                              const SizedBox(height: 2),
                              Text(p.subtitle,
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: Text(p.ctaLabel,
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
        ],
      ),
    );
  }

  /// Each section's own dedicated quick-input, matching what that
  /// category actually needs before routing into a flow — a
  /// destination-country picker for individuals sending money home,
  /// an invoice-currency picker for businesses getting paid, and a
  /// one-line pitch prompt for developers (their real input is the
  /// API-access form on the next screen).
  Widget _buildCategoryInput(String categoryName) {
    switch (categoryName) {
      case "For individuals":
        return InkWell(
          onTap: _pickIndividualsDestination,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Icon(Icons.flag_outlined, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Sending to ${_individualsDestination.flagEmoji} ${_individualsDestination.countryName}",
                    style: TextStyle(fontSize: 13, color: AppColors.ink, fontWeight: FontWeight.w600),
                  ),
                ),
                Icon(Icons.expand_more_rounded, size: 18, color: AppColors.textMuted),
              ],
            ),
          ),
        );
      case "For business":
        return Row(
          children: [
            Icon(Icons.payments_outlined, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text("Invoice currency", style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const Spacer(),
            DropdownButton<String>(
              value: _businessInvoiceCurrency,
              underline: const SizedBox.shrink(),
              items: const ['USD', 'GBP', 'EUR']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _businessInvoiceCurrency = value);
              },
            ),
          ],
        );
      case "For developers":
        return Row(
          children: [
            Icon(Icons.description_outlined, size: 16, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Payouts, collections and FX behind one API.",
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _pickIndividualsDestination() async {
    final picked = await showAfricanCountryPicker(context,
        currentCountry: _individualsDestination.countryName, onlyLiveCorridors: true);
    if (picked != null) setState(() => _individualsDestination = picked);
  }
}

class _BuildersApiRequestScreen extends StatefulWidget {
  @override
  State<_BuildersApiRequestScreen> createState() => _BuildersApiRequestScreenState();
}

class _BuildersApiRequestScreenState extends State<_BuildersApiRequestScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _companyController = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  /// Opens the device's real mail app with a pre-filled message to
  /// ikomihenry@dubiabank.com, carrying whatever the developer typed
  /// in. This is the actual submission — there's no backend endpoint
  /// for API-access requests, so a real mailto: deep link is the
  /// honest way to make "Request access" genuinely send something,
  /// rather than just flipping a local success flag with nothing
  /// behind it (which is what this screen did before).
  void _submitRequest() {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final company = _companyController.text.trim();

    final subject = Uri.encodeComponent('Dutch Remit API access request — $name');
    final bodyLines = [
      'Name: $name',
      'Work email: $email',
      if (company.isNotEmpty) 'Company: $company',
      '',
      '(Sent from the Dutch Remit app — For developers)',
    ];
    final body = Uri.encodeComponent(bodyLines.join('\n'));

    launchExternalURL('mailto:ikomihenry@dubiabank.com?subject=$subject&body=$body');
    setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: Text("Builders"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.ink,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Text("Embed payouts, collections and FX",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink)),
            const SizedBox(height: 10),
            Text(
              "Plug Dutch Remit's rails into your own product: payout African recipients, "
              "collect from global buyers, and hold multi-currency balances — all under your brand.",
              style: TextStyle(fontSize: 14, color: AppColors.inkMuted, height: 1.5),
            ),
            const SizedBox(height: 20),
            _row(Icons.send_rounded, "Payouts", "Send to mobile money and bank accounts across Africa."),
            _row(Icons.call_received_rounded, "Collections", "Accept payments in USD, EUR, GBP and more."),
            _row(Icons.currency_exchange_rounded, "FX", "Live, transparent rates on every conversion."),
            const SizedBox(height: 22),
            Divider(color: AppColors.divider),
            const SizedBox(height: 18),
            Text("Request API access",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 4),
            Text(
              "Tell us a bit about what you're building. Tapping Request access opens your mail app with your details ready to send.",
              style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            if (_submitted)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text("Opened your mail app — send it to reach us.",
                          style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              )
            else ...[
              _field(_nameController, "Your name"),
              const SizedBox(height: 10),
              _field(_emailController, "Work email", keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 10),
              _field(_companyController, "Company (optional)"),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_nameController.text.trim().isNotEmpty &&
                          _emailController.text.trim().isNotEmpty)
                      ? _submitRequest
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                  ),
                  child: Text("Request access", style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String hint, {TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: AppColors.border),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  const SizedBox(height: 2),
                  Text(sub, style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ],
              ),
            ),
          ],
        ),
      );
}
