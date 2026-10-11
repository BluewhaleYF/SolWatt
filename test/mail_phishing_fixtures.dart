import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/websocket.dart';

/// The server prints these verbatim in `authentication.warnings`; the reader
/// maps them to catalog keys.
const documentedWarnings = <String, String>{
  'Possible phishing: SPF verification failed': 'senderWarningSpfFail',
  'Possible forgery: DKIM signature is invalid': 'senderWarningDkimInvalid',
  'Domain policy rejects unauthenticated mail': 'senderWarningDmarcReject',
  'Domain policy quarantines unauthenticated mail':
      'senderWarningDmarcQuarantine',
  'Sender is blocked by a mailbox block rule': 'senderWarningBlockedSender',
  'Sender domain rejects unauthenticated mail (DMARC p=reject)':
      'senderWarningSpoofedSender',
};

/// Every catalog key the banner can render.
final bannerKeys = <String>[
  'senderSafetyPhishingTitle',
  'senderSafetySuspiciousTitle',
  'senderSafetyPhishingHint',
  ...documentedWarnings.values,
];

/// The phishing verdict ElecPostal records for a spoofed p=reject sender.
Map<String, dynamic> phishingVerdict() => {
  'spf': 'softfail',
  'dkim': 'none',
  'dmarc': 'reject',
  'score': 2.5,
  'phishing': true,
  'phishing_reason':
      'Sender domain rejects unauthenticated mail (DMARC p=reject)',
  'symbols': [
    {'name': 'R_SPF_SOFTFAIL', 'weight': 0.5},
    {'name': 'DMARC_POLICY_REJECT', 'weight': 2.0},
  ],
  'warnings': [
    'Domain policy rejects unauthenticated mail',
    'Likely phishing: Sender domain rejects unauthenticated mail (DMARC p=reject)',
  ],
};

Map<String, dynamic> emailJson({
  Map<String, dynamic>? authentication,
  String fromName = 'Alice',
}) => {
  'id': 'e-1',
  'mailbox_id': 'mb-1',
  'subject': 'Important: Review Your Payment and Billing Details',
  'body': 'Please review and update your payment information.',
  'is_draft': false,
  'from_address': 'support@anthropic.com',
  'from_name': fromName,
  'authentication': ?authentication,
};

MailEmail emailFixture({
  Map<String, dynamic>? authentication,
  String fromName = 'Alice',
}) => MailEmail.fromJson(
  emailJson(authentication: authentication, fromName: fromName),
);

MailThread threadFixture({Map<String, dynamic>? authentication}) =>
    MailThread.fromJson({
      'id': 't-1',
      'mailbox_id': 'mb-1',
      'subject': 'Important: Review Your Payment and Billing Details',
      'message_count': 1,
      'unread_count': 1,
      'participants': ['support@anthropic.com'],
      'latest_message': emailJson(authentication: authentication),
    });

/// Localization harness for a standalone widget, mirroring `main.dart`'s
/// wiring: `.tr()` resolves against the global localization instance, so the
/// delegate has to be in the tree and the locale pinned on the widget.
Widget localizationHarness(Widget child) => EasyLocalization(
  supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
  path: 'assets/i18n',
  fallbackLocale: const Locale('en', 'US'),
  startLocale: const Locale('en', 'US'),
  useFallbackTranslations: true,
  child: Builder(
    builder: (context) => MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: Scaffold(body: child),
    ),
  ),
);

/// Full app shell around the mail screen, mirroring the reader harness the
/// other mail tests use, so the banner can be asserted on the real reader
/// route.
Widget appHarness({
  required MailThread thread,
  required SharedPreferences prefs,
}) {
  const workspace = Workspace(
    id: 'ws-1',
    slug: 'ws-1',
    name: 'Test Workspace',
    isBundled: false,
  );
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appAccessProvider.overrideWith(
        (ref) => const AsyncValue.data(AppAccess.ready),
      ),
      selectedWorkspaceProvider.overrideWith((ref) async => workspace),
      mailboxesProvider.overrideWith(
        (ref) async => const [
          MailMailbox(
            id: 'mb-1',
            accountId: 'acc-1',
            workspaceId: 'ws-1',
            address: 'work@example.com',
            name: 'Work',
            isDefault: true,
            isVerified: true,
          ),
        ],
      ),
      mailHostProvider.overrideWith((ref) async => 'example.com'),
      mailboxUnreadCountsProvider.overrideWith(
        (ref) async => const {'mb-1': 1},
      ),
      mailCredentialsProvider.overrideWith(
        (ref) async => const <MailCredential>[],
      ),
      mailSenderIndexProvider.overrideWith(
        (ref) async => const <String, MailAddressSuggestion>{},
      ),
      threadsProvider.overrideWith(
        (ref, query) async =>
            PaginatedResult<MailThread>(items: [thread], totalCount: 1),
      ),
      threadProvider.overrideWith((ref, id) async => [thread.latestMessage]),
      emailProvider.overrideWith((ref, id) async => thread.latestMessage),
      realtimeBridgeProvider.overrideWith((ref) => RealtimeBridge(ref)),
      websocketStateProvider.overrideWith(WebSocketStateNotifier.new),
    ],
    child: EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/i18n',
      fallbackLocale: const Locale('en', 'US'),
      startLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      child: SolWattApp(),
    ),
  );
}
