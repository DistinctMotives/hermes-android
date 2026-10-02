import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/capability_registry.dart';
import 'package:hermes_android/core/services/ws_client.dart';

Map<String, dynamic> _readyFrame({
  String protocolName = 'hermes-jsonrpc',
  int protocolMajor = 2,
  Map<String, dynamic>? capabilities,
}) {
  return {
    'jsonrpc': '2.0',
    'method': 'event',
    'params': {
      'type': 'gateway.ready',
      'payload': {
        'protocol': {'name': protocolName, 'major': protocolMajor},
        'capabilities':
            capabilities ??
            {
              'projects': {'version': 1},
              'turn_recovery': {'version': 2},
            },
      },
    },
  };
}

void main() {
  group('CapabilityRegistry ready frame', () {
    test('ingests the protocol and the advertised families', () {
      final registry = CapabilityRegistry();

      final accepted = registry.ingestGatewayReady(_readyFrame());

      expect(accepted, isTrue);
      expect(registry.protocolName, 'hermes-jsonrpc');
      expect(registry.protocolMajor, 2);
      expect(registry.advertises('projects'), isTrue);
      expect(registry.advertises('turn_recovery'), isTrue);
      expect(registry.advertised('turn_recovery'), {'version': 2});
    });

    test('ignores a frame that is not gateway.ready', () {
      final registry = CapabilityRegistry()..ingestGatewayReady(_readyFrame());

      final accepted = registry.ingestGatewayReady({
        'jsonrpc': '2.0',
        'method': 'event',
        'params': {'type': 'turn.delta', 'payload': <String, dynamic>{}},
      });

      expect(accepted, isFalse);
      // The previous, valid advertisement must survive an unrelated event.
      expect(registry.advertises('projects'), isTrue);
    });

    test('an advertised family makes its methods supported', () {
      final registry = CapabilityRegistry()..ingestGatewayReady(_readyFrame());

      expect(registry.supportFor('projects.list'), CapabilitySupport.supported);
      expect(registry.isSupported('projects.create'), isTrue);
    });

    test('resolves turn.* through the turn_recovery alias', () {
      final registry = CapabilityRegistry()..ingestGatewayReady(_readyFrame());

      expect(
        registry.supportFor('turn.reconcile'),
        CapabilitySupport.supported,
      );
    });

    test('absence from the ready frame never means unsupported', () {
      final registry = CapabilityRegistry()
        ..ingestGatewayReady(_readyFrame(capabilities: const {}));

      // Older gateways advertise nothing yet still implement the method, so a
      // silent ready frame may only produce `unknown`, never `unsupported`.
      expect(registry.supportFor('projects.list'), CapabilitySupport.unknown);
      expect(registry.isUnsupported('projects.list'), isFalse);
    });

    test('an unprobed method on a silent gateway is unknown', () {
      final registry = CapabilityRegistry();

      expect(registry.supportFor('fs.list'), CapabilitySupport.unknown);
      expect(registry.isSupported('fs.list'), isFalse);
    });
  });

  group('CapabilityRegistry probes', () {
    test('a successful call marks an unadvertised method supported', () {
      final registry = CapabilityRegistry()..recordSuccess('fs.list');

      expect(registry.supportFor('fs.list'), CapabilitySupport.supported);
    });

    test('an unknown-method error marks the method unsupported', () {
      final registry = CapabilityRegistry()
        ..recordFailure(
          'projects.list',
          JsonRpcError('projects.list', 'unknown method', code: -32601),
        );

      expect(
        registry.supportFor('projects.list'),
        CapabilitySupport.unsupported,
      );
    });

    test('a method-not-found message without a code still counts', () {
      final registry = CapabilityRegistry()
        ..recordFailure(
          'projects.list',
          JsonRpcError('projects.list', 'Method not found'),
        );

      expect(
        registry.supportFor('projects.list'),
        CapabilitySupport.unsupported,
      );
    });

    test('a domain error proves the method exists', () {
      final registry = CapabilityRegistry()
        ..recordFailure(
          'projects.get',
          JsonRpcError('projects.get', 'no such project', code: -32001),
        );

      expect(registry.supportFor('projects.get'), CapabilitySupport.supported);
    });

    test('a transport failure leaves the verdict unknown', () {
      final registry = CapabilityRegistry()
        ..recordFailure('projects.list', StateError('socket closed'));

      expect(registry.supportFor('projects.list'), CapabilitySupport.unknown);
    });

    test('a closed connection is not proof the method exists', () {
      // WsClient synthesises this locally when the socket dies mid-call; the
      // gateway never answered, so it may not promote the method.
      final registry = CapabilityRegistry()
        ..recordFailure(
          'projects.list',
          JsonRpcError(
            'projects.list',
            'Desktop gateway connection closed',
            reason: 'connection_closed',
          ),
        );

      expect(registry.supportFor('projects.list'), CapabilitySupport.unknown);
    });

    test('a timeout is not proof the method exists', () {
      final registry = CapabilityRegistry()
        ..recordFailure(
          'projects.list',
          JsonRpcError('projects.list', 'Timeout'),
        );

      expect(registry.supportFor('projects.list'), CapabilitySupport.unknown);
    });

    test('an observation outranks the ready frame', () {
      final registry = CapabilityRegistry()
        ..ingestGatewayReady(_readyFrame())
        ..recordFailure(
          'projects.list',
          JsonRpcError('projects.list', 'unknown method', code: -32601),
        );

      expect(
        registry.supportFor('projects.list'),
        CapabilitySupport.unsupported,
      );
      // Only the probed method is downgraded; the family stays advertised.
      expect(
        registry.supportFor('projects.create'),
        CapabilitySupport.supported,
      );
    });

    test('reset clears probes and advertisements for a new connection', () {
      final registry = CapabilityRegistry()
        ..ingestGatewayReady(_readyFrame())
        ..recordFailure(
          'projects.list',
          JsonRpcError('projects.list', 'unknown method', code: -32601),
        )
        ..reset();

      expect(registry.protocolName, isNull);
      expect(registry.advertises('projects'), isFalse);
      expect(registry.supportFor('projects.list'), CapabilitySupport.unknown);
    });

    test('notifies listeners when a verdict changes', () {
      var notifications = 0;
      final registry = CapabilityRegistry()..addListener(() => notifications++);

      registry.recordSuccess('fs.list');
      expect(notifications, 1);

      // A repeated identical observation must not churn the UI.
      registry.recordSuccess('fs.list');
      expect(notifications, 1);
    });
  });

  group('CapabilityRegistry bound to a live socket', () {
    late HttpServer server;
    late List<WebSocket> sockets;

    setUp(() async {
      sockets = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.add(jsonEncode(_readyFrame()));
        socket.listen((_) {});
      });
    });

    tearDown(() async {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.close(force: true);
    });

    test('learns the capabilities a real gateway advertises', () async {
      final registry = CapabilityRegistry();
      final client = WsClient('http://127.0.0.1:${server.port}');
      registry.bindTo(client);

      try {
        await client.connect();
        await client.waitForGatewayReady(timeout: const Duration(seconds: 5));

        expect(registry.protocolName, 'hermes-jsonrpc');
        expect(registry.protocolMajor, 2);
        expect(
          registry.supportFor('projects.list'),
          CapabilitySupport.supported,
        );
      } finally {
        client.close();
      }
    });

    test('binding preserves an existing onGatewayReady listener', () async {
      final registry = CapabilityRegistry();
      final seen = Completer<Map<String, dynamic>>();
      final client = WsClient('http://127.0.0.1:${server.port}')
        ..onGatewayReady = (frame) {
          if (!seen.isCompleted) seen.complete(frame);
        };
      registry.bindTo(client);

      try {
        await client.connect();
        final frame = await seen.future.timeout(const Duration(seconds: 5));

        expect(frame['method'], 'event');
        expect(registry.advertises('projects'), isTrue);
      } finally {
        client.close();
      }
    });
  });
}
