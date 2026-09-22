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
append `?variant=standard`, `?variant=branded`, `?variant=compact`, or
`?variant=quoted` to open a specific configuration.

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

Every message fixture carries the server `revision` (0 as created, one more
per content edit); one of the connected user's rows was edited once, so the
default row shows the package's "Edited" caption beside its time
(`Message.isEdited`, never a timestamp comparison). The controlled
`ConvoKitConversationView` receives `editingMessage`, `onEditMessage`,
`onSaveEdit`, `onCancelEdit` and `onDeleteMessage` from the page's local
state: a long press on one of the connected user's own confirmed rows (or the
"Message actions" accessibility action) opens the package's "Edit message" /
"Delete message" sheet, other members' rows offer neither. Edit puts the
default composer into its edit mode (an "Editing message" banner with Cancel,
the field prefilled, the send button becoming "Save message"); the fixture
callback stands in for the backend's `PATCH /api/v1/messages/:id/own` and
bumps the row's `revision`, so the caption appears. Delete asks the package's
"Delete this message?" confirmation first and the callback removes the row.

Quoted replies arrive through the same kind of props, added in 0.9.0:
`replyTarget`, `onReplyToMessage`, `onCancelReply`, `replyPreviewByMessageId`,
`onJumpToMessage`, `highlightedMessageId` and `onHighlightHandled`. The same
sheet now opens on **every** confirmed row, own or not, because any member may
quote any row, and it offers "Reply"; picking it sets the page's reply target,
which the default composer shows as a cancellable "Replying to" strip above
the field. Sending stores the target as `Message.replyToMessageId`, so the new
row renders its quoted block straight away. `replyPreviewByMessageId` has
three states and the fixture reaches all three: a `ReplyPreview` value is
resolved (the quoted author and text), and a key mapped to **null** is the
terminal "the original is gone" answer, rendered as "Original message
unavailable" with the reference and the jump affordance intact. An absent key
is the third, "not resolved yet" state, which renders the reference with no
quoted text and must not claim the original is gone. The page answers one
batched request per window a frame after the rows that need it are built, the
way a controller resolves previews over the network, so a reference is on
screen before its preview lands. One
fixture row quotes a message deleted before the snapshot, so the unavailable
state is visible without doing anything, and deleting one of the connected
user's own quoted rows turns every quote of it into the same state — the
replies keep pointing at it, because a reference is written once and never
rewritten. The edited fixture row is itself a reply, since an edit never
changes what a message quotes; the page applies edits with `Message.copyWith`
rather than rebuilding a row field by field, which is the mistake that would
silently drop the reference.

The page also renders a **window** of a longer fixture room rather than the
whole of it, the way a controller renders the page it fetched. The nine oldest
messages start outside it, `hasOlderMessages`/`onLoadOlder` extend it
backwards, and one reply quotes a message that is outside it: activating that
quoted block calls `onJumpToMessage`, the page replaces the window with a
bounded one centred on the target, and the package scrolls to that row,
flashes it for about two seconds and reports back through
`onHighlightHandled`. While the rendered window is not the newest page the
view offers "Jump to latest" (`hasNewerMessages`, `onReturnToLatest`) and a
newer-edge trigger (`onLoadNewer`); a newer page that reaches the newest
message returns to the live tail rather than flipping the window's mode in
place. Activating the quoted block of a message that is gone reports it the
way the backend's coded "not found" does, without disturbing the window.

### Branded customer support

![Branded ConvoKit customer support interface](doc/screenshots/branded-support.jpg)

A support treatment built with `rowBuilder` (custom rows that read the preview
and unread state from `ConvoKitInboxRow`: `ConvoKitUnreadBadge` for a count,
`ConvoKitUnreadDot` for a marked room without one), `headerBuilder`,
`mediaBlockBuilder`, `readReceiptBuilder`, and `composerBuilder`. The message
rows stay the package's, so they offer reply, edit and delete and render
quoted blocks; the custom composer shows its own "Editing your reply" banner
with a Cancel action while a row is edited, its own "Quoting …" banner with a
"Cancel quote" action while a row is quoted, and labels its button "Save".
`ConvoKitComposerBuilder` is unchanged in 0.9.0 (its `send` saves while
`editingMessage` is set and sends otherwise, quoting the reply target when one
is set), so the page hands both pieces of state to the custom composer next to
the package arguments instead of branching inside it. This configuration runs
the history oldest-first, so the reply whose quoted message is outside the
loaded window is on screen straight away: activating its quoted block loads
that window and offers "Jump to latest" to come back.

