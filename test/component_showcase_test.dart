import 'package:convokit_flutter_ui/convokit_flutter_ui.dart';
import 'package:convokit_flutter_ui_examples/showcase/component_showcase_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpShowcase(
    WidgetTester tester,
    ShowcaseVariant variant,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 820);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(ComponentShowcaseApp(initialVariant: variant));
    await tester.pump();
  }

  // The page scrolls and the reversed history clips its oldest rows, so
  // every interaction first scrolls its target into view.
  Future<void> pressAndSettle(
    WidgetTester tester,
    Finder target, {
    bool long = false,
  }) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    if (long) {
      await tester.longPress(target);
    } else {
      await tester.tap(target);
    }
    await tester.pumpAndSettle();
  }

  // Drags the message history of one configuration until [text] is built;
  // a positive step moves toward the oldest end of a reversed list.
  Future<void> dragHistory(
    WidgetTester tester,
    ShowcaseVariant variant,
    String text, {
    double step = 120,
  }) async {
    await tester.dragUntilVisible(
      find.text(text),
      find.descendant(
        of: find.byKey(ValueKey('chat-view-${variant.name}')),
        matching: find.byType(ListView),
      ),
      Offset(0, step),
    );
    await tester.pumpAndSettle();
  }

  // Returns a reversed history to its newest end. `ensureVisible` aligns its
  // target with the leading edge, so interacting with an older row leaves the
  // newest ones unbuilt until the list is scrolled back.
  Future<void> showNewest(WidgetTester tester, ShowcaseVariant variant) async {
    await tester.drag(
      find.descendant(
        of: find.byKey(ValueKey('chat-view-${variant.name}')),
        matching: find.byType(ListView),
      ),
      const Offset(0, -900),
    );
    await tester.pumpAndSettle();
  }

  // Lets the package's ~2 second flash and its scroll guard expire, so a jump
  // leaves no pending timer behind.
  Future<void> settleHighlight(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  testWidgets('standard view renders both package components with defaults', (
    tester,
  ) async {
    await pumpShowcase(tester, ShowcaseVariant.standard);

    expect(
      find.byKey(const ValueKey('conversation-list-standard')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('chat-view-standard')), findsOneWidget);
    expect(find.text('1 · Standard components'), findsOneWidget);
    expect(find.text('Customer operations'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Write a message'), findsOneWidget);
    // The fixture row with revision 1 renders the package's "Edited" caption.
    expect(find.text('Edited'), findsOneWidget);

    // Default rows render the summaries: previews, times and the unread badge.
    expect(
      find.text('You: I linked this conversation to the support case.'),
      findsOneWidget,
    );
    expect(
      find.text('Alex Rivera: Refund approved, closing the ticket.'),
      findsOneWidget,
    );
    expect(find.text('Jordan Lee: Photo'), findsOneWidget);
    final badge = find.byType(ConvoKitUnreadBadge);
    expect(badge, findsOneWidget);
    expect(tester.widget<ConvoKitUnreadBadge>(badge).unreadCount, 2);
    expect(find.text('2'), findsOneWidget);

    // The room the user marked unread (isUnread with a count of 0) gets the
    // package's numberless dot, announced as "Unread", never as "0 unread".
    final semantics = tester.ensureSemantics();
    final dot = find.byType(ConvoKitUnreadDot);
    expect(dot, findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text('Incident room'),
          matching: find.byType(ListTile),
        ),
        matching: dot,
      ),
      findsOneWidget,
    );
    expect(tester.getSemantics(dot).label, endsWith('Unread'));
    expect(find.text('0'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'0 unread')), findsNothing);
    expect(
      tester.widget<Text>(find.text('Incident room')).style?.fontWeight,
      FontWeight.w700,
    );
    expect(
      tester.widget<Text>(find.text('Design review')).style?.fontWeight,
      FontWeight.w600,
    );
    semantics.dispose();

    // The newest page is a window over a longer room, so the oldest rows are
    // reachable by scrolling rather than already rendered.
    expect(find.text('launch-handoff.pdf'), findsNothing);
    await dragHistory(tester, ShowcaseVariant.standard, 'launch-handoff.pdf');
    expect(find.text('launch-handoff.pdf'), findsOneWidget);

    await tester.tap(find.text('Customer operations'));
    await tester.pump();

    expect(find.text('Customer operations'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'standard view edits and deletes own messages through the package rows '
    'and composer',
    (tester) async {
      await pumpShowcase(tester, ShowcaseVariant.standard);
      const original = 'I linked this conversation to the support case.';
      const updated = 'I linked this conversation to the support case (v2).';
      const earlier = 'Filing this with the release record.';
      final field = find.byType(TextField);
      expect(field, findsOneWidget);

      // A long press on an own confirmed row opens the package's sheet.
      await pressAndSettle(tester, find.text(original), long: true);
      expect(find.text('Edit message'), findsOneWidget);
      expect(find.text('Delete message'), findsOneWidget);
      await pressAndSettle(tester, find.text('Edit message'));

      // `onEditMessage` set the host's editingMessage; the default composer
      // shows its banner, prefills the field and offers Save.
      expect(find.text('Editing message'), findsOneWidget);
      expect(find.byTooltip('Cancel editing'), findsOneWidget);
      expect(find.byTooltip('Save message'), findsOneWidget);
      expect(find.byTooltip('Send message'), findsNothing);
      expect(tester.widget<TextField>(field).controller?.text, original);

      await tester.enterText(field, updated);
      await pressAndSettle(tester, find.byTooltip('Save message'));
      await showNewest(tester, ShowcaseVariant.standard);

      // `onSaveEdit` bumped the fixture's revision: the row shows the new
      // text with the "Edited" caption and the composer left edit mode. The
      // edited row quotes another message and `Message.copyWith` kept that
      // reference, so its quoted block is still there.
      expect(find.text(updated), findsOneWidget);
      expect(find.text(original), findsNothing);
      expect(find.text('Edited'), findsNWidgets(2));
      expect(find.text('Maya Chen'), findsOneWidget);
      expect(find.text('Editing message'), findsNothing);
      expect(find.byTooltip('Send message'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller?.text, isEmpty);

      // Delete goes through the package's confirmation; Cancel keeps the row.
      // The row is quoted by the newest one, so its text is on screen twice
      // and the row itself is the later of the two.
      await pressAndSettle(tester, find.text(earlier).last, long: true);
      await pressAndSettle(tester, find.text('Delete message'));
      expect(find.text('Delete this message?'), findsOneWidget);
      await pressAndSettle(tester, find.byTooltip('Cancel delete'));
      expect(find.text('Delete this message?'), findsNothing);
      expect(find.text(earlier), findsWidgets);

      await pressAndSettle(tester, find.text(earlier).last, long: true);
      await pressAndSettle(tester, find.text('Delete message'));
      await pressAndSettle(tester, find.byTooltip('Confirm delete'));
      await showNewest(tester, ShowcaseVariant.standard);

      // `onDeleteMessage` removed the fixture row; only the freshly edited
      // row still carries the caption.
      expect(find.text(earlier), findsNothing);
      expect(find.text('Edited'), findsOneWidget);
      expect(find.text(updated), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('standard view quotes rows, jumps to a quoted row and keeps the '
      'reference when the quoted row is deleted', (tester) async {
    await pumpShowcase(tester, ShowcaseVariant.standard);
    const quotedRow = 'Filing this with the release record.';
    const foreignRow = 'Still waiting on an answer to this one.';
    final field = find.byType(TextField);
    ConvoKitConversationView chatView() =>
        tester.widget<ConvoKitConversationView>(
          find.byKey(const ValueKey('chat-view-standard')),
        );

    // A reply renders its quoted block above its own text: the author and
    // the quoted text come from the preview the host resolved. A reference
    // the previews answered nothing for is the terminal "the original is
    // gone" state, not an unresolved one.
    expect(find.text('Maya Chen'), findsOneWidget);
    expect(find.text(quotedRow), findsNWidgets(2));
    expect(find.text('Original message unavailable'), findsOneWidget);

    // Activating a quoted block whose message is loaded scrolls to it and
    // flashes it; the package reports the flash back and the host clears
    // it. The props are read off the view rather than guessed from pixels,
    // so both halves of the round trip are pinned.
    expect(chatView().highlightedMessageId, isNull);
    await tester.ensureVisible(find.text('Maya Chen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maya Chen'));
    await tester.pump();
    expect(chatView().highlightedMessageId, 'message-5');
    await tester.pumpAndSettle();
    await settleHighlight(tester);
    expect(chatView().highlightedMessageId, isNull);
    expect(find.text(quotedRow), findsWidgets);
    await showNewest(tester, ShowcaseVariant.standard);

    // A quoted message that is gone answers the jump the same way the
    // backend does, with a coded "not found" rather than a broken window.
    await pressAndSettle(tester, find.text('Original message unavailable'));
    expect(find.text('That message is no longer available'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await showNewest(tester, ShowcaseVariant.standard);

    // Any member may quote any row, so a row of another member offers
    // "Reply" without the author-only actions.
    await pressAndSettle(tester, find.text(foreignRow), long: true);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Edit message'), findsNothing);
    expect(find.text('Delete message'), findsNothing);
    await pressAndSettle(tester, find.text('Reply'));
    expect(find.text('Replying to Jordan Lee'), findsOneWidget);
    expect(find.byTooltip('Cancel reply'), findsOneWidget);

    await tester.enterText(field, 'Adding the case number here.');
    await pressAndSettle(tester, find.byTooltip('Send message'));
    await showNewest(tester, ShowcaseVariant.standard);

    // Sending cleared the strip and stored the reference, so the new row
    // quotes the one it answered.
    expect(find.text('Replying to Jordan Lee'), findsNothing);
    expect(find.text('Adding the case number here.'), findsOneWidget);
    expect(find.text(foreignRow), findsNWidgets(2));

    // Deleting a quoted message never rewrites the replies pointing at it:
    // the reference stays and the block degrades.
    await pressAndSettle(tester, find.text(quotedRow).last, long: true);
    await pressAndSettle(tester, find.text('Delete message'));
    await pressAndSettle(tester, find.byTooltip('Confirm delete'));
    await showNewest(tester, ShowcaseVariant.standard);

    expect(find.text(quotedRow), findsNothing);
    expect(find.text('Original message unavailable'), findsNWidgets(2));
    expect(
      find.text('I linked this conversation to the support case.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('branded view applies every targeted builder and sends text', (
    tester,
  ) async {
    await pumpShowcase(tester, ShowcaseVariant.branded);

    // The first room is the only one with unread messages; its custom row
    // reads the count and the preview from the summary.
    final badge = find.byKey(const ValueKey('support-unread-badge'));
    expect(badge, findsOneWidget);
    expect(tester.widget<ConvoKitUnreadBadge>(badge).unreadCount, 2);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('support-row-launch-room')),
        matching: badge,
      ),
      findsOneWidget,
    );
    // The marked room (isUnread, count 0) composes the package's dot instead.
    final dot = find.byKey(const ValueKey('support-unread-dot'));
    expect(dot, findsOneWidget);
    expect(tester.widget(dot), isA<ConvoKitUnreadDot>());
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('support-row-incident-room')),
        matching: dot,
      ),
      findsOneWidget,
    );
    expect(find.byType(ConvoKitUnreadBadge), findsOneWidget);
    expect(
      find.text('You: I linked this conversation to the support case.'),
      findsOneWidget,
    );
    expect(find.text('Jordan Lee: Photo'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-read-receipt')), findsWidgets);
    expect(find.text('Read by Alex Rivera'), findsWidgets);
    // `mediaBlockBuilder` replaces the ticket attachment's block. This
    // configuration runs oldest-first over a window, so the row carrying it
    // is below the fold until the history is scrolled, exactly like the
    // standard configuration's attachment row.
    expect(find.byKey(const ValueKey('support-ticket')), findsNothing);
    await dragHistory(
      tester,
      ShowcaseVariant.branded,
      'Ticket CK-4821',
      step: -120,
    );
    expect(find.byKey(const ValueKey('support-ticket')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-composer')), findsOneWidget);
    expect(find.text('Priority support · SLA 18 min'), findsOneWidget);
    expect(find.text('Alex Rivera is typing…'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Reply to customer…'),
      'Customer reply sent',
    );
    final sendButton = find.widgetWithText(FilledButton, 'Send');
    await tester.ensureVisible(sendButton);
    await tester.pump();
    await tester.tap(sendButton);
    await tester.pump();

    expect(
      tester
          .widget<TextField>(
            find.widgetWithText(TextField, 'Reply to customer…'),
          )
          .controller
          ?.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'branded composer shows its own banners while a package row is edited or '
    'quoted',
    (tester) async {
      await pumpShowcase(tester, ShowcaseVariant.branded);
      const original =
          'Great. I approved the copy and shared the release notes.';
      const updated = 'Approved the copy and shared the release notes.';
      final field = find.widgetWithText(TextField, 'Reply to customer…');
      final banner = find.byKey(const ValueKey('support-edit-banner'));
      await tester.ensureVisible(field);
      await tester.enterText(field, 'unsent draft');

      // Default rows are still the package's: the own row opens the sheet.
      await pressAndSettle(tester, find.text(original), long: true);
      await pressAndSettle(tester, find.text('Edit message'));

      // The custom composer received the host's edit state through the
      // page's adapter and renders its banner; the package prefilled the
      // field after stashing the unsent draft.
      expect(banner, findsOneWidget);
      expect(find.textContaining('Editing your reply'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Send'), findsNothing);
      expect(tester.widget<TextField>(field).controller?.text, original);

      // The banner's Cancel clears the host state; the package restores the
      // stashed draft.
      await pressAndSettle(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(banner, findsNothing);
      expect(find.widgetWithText(FilledButton, 'Send'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller?.text, 'unsent draft');

      // Saving goes through the same `send` the composer already uses.
      await pressAndSettle(tester, find.text(original), long: true);
      await pressAndSettle(tester, find.text('Edit message'));
      await tester.enterText(field, updated);
      await pressAndSettle(tester, find.widgetWithText(FilledButton, 'Save'));

      expect(find.text(updated), findsOneWidget);
      expect(find.text(original), findsNothing);
      expect(find.text('Edited'), findsOneWidget);
      expect(banner, findsNothing);
      expect(tester.widget<TextField>(field).controller?.text, 'unsent draft');

      // The same adapter hands it the reply target, which is mutually
      // exclusive with edit mode.
      final replyBanner = find.byKey(const ValueKey('support-reply-banner'));
      await pressAndSettle(tester, find.text(updated), long: true);
      await pressAndSettle(tester, find.text('Reply'));
      expect(replyBanner, findsOneWidget);
      expect(find.textContaining('Quoting Maya Chen'), findsOneWidget);
      expect(banner, findsNothing);

      await pressAndSettle(
        tester,
        find.widgetWithText(TextButton, 'Cancel quote'),
      );
      expect(replyBanner, findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'branded view jumps to a quoted message outside the loaded window and '
    'back to the newest page',
    (tester) async {
      await pumpShowcase(tester, ShowcaseVariant.branded);
      const quoted =
          'Kickoff notes from the launch sync are in the shared drive.';
      const reply = 'Pulling the kickoff notes back up so nothing is lost.';

      // The quoted message is older than the loaded window, so only the
      // reply and its quoted block are rendered.
      expect(find.text(reply), findsOneWidget);
      expect(find.text(quoted), findsOneWidget);
      expect(find.text('Jump to latest'), findsNothing);

      // Activating the block loads the window around the quoted message and
      // replaces the rendered one with it.
      await pressAndSettle(tester, find.text(quoted));
      await settleHighlight(tester);

      expect(find.text(quoted), findsOneWidget);
      expect(find.text(reply), findsNothing);
      expect(
        find.text('Thanks — I will fold them into the checklist.'),
        findsOneWidget,
      );
      expect(find.text('Jump to latest'), findsOneWidget);

      // The way back is always offered while the window is not the live tail.
      await pressAndSettle(tester, find.text('Jump to latest'));
      expect(find.text(reply), findsOneWidget);
      expect(find.text('Jump to latest'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact view replaces rows, messages, typing and composer', (
    tester,
  ) async {
    await pumpShowcase(tester, ShowcaseVariant.compact);

    expect(
      find.byKey(const ValueKey('compact-row-launch-room')),
      findsOneWidget,
    );
    // The dense rows show one dot for the room with unread messages and one
    // for the room the user marked unread; every row shows its time.
    final dot = find.byKey(const ValueKey('compact-unread-dot'));
    expect(dot, findsNWidgets(2));
    for (final id in <String>['launch-room', 'incident-room']) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('compact-row-$id')),
          matching: dot,
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('compact-row-design-review')),
        matching: dot,
      ),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('compact-header')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compact-message-message-1')),
      findsOneWidget,
    );
    // Custom rows read `Message.isEdited`: only the revision-1 fixture row
    // shows the caption.
    expect(find.text('Edited'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('compact-message-message-5')),
        matching: find.text('Edited'),
      ),
      findsOneWidget,
    );
    // The frozen six-parameter `ConvoKitMessageItemBuilder` is unchanged in
    // 0.9.0 and renders exactly as it did: it receives no reply members, so
    // these rows carry no quoted block and offer no "Reply" action. A row
    // that needs them uses `messageContextBuilder` instead.
    expect(find.text('Original message unavailable'), findsNothing);
    expect(find.text('Reply'), findsNothing);
    expect(find.byKey(const ValueKey('compact-typing')), findsOneWidget);
    expect(find.byKey(const ValueKey('compact-composer')), findsOneWidget);
    expect(find.text('Jordan Lee is responding…'), findsOneWidget);
    expect(find.byTooltip('Back to queue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'quoted view builds rows from the scope and reaches the package composer',
    (tester) async {
      await pumpShowcase(tester, ShowcaseVariant.quoted);

      // Every row is the page's own widget, built from
      // `ConvoKitMessageItemScope` through `messageContextBuilder`.
      expect(
        find.byKey(const ValueKey('quoted-message-message-7')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('quoted-quote-message-7')),
        findsOneWidget,
      );
      expect(
        find.text('Maya Chen: Filing this with the release record.'),
        findsOneWidget,
      );
      expect(find.text('Original message unavailable'), findsOneWidget);
      // The scope still carries every frozen-builder argument, so the row
      // renders the sender, the attachment count, the edited caption and the
      // reader count itself.
      expect(find.text('1 attachment'), findsOneWidget);
      expect(find.text(' · Edited'), findsOneWidget);
      expect(find.text('Jordan Lee'), findsOneWidget);
      // `chronologicalIndex` and `sender` are values only the scope supplies:
      // the row's place in the loaded window is nowhere in the fixture, and
      // the author comes off `scope.sender`, not off the page's own lookup.
      final semantics = tester.ensureSemantics();
      await tester.pump();
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('quoted-message-message-7')),
            )
            .label,
        startsWith('Row 7 from Maya Chen'),
      );
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('quoted-message-message-6')),
            )
            .label,
        startsWith('Row 6 from Jordan Lee'),
      );
      semantics.dispose();

      // `scope.reply` is non-null exactly when `scope.canReply`, and the
      // package's default composer shows the strip for whatever the host set.
      await pressAndSettle(
        tester,
        find.byKey(const ValueKey('quoted-reply-message-6')),
      );
      expect(find.text('Replying to Jordan Lee'), findsOneWidget);
      await pressAndSettle(tester, find.byTooltip('Cancel reply'));
      expect(find.text('Replying to Jordan Lee'), findsNothing);
      await showNewest(tester, ShowcaseVariant.quoted);

      // `scope.jumpToReplyTarget` is the same host callback the package's
      // own rows use, so it drives the same highlight round trip.
      final quotedView = find.byKey(const ValueKey('chat-view-quoted'));
      await tester.ensureVisible(
        find.text('Maya Chen: Filing this with the release record.'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Maya Chen: Filing this with the release record.'),
      );
      await tester.pump();
      expect(
        tester
            .widget<ConvoKitConversationView>(quotedView)
            .highlightedMessageId,
        'message-5',
      );
      await tester.pumpAndSettle();
      await settleHighlight(tester);
      expect(
        tester
            .widget<ConvoKitConversationView>(quotedView)
            .highlightedMessageId,
        isNull,
      );
      expect(find.text('Filing this with the release record.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'standard view mints a fresh id for every send, including after a delete',
    (tester) async {
      await pumpShowcase(tester, ShowcaseVariant.standard);
      const ownRow = 'I linked this conversation to the support case.';
      final field = find.byType(TextField);

      await tester.enterText(field, 'first local send');
      await pressAndSettle(tester, find.byTooltip('Send message'));

      // Deleting shortens the history, so a send id derived from its length
      // would repeat the previous one. The package keys every rendered row by
      // its message id, so a repeat throws on the next build.
      await pressAndSettle(tester, find.text(ownRow), long: true);
      await pressAndSettle(tester, find.text('Delete message'));
      await pressAndSettle(tester, find.byTooltip('Confirm delete'));

      await tester.enterText(field, 'second local send');
      await pressAndSettle(tester, find.byTooltip('Send message'));
      await showNewest(tester, ShowcaseVariant.standard);

      expect(tester.takeException(), isNull);
      expect(find.text('first local send'), findsOneWidget);
      expect(find.text('second local send'), findsOneWidget);
    },
  );

  testWidgets('standard view keeps edit mode and reply mode mutually '
      'exclusive in both directions', (tester) async {
    await pumpShowcase(tester, ShowcaseVariant.standard);
    const foreignRow = 'Still waiting on an answer to this one.';
    const ownRow = 'I linked this conversation to the support case.';

    // Reply first: the package's strip is up for the host's reply target.
    await pressAndSettle(tester, find.text(foreignRow), long: true);
    await pressAndSettle(tester, find.text('Reply'));
    expect(find.text('Replying to Jordan Lee'), findsOneWidget);
    expect(find.text('Editing message'), findsNothing);
    await showNewest(tester, ShowcaseVariant.standard);

    // Entering edit mode clears the reply target, so the two banners are
    // never on screen together.
    await pressAndSettle(tester, find.text(ownRow), long: true);
    await pressAndSettle(tester, find.text('Edit message'));
    expect(find.text('Editing message'), findsOneWidget);
    expect(find.text('Replying to Jordan Lee'), findsNothing);
    await showNewest(tester, ShowcaseVariant.standard);

    // And the other direction: replying while an edit is open cancels it.
    await pressAndSettle(tester, find.text(foreignRow), long: true);
    await pressAndSettle(tester, find.text('Reply'));
    expect(find.text('Replying to Jordan Lee'), findsOneWidget);
    expect(find.text('Editing message'), findsNothing);
    expect(find.byTooltip('Send message'), findsOneWidget);
    expect(find.byTooltip('Save message'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'standard view pages older messages in at the older edge of the window',
    (tester) async {
      await pumpShowcase(tester, ShowcaseVariant.standard);
      const beyondWindow =
          'Status call moved to 15:00 so the whole team can join.';
      const oldest =
          'Kickoff notes from the launch sync are in the shared drive.';

      // The newest page is seven of the room's sixteen rows, so these two
      // are not merely unbuilt — they are outside the loaded window.
      expect(find.text(beyondWindow), findsNothing);
      expect(find.text(oldest), findsNothing);

      // Reaching the older edge calls `onLoadOlder`, which extends the window
      // backwards one page at a time. Nothing else can bring these rows in.
      await dragHistory(tester, ShowcaseVariant.standard, beyondWindow);
      expect(find.text(beyondWindow), findsOneWidget);
      await dragHistory(tester, ShowcaseVariant.standard, oldest);
      expect(find.text(oldest), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'branded view pages the newer edge of a jumped window back to the live '
    'tail without the explicit control',
    (tester) async {
      await pumpShowcase(tester, ShowcaseVariant.branded);
      const quoted =
          'Kickoff notes from the launch sync are in the shared drive.';
      const reply = 'Pulling the kickoff notes back up so nothing is lost.';
      const beyondWindow = 'Support macros for the new plan are written.';
      final history = find.descendant(
        of: find.byKey(const ValueKey('chat-view-branded')),
        matching: find.byType(ListView),
      );

      // Jump to a message older than the loaded window: the rendered window
      // becomes a bounded one centred on it.
      await pressAndSettle(tester, find.text(quoted));
      await settleHighlight(tester);
      expect(find.text('Jump to latest'), findsOneWidget);
      expect(find.text(beyondWindow), findsNothing);

      // Scrolling toward the newer edge calls `onLoadNewer`, which extends
      // the window forwards.
      for (var i = 0; i < 4 && find.text(beyondWindow).evaluate().isEmpty; i++) {
        await tester.drag(history, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(find.text(beyondWindow), findsOneWidget);

      // Keeping at it reaches the room's newest message, which rejoins the
      // live tail rather than flipping the window's mode in place. "Jump to
      // latest" is never tapped here.
      for (var i = 0; i < 12; i++) {
        if (find.text('Jump to latest').evaluate().isEmpty) break;
        await tester.drag(history, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(find.text('Jump to latest'), findsNothing);

      // The live tail is the newest page again, with the reply in it.
      await dragHistory(tester, ShowcaseVariant.branded, reply);
      expect(find.text(reply), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'quoted view renders the unresolved preview state before the batched '
    'previews land',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 820);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const ComponentShowcaseApp(initialVariant: ShowcaseVariant.quoted),
      );

      // First frame: the rows carry their reference with no quoted text. An
      // id the batched request has not answered for is absent from the map,
      // which is neither a resolved preview nor a claim that the original is
      // gone.
      expect(find.text('Quoted message'), findsWidgets);
      expect(find.text('Original message unavailable'), findsNothing);
      expect(
        find.text('Maya Chen: Filing this with the release record.'),
        findsNothing,
      );

      // The request answers, and the same rows settle into the other two
      // states.
      await tester.pumpAndSettle();
      expect(find.text('Quoted message'), findsNothing);
      expect(find.text('Original message unavailable'), findsOneWidget);
      expect(
        find.text('Maya Chen: Filing this with the release record.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('variant selector swaps the live component configuration', (
    tester,
  ) async {
    await pumpShowcase(tester, ShowcaseVariant.standard);

    await tester.tap(find.text('Branded'));
    await tester.pumpAndSettle();

    expect(find.text('2 · Branded customer support'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-header')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-list-branded')),
      findsOneWidget,
    );

    await tester.tap(find.text('Quoted'));
    await tester.pumpAndSettle();

    expect(find.text('4 · Quoted rows'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('quoted-message-message-7')),
      findsOneWidget,
    );
  });

  for (final width in <double>[320, 390, 768, 1440]) {
    for (final variant in ShowcaseVariant.values) {
      testWidgets('${variant.name} remains usable at width $width', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        await tester.pumpWidget(ComponentShowcaseApp(initialVariant: variant));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final title = tester.getRect(find.text('ConvoKit UI components'));
        expect(title.height, lessThan(70));
        expect(title.left, greaterThanOrEqualTo(0));
        expect(title.right, lessThanOrEqualTo(width));
        final selector = find.byKey(const ValueKey('variant-selector'));
        final selectorRect = tester.getRect(selector);
        expect(selectorRect.left, greaterThanOrEqualTo(0));
        expect(selectorRect.right, lessThanOrEqualTo(width));
        expect(selectorRect.bottom, lessThan(220));

        if (width < 900) {
          await tester.tap(selector);
          await tester.pumpAndSettle();
          final next =
              ShowcaseVariant.values[(variant.index + 1) %
                  ShowcaseVariant.values.length];
          await tester.tap(find.text(next.label).last);
          await tester.pumpAndSettle();
          expect(
            find.byKey(ValueKey('conversation-list-${next.name}')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        }

        final chat = find.text('CHAT VIEW');
        await tester.ensureVisible(chat);
        await tester.pumpAndSettle();
        expect(tester.getRect(chat).top, lessThan(844));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
