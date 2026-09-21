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
    expect(find.text('launch-handoff.pdf'), findsOneWidget);
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
      const earlier =
          'Great. I approved the copy and shared the release notes.';
      final field = find.byType(TextField);
      expect(field, findsOneWidget);

      // Another member's row offers no actions: the package decides.
      await pressAndSettle(
        tester,
        find.text('The final launch checklist is ready for review.'),
        long: true,
      );
      expect(find.text('Edit message'), findsNothing);
      expect(find.text('Delete message'), findsNothing);

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

      // `onSaveEdit` bumped the fixture's revision: the row shows the new
      // text with the "Edited" caption and the composer left edit mode.
      expect(find.text(updated), findsOneWidget);
      expect(find.text(original), findsNothing);
      expect(find.text('Edited'), findsNWidgets(2));
      expect(find.text('Editing message'), findsNothing);
      expect(find.byTooltip('Send message'), findsOneWidget);
      expect(tester.widget<TextField>(field).controller?.text, isEmpty);

      // Delete goes through the package's confirmation; Cancel keeps the row.
      await pressAndSettle(tester, find.text(earlier), long: true);
      await pressAndSettle(tester, find.text('Delete message'));
      expect(find.text('Delete this message?'), findsOneWidget);
      await pressAndSettle(tester, find.byTooltip('Cancel delete'));
      expect(find.text('Delete this message?'), findsNothing);
      expect(find.text(earlier), findsOneWidget);

      await pressAndSettle(tester, find.text(earlier), long: true);
      await pressAndSettle(tester, find.text('Delete message'));
      await pressAndSettle(tester, find.byTooltip('Confirm delete'));

      // `onDeleteMessage` removed the fixture row; only the freshly edited
      // row still carries the caption.
      expect(find.text(earlier), findsNothing);
      expect(find.text('Edited'), findsOneWidget);
      expect(find.text(updated), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
    expect(find.byKey(const ValueKey('support-ticket')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-read-receipt')), findsWidgets);
    expect(find.text('Read by Alex Rivera'), findsWidgets);
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
    'branded composer shows its own banner while a package row is edited',
    (tester) async {
      await pumpShowcase(tester, ShowcaseVariant.branded);
      const original = 'I linked this conversation to the support case.';
      const updated = 'Linked to the support case.';
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
      expect(find.text('Edited'), findsNWidgets(2));
      expect(banner, findsNothing);
      expect(tester.widget<TextField>(field).controller?.text, 'unsent draft');
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
        of: find.byKey(const ValueKey('compact-message-message-2')),
        matching: find.text('Edited'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('compact-typing')), findsOneWidget);
    expect(find.byKey(const ValueKey('compact-composer')), findsOneWidget);
    expect(find.text('Jordan Lee is responding…'), findsOneWidget);
    expect(find.byTooltip('Back to queue'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('variant selector swaps the live component configuration', (
    tester,
  ) async {
    await pumpShowcase(tester, ShowcaseVariant.standard);

    await tester.tap(find.text('Branded support'));
    await tester.pumpAndSettle();

    expect(find.text('2 · Branded customer support'), findsOneWidget);
    expect(find.byKey(const ValueKey('support-header')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('conversation-list-branded')),
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
          final next = ShowcaseVariant.values[(variant.index + 1) % 3];
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
