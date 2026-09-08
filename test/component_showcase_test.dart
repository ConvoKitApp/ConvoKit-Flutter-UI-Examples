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

    await tester.tap(find.text('Customer operations'));
    await tester.pump();

    expect(find.text('Customer operations'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('branded view applies every targeted builder and sends text', (
    tester,
  ) async {
    await pumpShowcase(tester, ShowcaseVariant.branded);

    expect(find.byKey(const ValueKey('support-unread-badge')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-ticket')), findsOneWidget);
    expect(find.byKey(const ValueKey('support-read-receipt')), findsWidgets);
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

  testWidgets('compact view replaces rows, messages, typing and composer', (
    tester,
  ) async {
    await pumpShowcase(tester, ShowcaseVariant.compact);

    expect(
      find.byKey(const ValueKey('compact-row-launch-room')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('compact-header')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compact-message-message-1')),
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
