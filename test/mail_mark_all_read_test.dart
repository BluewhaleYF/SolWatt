import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';

import 'package:solwatt/core/config.dart';
import 'package:solwatt/main.dart';
import 'package:solwatt/mail/mail_address_suggestion.dart';
import 'package:solwatt/network.dart';
import 'package:solwatt/realtime/realtime.dart';
import 'package:solwatt/websocket.dart';

const _mailboxWork = MailMailbox(
  id: 'mb-1',
  accountId: 'acc-1',
  workspaceId: 'ws-1',
  address: 'work@example.com',
  name: 'Work',
  isDefault: true,
  isVerified: true,
);

const _workspace = Workspace(
  id: 'ws-1',
  slug: 'ws-1',
  name: 'Test Workspace',
  isBundled: false,
);

/// Records the scope of every bulk read sweep the UI asks for, so the menu's
/// two entries can be told apart.
class _FakeMailClient extends WattEngineClient {
  _FakeMailClient() : super(SolarNetworkAuthenticator(FlutterSecureStorage()));

  final markedAllRead = <({String? mailboxId, String? folder})>[];

  @override
  Future<int> markAllRead({String? mailboxId, String? folder}) async {
    markedAllRead.add((mailboxId: mailboxId, folder: folder));
    return 2;
  }
}

MailThread _thread(String id) => MailThread(
  id: 't-$id',
  mailboxId: 'mb-1',
  subject: 'Subject $id',
  messageCount: 1,
  unreadCount: 1,
  participants: const ['alice@example.com'],
  latestMessage: MailEmail(
    id: id,
    mailboxId: 'mb-1',
    threadId: 't-$id',
    subject: 'Subject $id',
    body: 'Body',
    contentType: 'text/plain',
    isDraft: false,
    folder: 'inbox',
    from: const MailRecipient(address: 'alice@example.com', name: 'Alice'),
    createdAt: DateTime(2026, 9, 25, 10),
  ),
  latestAt: DateTime(2026, 9, 25, 10),
);

Future<void> _pumpMailApp(WidgetTester tester, _FakeMailClient client) async {
  tester.binding.platformDispatcher.platformBrightnessTestValue =
      Brightness.dark;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('window_manager'),
    (call) async => switch (call.method) {
      'isMaximized' => false,
      _ => null,
    },
  );

  final threads = [_thread('e-1'), _thread('e-2')];
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appAccessProvider.overrideWith(
          (ref) => const AsyncValue.data(AppAccess.ready),
        ),
        selectedWorkspaceProvider.overrideWith((ref) async => _workspace),
        mailboxesProvider.overrideWith((ref) async => const [_mailboxWork]),
        mailHostProvider.overrideWith((ref) async => 'example.com'),
        mailboxUnreadCountsProvider.overrideWith(
          (ref) async => const {'mb-1': 2},
        ),
        mailCredentialsProvider.overrideWith(
          (ref) async => const <MailCredential>[],
        ),
        mailSenderIndexProvider.overrideWith(
          (ref) async => const <String, MailAddressSuggestion>{},
        ),
        threadsProvider.overrideWith(
          (ref, query) async =>
              PaginatedResult<MailThread>(items: threads, totalCount: 2),
        ),
        threadProvider.overrideWith(
          (ref, id) async =>
              [threads.firstWhere((thread) => thread.id == id).latestMessage],
        ),
        emailProvider.overrideWith(
          (ref, id) async => threads
              .firstWhere((thread) => thread.latestMessage.id == id)
              .latestMessage,
        ),
        wattEngineClientProvider.overrideWith((ref) => client),
        realtimeBridgeProvider.overrideWith((ref) => RealtimeBridge(ref)),
        websocketStateProvider.overrideWith(WebSocketStateNotifier.new),
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/i18n',
        fallbackLocale: const Locale('en', 'US'),
        useFallbackTranslations: true,
        child: SolWattApp(),
      ),
    ),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 10),
  );
}

/// Confirms the sweep dialog and lets its snackbar land.
Future<void> _confirmSweep(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Mark read'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _settleMail(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 10),
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the list header sweeps unread mail per folder and per mailbox', (
    tester,
  ) async {
    final client = _FakeMailClient();
    await _pumpMailApp(tester, client);
    expect(find.text('Subject e-1'), findsWidgets);

    // Folder scope: the header's overflow marks only the open folder read.
    await tester.tap(find.byIcon(Symbols.mark_email_read));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark folder as read'));
    await tester.pumpAndSettle();
    await _confirmSweep(tester);
    expect(client.markedAllRead, [(mailboxId: 'mb-1', folder: 'inbox')]);
    expect(find.text('Marked 2 messages as read.'), findsOneWidget);
    await _settleMail(tester);

    // Mailbox scope: the same menu drops the folder for the whole address.
    await tester.tap(find.byIcon(Symbols.mark_email_read));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark mailbox as read'));
    await tester.pumpAndSettle();
    await _confirmSweep(tester);
    expect(client.markedAllRead.last, (mailboxId: 'mb-1', folder: null));
    expect(find.text('Marked 2 messages as read.'), findsOneWidget);
  });
}
