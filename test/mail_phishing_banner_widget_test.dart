import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:solwatt/mail/mail_screen.dart';

import 'mail_phishing_fixtures.dart';

/// One pump per file: the localization harness installs the delegate once, and
/// a second `pumpWidget` in the same isolate renders an empty tree.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('renders the verdict for forged, suspicious and clean senders', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizationHarness(
        Column(
          children: [
            MailSenderSafetyBanner(
              email: emailFixture(authentication: phishingVerdict()),
            ),
            MailSenderSafetyBanner(
              email: emailFixture(
                authentication: {
                  'spf': 'fail',
                  'warnings': [
                    'Possible phishing: SPF verification failed',
                    'Some future verdict',
                  ],
                },
              ),
            ),
            MailSenderSafetyBanner(email: emailFixture()),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Forged sender: escalated title, both warnings, and the hint. The reason
    // and the warning carrying the same verdict collapse into one line.
    expect(find.text('senderSafetyPhishingTitle'.tr()), findsOneWidget);
    expect(find.text('senderSafetyPhishingHint'.tr()), findsOneWidget);
    expect(find.text('senderWarningSpoofedSender'.tr()), findsOneWidget);
    expect(find.text('senderWarningDmarcReject'.tr()), findsOneWidget);
    expect(find.byIcon(Symbols.phishing), findsOneWidget);

    // Bare warnings: lower-intensity title, mapped line, and an unrecognised
    // server string shown verbatim.
    expect(find.text('senderSafetySuspiciousTitle'.tr()), findsOneWidget);
    expect(find.text('senderWarningSpfFail'.tr()), findsOneWidget);
    expect(find.text('Some future verdict'), findsOneWidget);
    expect(find.byIcon(Symbols.warning), findsOneWidget);

    // The message without a verdict contributes no banner copy at all.
    expect(find.text('senderWarningBlockedSender'.tr()), findsNothing);
    expect(find.text('senderWarningDkimInvalid'.tr()), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
