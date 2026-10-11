import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:solwatt/mail/mail_screen.dart';
import 'package:solwatt/network.dart';

import 'mail_phishing_fixtures.dart';

Map<String, String> catalog(String locale) {
  final file = File('assets/i18n/$locale.json');
  final decoded = json.decode(file.readAsStringSync()) as Map<String, dynamic>;
  return decoded.map((key, value) => MapEntry(key, value.toString()));
}

void main() {
  group('MailSenderAuthentication', () {
    test('parses the server verdict', () {
      final authentication = emailFixture(
        authentication: phishingVerdict(),
      ).authentication;
      expect(authentication, isNotNull);
      expect(authentication!.phishing, isTrue);
      expect(
        authentication.phishingReason,
        'Sender domain rejects unauthenticated mail (DMARC p=reject)',
      );
      expect(authentication.warnings, hasLength(2));
      expect(authentication.hasWarnings, isTrue);
    });

    test('is null when the server recorded no verdict', () {
      expect(emailFixture().authentication, isNull);
      expect(emailFixture().isPhishing, isFalse);
      expect(emailFixture().senderWarnings, isEmpty);
    });

    test('ignores a payload that is not an object', () {
      final email = MailEmail.fromJson({'id': 'e-1', 'authentication': 'yes'});
      expect(email.authentication, isNull);
    });

    test('drops blank warnings and keeps a clean verdict non-phishing', () {
      final authentication = MailSenderAuthentication.fromJson({
        'spf': 'pass',
        'dkim': 'pass',
        'dmarc': 'allow',
        'warnings': ['', '   '],
      });
      expect(authentication, isNotNull);
      expect(authentication!.phishing, isFalse);
      expect(authentication.hasWarnings, isFalse);
      expect(authentication.phishingReason, isNull);
    });
  });

  group('mailSenderSafetyLevel', () {
    test('shows nothing without a verdict', () {
      expect(mailSenderSafetyLevel(emailFixture()), MailSenderSafetyLevel.none);
    });

    test('shows nothing for a clean verdict', () {
      final email = emailFixture(
        authentication: {'spf': 'pass', 'dkim': 'pass', 'dmarc': 'allow'},
      );
      expect(mailSenderSafetyLevel(email), MailSenderSafetyLevel.none);
    });

    test('escalates warnings to suspicious', () {
      final email = emailFixture(
        authentication: {
          'spf': 'fail',
          'warnings': ['Possible phishing: SPF verification failed'],
        },
      );
      expect(mailSenderSafetyLevel(email), MailSenderSafetyLevel.suspicious);
    });

    test('ranks the forged-sender verdict above bare warnings', () {
      final email = emailFixture(authentication: phishingVerdict());
      expect(mailSenderSafetyLevel(email), MailSenderSafetyLevel.phishing);
    });

    test('treats a forged sender without warnings as phishing', () {
      final email = emailFixture(
        authentication: {'dmarc': 'reject', 'phishing': true},
      );
      expect(mailSenderSafetyLevel(email), MailSenderSafetyLevel.phishing);
    });
  });

  group('mailSenderWarningKey', () {
    test('maps every documented server warning to a catalog key', () {
      for (final entry in documentedWarnings.entries) {
        expect(mailSenderWarningKey(entry.key), entry.value);
        expect(mailSenderWarningKey('  ${entry.key}  '), entry.value);
      }
    });

    test('returns null for an unknown server warning', () {
      expect(mailSenderWarningKey('Some future verdict'), isNull);
    });

    test('keeps the mapping one-to-one', () {
      expect(
        documentedWarnings.values.toSet(),
        hasLength(documentedWarnings.length),
      );
    });
  });

  group('sender-safety catalog', () {
    test('defines every banner key in both locales', () {
      for (final locale in ['en-US', 'zh-CN']) {
        final entries = catalog(locale);
        for (final key in bannerKeys) {
          expect(entries[key], isNotNull, reason: '$locale is missing $key');
          expect(
            entries[key]!.trim(),
            isNotEmpty,
            reason: '$locale has empty $key',
          );
          expect(
            entries[key],
            isNot(contains('{')),
            reason: '$locale has a placeholder in $key',
          );
        }
      }
    });

    test('translates the copy instead of echoing the server text', () {
      final english = catalog('en-US');
      final chinese = catalog('zh-CN');
      for (final key in bannerKeys) {
        expect(
          english[key],
          isNot(chinese[key]),
          reason: '$key is untranslated',
        );
        // The mapped copy is a reader-facing sentence, not the server's
        // internal wording mapped back onto itself.
        expect(documentedWarnings.keys, isNot(contains(english[key])));
      }
      expect(
        english['senderSafetyPhishingTitle'],
        isNot(english['senderSafetySuspiciousTitle']),
      );
      // Chinese copy is actually Chinese.
      expect(
        RegExp(
          r'[\u4e00-\u9fff]',
        ).hasMatch(chinese['senderSafetyPhishingTitle']!),
        isTrue,
      );
    });
  });
}