### Compact operations

![Compact ConvoKit operations interface](doc/screenshots/compact-operations.jpg)

A dense dashboard built with custom padding, separators, `rowBuilder` rows
that show their own dot for any unread state (`isUnread`, a count, or a capped
count) and the activity time, message rows that read `Message.isEdited` for
their own "Edited" caption, typing indicator, composer, and
`reverseMessages: false`.

`ConvoKitMessageItemBuilder` keeps its six positional parameters in 0.9.0, and
this configuration is the proof: its row function is unchanged and renders
exactly as it did. That also shows the trade — a frozen builder receives no
quoted-reply members, so these rows carry no quoted block and offer no
"Reply". A row that needs them uses `messageContextBuilder` instead, which the
next configuration demonstrates.

### Quoted rows

The standard configuration with a single override: `messageContextBuilder`,
added in 0.9.0 beside `messageBuilder`. Its rows are the page's own widgets,
built from a `ConvoKitMessageItemScope` that carries every argument the frozen
`ConvoKitMessageItemBuilder` carries — `message`, `chronologicalIndex`,
`isCurrentUser`, `sender`, `readerIds` — so a row can migrate to it without
losing one, plus `isReply`, `replyPreview`, `replyTargetUnavailable`,
`canReply`, `reply` and `jumpToReplyTarget`. These rows read all five of the
frozen arguments off the scope rather than looking any of them up again: the
author comes from `scope.sender` and the row's place in the loaded window,
announced with the row, from `scope.chronologicalIndex`. They render their own
quoted block with the three preview states, their own "Reply" action
(`reply` is non-null exactly when `canReply`) and their own jump affordance,
while the composer, its "Replying to" strip and the highlight stay the
package's. When a host sets both builders the scope builder wins. This
configuration also sets the theme's new `highlightColor`, the flash behind a
row a jump landed on; leaving it null uses the accent colour at low opacity.

There is no separate screenshot for this configuration: it is the standard
treatment with page-built rows.

All four configurations are in
[`lib/showcase/component_showcase_app.dart`](lib/showcase/component_showcase_app.dart),
and their widget tests are in
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
`inbox_activity`. The room keeps the package's default rows and composer, so
editing and deleting the connected user's own messages needs no code here:
a long press on an own row opens "Edit message" / "Delete message", the
composer's edit mode saves through `PATCH /api/v1/messages/:id/own` with the
`revision` captured when editing began (a 409 `REVISION_CONFLICT` reloads the
row, shows the changed content and keeps the draft), and a confirmed delete
sends `DELETE /api/v1/messages/:id/own`; other devices show the "Edited"
caption from the live row image and drop a deleted row on the room's
deletion notification. Deleting cannot be undone, and files already received
cannot be retracted. The author routes need the 0.8 backend.

Quoting needs no code here either. Every confirmed row offers "Reply", the
composer shows its cancellable "Replying to" strip, the sent message carries
`replyToMessageId`, and the quoted block's text comes from one batched request
per rendered page rather than one per row. Activating a quoted block opens the
quoted message: if it is outside the loaded history the controller loads a
bounded window around it, scrolls to it and flashes it, and the room offers
"Jump to latest" until it rejoins its newest page. A quoted message that was
edited shows its new text, and one that was deleted leaves the reply and its
reference in place under "Original message unavailable". The quoted-reply
routes need the 0.9 backend: against an older one the controller hides the
jump affordance after the first answer and leaves quoted text unresolved
(never "unavailable"), and a message quoted to it is delivered without its
reference, so the quote disappears when the row is confirmed.

It expects a public client ID and a token endpoint that keeps the client
secret on its server:

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
