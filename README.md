# ConvoKit Flutter UI examples

Public, runnable examples showing how an application can configure
[`convokit_flutter_ui`](https://pub.dev/packages/convokit_flutter_ui) without
copying or modifying the package source.

This repository contains application code only. The examples depend on the
published `convokit_flutter_ui` and `convokit_flutter` packages.

## Component showcase

The default entry point uses local fixture data, so it runs without a backend,
client ID, or client secret:

```bash
flutter pub get
flutter run -d chrome
```

Use the selector in the app to compare the configurations. On Flutter web,
append `?variant=standard`, `?variant=branded`, or `?variant=compact` to open a
specific configuration.

The web runner is checked in; no `flutter create` step is needed. To produce a
static build of the fixture-only showcase:

```bash
flutter build web --release
```

Serve `build/web` through an HTTP server. The showcase does not issue tokens or
contact a ConvoKit backend. For hosting below a subdirectory, pass the matching
`--base-href=/your/path/` when building.

### Standard components

![Standard ConvoKit conversation list and chat components](doc/screenshots/standard-components.jpg)

Package defaults: the rows render the latest-message preview, activity time,
and unread badge from `summaries` and `currentUserId`, plus `onRefresh`,
`onAddAttachment`, `readPositionByUserId`, and `reverseMessages: true`. The
fixtures carry the private "mark unread" fields (`isUnread`, `unreadMarkedAt`,
`privateStateVersion`): one room has unread messages and shows the numeric
badge, another was marked unread with nothing new in it, so the default row
renders the package's numberless `ConvoKitUnreadDot` (announced as "Unread",
never as a count of 0).

### Branded customer support

![Branded ConvoKit customer support interface](doc/screenshots/branded-support.jpg)

A support treatment built with `rowBuilder` (custom rows that read the preview
and unread state from `ConvoKitInboxRow`: `ConvoKitUnreadBadge` for a count,
`ConvoKitUnreadDot` for a marked room without one), `headerBuilder`,
`mediaBlockBuilder`, `readReceiptBuilder`, and `composerBuilder`.

### Compact operations

![Compact ConvoKit operations interface](doc/screenshots/compact-operations.jpg)

A dense dashboard built with custom padding, separators, `rowBuilder` rows
that show their own dot for any unread state (`isUnread`, a count, or a capped
count) and the activity time, message rows, typing indicator, composer, and
`reverseMessages: false`.

The complete configuration is in
[`lib/showcase/component_showcase_app.dart`](lib/showcase/component_showcase_app.dart),
and its widget tests are in
[`test/component_showcase_test.dart`](test/component_showcase_test.dart).

## Live SDK-backed example

[`lib/live_example.dart`](lib/live_example.dart) demonstrates the minimal
SDK-backed conversation list and selected conversation flow. The list loads
`GET /api/v1/inbox` pages through the SDK and renders previews, activity times,
unread badges and the mark-unread dot by itself, refreshing on
`inbox_activity`. The page owns the `ConvoKitConversationListController` so the
open room's header (a `headerBuilder` app bar) can offer "Mark unread": it
calls `markUnread(conversationId)` on that controller, which sends
`POST /api/v1/conversations/:id/unread`, patches the row's summary from the
response, and returns to the list, where the default row shows the dot. The
room acknowledged itself with the private-state version captured when it
opened, so the marker survives that room's later acknowledgements and clears
the next time the room is opened; other devices refetch the list on
`inbox_activity`. It expects a public client ID and a token endpoint that keeps
the client secret on its server:

```bash
flutter run -d chrome -t lib/live_example.dart \
  --dart-define=CONVOKIT_CLIENT_ID=public-client-id \
  --dart-define=CONVOKIT_TOKEN_ENDPOINT=https://app.example.com/api/convokit-token
```

The managed `https://api.convokit.app` endpoint is automatic. Add
`--dart-define=CONVOKIT_BACKEND_URL=...` only for local testing or self-hosting.

Never put a ConvoKit client secret in Flutter application code or
`--dart-define` values.

## Verification

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build web --release
flutter build web --release -t lib/live_example.dart --output build/web-live
```

CI compiles both entry points. Without the live configuration defines, the
second build displays configuration help and does not connect; compilation is
not a live backend or Realtime acceptance test.
