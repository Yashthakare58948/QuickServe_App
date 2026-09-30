import 'package:flutter_test/flutter_test.dart';

import 'package:quickserve/domain/enums.dart';
import 'package:quickserve/domain/validators.dart';

void main() {
  group('Validators.email', () {
    test('rejects empty and malformed emails', () {
      expect(Validators.email(null), isNotNull);
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
    });

    test('accepts a valid email', () {
      expect(Validators.email(' user@demo.dev '), isNull);
    });
  });

  group('Validators.password', () {
    test('requires 8+ characters', () {
      expect(Validators.password('short'), isNotNull);
      expect(Validators.password('longenough'), isNull);
    });
  });

  group('StatusRules', () {
    test('mirrors the database transition table', () {
      expect(
        StatusRules.isValid(RequestStatus.created, RequestStatus.assigned),
        isTrue,
      );
      expect(
        StatusRules.isValid(RequestStatus.created, RequestStatus.completed),
        isFalse,
      );
      expect(
        StatusRules.isValid(RequestStatus.completed, RequestStatus.cancelled),
        isFalse,
      );
      expect(
        StatusRules.isValid(RequestStatus.inProgress, RequestStatus.completed),
        isTrue,
      );
    });

    test('customers may only cancel while created or assigned', () {
      expect(StatusRules.customerCanCancel(RequestStatus.created), isTrue);
      expect(StatusRules.customerCanCancel(RequestStatus.assigned), isTrue);
      expect(StatusRules.customerCanCancel(RequestStatus.inProgress), isFalse);
      expect(StatusRules.customerCanCancel(RequestStatus.completed), isFalse);
    });

    test('agent happy path: accept -> start -> complete', () {
      expect(StatusRules.agentNext(RequestStatus.assigned),
          RequestStatus.accepted);
      expect(StatusRules.agentNext(RequestStatus.accepted),
          RequestStatus.inProgress);
      expect(StatusRules.agentNext(RequestStatus.inProgress),
          RequestStatus.completed);
      expect(StatusRules.agentNext(RequestStatus.created), isNull);
    });
  });

  group('RequestId', () {
    test('formats REQ-YYYY-NNNNNN', () {
      expect(RequestId.format(123, year: 2026), 'REQ-2026-000123');
      expect(RequestId.format(7, year: 2026), 'REQ-2026-000007');
    });

    test('validates ids', () {
      expect(RequestId.isValid('REQ-2026-000123'), isTrue);
      expect(RequestId.isValid('REQ-26-1'), isFalse);
      expect(RequestId.isValid(''), isFalse);
    });
  });
}
