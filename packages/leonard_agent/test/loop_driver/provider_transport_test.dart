import 'dart:async';
import 'dart:io' show HttpException, SocketException;

import 'package:http/http.dart' show ClientException;
import 'package:leonard_agent/leonard_agent.dart';
import 'package:test/test.dart';

/// An exception with no transport meaning at all.
class _Unrelated implements Exception {
  const _Unrelated();

  @override
  String toString() => 'unrelated';
}

void main() {
  group('isProviderTransportError', () {
    test('classifies package:http ClientException', () {
      expect(
        isProviderTransportError(
          ClientException(
            'Connection closed while receiving data, '
            'uri=http://localhost:8080/v1/messages',
          ),
        ),
        isTrue,
      );
    });

    test('classifies TimeoutException', () {
      expect(isProviderTransportError(TimeoutException('slow')), isTrue);
    });

    test('classifies dart:io SocketException and HttpException by name', () {
      expect(isProviderTransportError(const SocketException('closed')), isTrue);
      expect(isProviderTransportError(const HttpException('bad')), isTrue);
      expect(kIoTransportExceptionNames, contains('SocketException'));
    });

    test('does NOT classify unrelated failures', () {
      expect(isProviderTransportError(const _Unrelated()), isFalse);
      expect(isProviderTransportError(StateError('boom')), isFalse);
    });
  });

  group('scrubCredentials', () {
    test('redacts an authorization header to end of line', () {
      expect(
        scrubCredentials('authorization: Bearer tok-abc\nnext line'),
        'authorization: <redacted>\nnext line',
      );
    });

    test('redacts a bare bearer token', () {
      expect(
        scrubCredentials('sent Bearer tok-abc now'),
        'sent Bearer <redacted> now',
      );
    });

    test('redacts a token query parameter', () {
      expect(
        scrubCredentials('http://h/v1/messages?token=abc123&x=1'),
        'http://h/v1/messages?token=<redacted>&x=1',
      );
    });

    test(
      'leaves an endpoint URL byte-identical (configuration, not a credential)',
      () {
        const String line =
            'ClientException: Connection closed while receiving data, '
            'uri=http://localhost:8080/v1/messages';
        expect(scrubCredentials(line), line);
      },
    );
  });

  group('describeThrowable', () {
    test('names the runtime type and scrubs the message', () {
      final String d = describeThrowable(
        ClientException('closed; authorization: Bearer tok-abc'),
      );
      expect(d, startsWith('ClientException: '));
      expect(d, contains('<redacted>'));
      expect(d, isNot(contains('tok-abc')));
    });

    test('truncates a very long message', () {
      final String d = describeThrowable(StateError('x' * 500));
      expect(d, endsWith('…'));
      expect(d.length, lessThan(kMaxDetailLength + 60));
    });

    test('never returns empty for a null escapee', () {
      expect(describeThrowable(null), isNotEmpty);
    });
  });
}
