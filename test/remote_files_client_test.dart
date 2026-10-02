import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hermes_android/core/services/connection_manager.dart';
import 'package:hermes_android/core/services/remote_files_client.dart';

void main() {
  DashboardClient dashboardWith(
    Future<http.Response> Function(http.Request request) handler,
  ) => DashboardClient(
    host: 'hermes.local',
    port: 9119,
    proxied: true,
    httpClient: MockClient(handler),
  );

  test('loads the default working directory', () async {
    final dashboard = dashboardWith((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/fs/default-cwd');
      return http.Response(
        jsonEncode({'cwd': '/srv/project', 'branch': 'main'}),
        200,
      );
    });
    final client = RemoteFilesClient(dashboard: dashboard);

    final root = await client.defaultDirectory();

    expect(root.path, '/srv/project');
    expect(root.branch, 'main');
    client.close();
  });

  test('lists directories before files and preserves server paths', () async {
    final dashboard = dashboardWith((request) async {
      expect(request.url.path, '/api/fs/list');
      expect(request.url.queryParameters['path'], '/srv/project');
      return http.Response(
        jsonEncode({
          'entries': [
            {
              'name': 'README.md',
              'path': '/srv/project/README.md',
              'isDirectory': false,
            },
            {'name': 'lib', 'path': '/srv/project/lib', 'isDirectory': true},
          ],
        }),
        200,
      );
    });
    final client = RemoteFilesClient(dashboard: dashboard);

    final entries = await client.listDirectory('/srv/project');

    expect(entries.map((entry) => entry.name), ['lib', 'README.md']);
    expect(entries.first.isDirectory, isTrue);
    client.close();
  });

  test('reads a text preview with language and truncation metadata', () async {
    final dashboard = dashboardWith((request) async {
      expect(request.url.path, '/api/fs/read-text');
      expect(request.url.queryParameters['path'], '/srv/project/main.dart');
      return http.Response(
        jsonEncode({
          'path': '/srv/project/main.dart',
          'text': 'void main() {}',
          'language': 'dart',
          'mimeType': 'text/x-dart',
          'byteSize': 14,
          'binary': false,
          'truncated': true,
        }),
        200,
      );
    });
    final client = RemoteFilesClient(dashboard: dashboard);

    final preview = await client.readText('/srv/project/main.dart');

    expect(preview.text, 'void main() {}');
    expect(preview.language, 'dart');
    expect(preview.truncated, isTrue);
    client.close();
  });

  test('downloads bytes with the server filename', () async {
    final dashboard = dashboardWith((request) async {
      expect(request.url.path, '/api/fs/download');
      expect(request.url.queryParameters['path'], '/srv/project/report.pdf');
      return http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-disposition': 'attachment; filename="report.pdf"'},
      );
    });
    final client = RemoteFilesClient(dashboard: dashboard);

    final download = await client.download('/srv/project/report.pdf');

    expect(download.filename, 'report.pdf');
    expect(download.bytes, [1, 2, 3]);
    client.close();
  });
}
