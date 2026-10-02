# Security

Do not report real gateway URLs, API keys, dashboard passwords, access tokens,
device profiles, or signing material in a public issue.

Before sharing diagnostics:

- replace private hostnames and IP addresses;
- remove Authorization, Cookie, and WebSocket ticket values;
- remove attached user files and conversation content;
- confirm that Android `key.properties`, keystores, and local environment files
  are not included.

The APK in the community `.13` prerelease is a debug test build. Do not use it
as a production-signed or store-distributed application.
