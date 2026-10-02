import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/models/connection.dart';
import 'package:hermes_android/core/services/desktop_gateway_client.dart';

SavedConnection _connection({
  String? gatewayPrefix,
  String? desktopGatewayUrl,
}) {
  return SavedConnection(
    id: 'test',
    label: 'Test',
    host: '127.0.0.1',
    port: 8642,
    apiKey: 'test-key',
    gatewayPrefix: gatewayPrefix,
    desktopGatewayUrl: desktopGatewayUrl,
  );
}

void main() {
  group('documentIntakeProfileForConnection', () {
    test('maps the three ATLAS profile routes', () {
      expect(
        documentIntakeProfileForConnection(
          _connection(gatewayPrefix: '/organizator'),
        ),
        'organizator',
      );
      expect(
        documentIntakeProfileForConnection(_connection(gatewayPrefix: '/pro')),
        'pro',
      );
      expect(
        documentIntakeProfileForConnection(
          _connection(gatewayPrefix: '/personal'),
        ),
        'personal',
      );
    });

    test('uses the Desktop Gateway URL when the API prefix is absent', () {
      expect(
        documentIntakeProfileForConnection(
          _connection(
            desktopGatewayUrl: 'https://gateway.example.test/pro/dashboard',
          ),
        ),
        'pro',
      );
    });

    test('defaults unknown routes to organizator without partial matches', () {
      expect(
        documentIntakeProfileForConnection(
          _connection(gatewayPrefix: '/profile/project'),
        ),
        'organizator',
      );
    });
  });
}
