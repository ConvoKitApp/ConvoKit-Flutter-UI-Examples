import 'dart:async';

import 'package:convokit_flutter/convokit_flutter.dart';
import 'package:convokit_flutter_ui/convokit_flutter_ui.dart';
import 'package:flutter/material.dart';

/// Three configurations of the same public ConvoKit UI components.
enum ShowcaseVariant {
  /// Package defaults with no visual builder overrides.
  standard,

  /// Branded support UI assembled with theme and builder parameters.
  branded,

  /// Dense operational UI assembled with full-row builder parameters.
  compact;

  /// Resolves a URL-friendly variant name, defaulting to [standard].
  static ShowcaseVariant fromName(String? value) => switch (value) {
    'branded' => branded,
    'compact' => compact,
    _ => standard,
  };

  /// Human-readable selector label.
  String get label => switch (this) {
    standard => 'Standard',
    branded => 'Branded support',
    compact => 'Compact operations',
  };
}

/// Interactive, backend-free gallery for the UI package's public widgets.
class ComponentShowcaseApp extends StatefulWidget {
  /// Creates the gallery at a chosen initial configuration.
  const ComponentShowcaseApp({
    this.initialVariant = ShowcaseVariant.standard,
    super.key,
  });

  /// Configuration selected when the gallery first renders.
  final ShowcaseVariant initialVariant;

  @override
  State<ComponentShowcaseApp> createState() => _ComponentShowcaseAppState();
}

class _ComponentShowcaseAppState extends State<ComponentShowcaseApp> {
  late ShowcaseVariant _variant = widget.initialVariant;

  @override
  Widget build(BuildContext context) {
    final spec = _specFor(_variant);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ConvoKit UI component showcase',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: spec.primary,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF3F5F4),
        extensions: <ThemeExtension<dynamic>>[spec.theme],
      ),
      home: _ShowcasePage(
        variant: _variant,
        spec: spec,
        onVariantChanged: (value) => setState(() => _variant = value),
      ),
    );
  }
}

class _ShowcasePage extends StatefulWidget {
  const _ShowcasePage({
    required this.variant,
    required this.spec,
    required this.onVariantChanged,
  });

  final ShowcaseVariant variant;
  final _VariantSpec spec;
  final ValueChanged<ShowcaseVariant> onVariantChanged;

  @override
  State<_ShowcasePage> createState() => _ShowcasePageState();
}

class _ShowcasePageState extends State<_ShowcasePage> {
  late Conversation _selectedConversation = _showcaseConversations.first;
  late List<Message> _messages = List<Message>.of(_showcaseMessages);

  @override
  void didUpdateWidget(covariant _ShowcasePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variant != widget.variant) {
      _selectedConversation = _showcaseConversations.first;
      _messages = List<Message>.of(_showcaseMessages);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spec = widget.spec;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _ShowcaseTopBar(
              variant: widget.variant,
              onVariantChanged: widget.onVariantChanged,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final horizontal = constraints.maxWidth >= 900;
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1320),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _VariantSummary(spec: spec),
                            const SizedBox(height: 16),
                            if (horizontal)
                              SizedBox(
                                height: 650,
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: spec.listWidth,
                                      child: _ComponentFrame(
                                        label: 'Conversation list',
                                        child: _buildConversationList(spec),
                                      ),
                                    ),
                                    const SizedBox(width: 18),
                                    Expanded(
                                      child: _ComponentFrame(
                                        label: 'Chat view',
                                        child: _buildConversation(spec),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              SizedBox(
                                height: 440,
                                child: _ComponentFrame(
                                  label: 'Conversation list',
                                  child: _buildConversationList(spec),
                                ),
                              ),
                              const SizedBox(height: 18),
                              SizedBox(
                                height: 650,
                                child: _ComponentFrame(
                                  label: 'Chat view',
                                  child: _buildConversation(spec),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationList(_VariantSpec spec) {
    return ConvoKitConversationListView(
      key: ValueKey('conversation-list-${widget.variant.name}'),
      conversations: _showcaseConversations,
      onConversationSelected: (conversation) {
        setState(() => _selectedConversation = conversation);
      },
      onRefresh: () async {},
      padding: spec.listPadding,
      itemBuilder: spec.listItemBuilder,
      separatorBuilder: (_, __) => SizedBox(height: spec.listSpacing),
      scrollThreshold: 120,
    );
  }

  Widget _buildConversation(_VariantSpec spec) {
    return ConvoKitConversationView(
      key: ValueKey('chat-view-${widget.variant.name}'),
      conversation: _selectedConversation,
      messages: _messages,
      currentUserId: _currentUserId,
      onSendMessage: (text) {
        setState(() {
          _messages = <Message>[
            ..._messages,
            Message(
              id: 'local-${_messages.length}',
              conversationId: _selectedConversation.id,
              senderId: _currentUserId,
              text: text,
              createdAt: DateTime.now().toUtc(),
            ),
          ];
        });
        return true;
      },
      onBack: spec.showBack ? () => _showNotice('Back callback') : null,
      onRefresh: spec.showRefresh ? () {} : null,
      onAddAttachment: () => _showNotice('Attachment callback'),
      onAttachmentTap: (context, message, attachment) {
        _showNotice('Opened ${attachment['name'] ?? 'attachment'}');
      },
      typingUserIds: spec.typingUserIds,
      readAtByUserId: <String, DateTime>{
        'alex': _showcaseNow.add(const Duration(minutes: 2)),
      },
      reverseMessages: spec.reverseMessages,
      headerBuilder: spec.headerBuilder,
      messageBuilder: spec.messageBuilder,
      mediaBlockBuilder: spec.mediaBlockBuilder,
      readReceiptBuilder: spec.readReceiptBuilder,
      composerBuilder: spec.composerBuilder,
      typingIndicatorBuilder: spec.typingIndicatorBuilder,
      displayNameForUser:
          (id) => switch (id) {
            'alex' => 'Alex Rivera',
            'jordan' => 'Jordan Lee',
            _ => id,
          },
    );
  }

  void _showNotice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _ShowcaseTopBar extends StatelessWidget {
  const _ShowcaseTopBar({
    required this.variant,
    required this.onVariantChanged,
  });

  final ShowcaseVariant variant;
  final ValueChanged<ShowcaseVariant> onVariantChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.forum_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ConvoKit UI components',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Same SDK widgets, different props and builders',
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7471)),
                  ),
                ],
              ),
            ),
            SegmentedButton<ShowcaseVariant>(
              key: const ValueKey('variant-selector'),
              segments: <ButtonSegment<ShowcaseVariant>>[
                for (final value in ShowcaseVariant.values)
                  ButtonSegment<ShowcaseVariant>(
                    value: value,
                    label: Text(value.label),
                  ),
              ],
              selected: <ShowcaseVariant>{variant},
              onSelectionChanged: (values) => onVariantChanged(values.single),
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantSummary extends StatelessWidget {
  const _VariantSummary({required this.spec});

  final _VariantSpec spec;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spec.title,
                key: ValueKey('variant-title-${spec.variant.name}'),
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                spec.description,
                style: const TextStyle(color: Color(0xFF66706D)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Flexible(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final prop in spec.props)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(prop, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ComponentFrame extends StatelessWidget {
  const _ComponentFrame({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ConvoKitUiThemeData.of(context).backgroundColor,
        border: Border.all(color: const Color(0xFFD8DEDC)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 38,
            width: double.infinity,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            color: Colors.white,
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF78817E),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

typedef _ListItemBuilder =
    Widget Function(
      BuildContext context,
      Conversation conversation,
      int index,
      VoidCallback onTap,
    );

class _VariantSpec {
  const _VariantSpec({
    required this.variant,
    required this.title,
    required this.description,
    required this.props,
    required this.primary,
    required this.theme,
    this.listWidth = 340,
    this.listPadding = const EdgeInsets.all(12),
    this.listSpacing = 8,
    this.listItemBuilder,
    this.headerBuilder,
    this.messageBuilder,
    this.mediaBlockBuilder,
    this.readReceiptBuilder,
    this.composerBuilder,
    this.typingIndicatorBuilder,
    this.typingUserIds = const <String>{},
    this.reverseMessages = true,
    this.showBack = false,
    this.showRefresh = true,
  });

  final ShowcaseVariant variant;
  final String title;
  final String description;
  final List<String> props;
  final Color primary;
  final ConvoKitUiThemeData theme;
  final double listWidth;
  final EdgeInsetsGeometry listPadding;
  final double listSpacing;
  final _ListItemBuilder? listItemBuilder;
  final ConvoKitConversationHeaderBuilder? headerBuilder;
  final ConvoKitMessageItemBuilder? messageBuilder;
  final ConvoKitMediaBlockBuilder? mediaBlockBuilder;
  final ConvoKitReadReceiptBuilder? readReceiptBuilder;
  final ConvoKitComposerBuilder? composerBuilder;
  final ConvoKitTypingIndicatorBuilder? typingIndicatorBuilder;
  final Set<String> typingUserIds;
  final bool reverseMessages;
  final bool showBack;
  final bool showRefresh;
}

_VariantSpec _specFor(ShowcaseVariant variant) => switch (variant) {
  ShowcaseVariant.standard => const _VariantSpec(
    variant: ShowcaseVariant.standard,
    title: '1 · Standard components',
    description:
        'Default list rows, header, bubbles, receipts, attachments and composer.',
    props: <String>[
      'onRefresh',
      'onAddAttachment',
      'readAtByUserId',
      'reverseMessages: true',
    ],
    primary: Color(0xFF148F78),
    theme: ConvoKitUiThemeData.light(),
  ),
  ShowcaseVariant.branded => _VariantSpec(
    variant: ShowcaseVariant.branded,
    title: '2 · Branded customer support',
    description:
        'A purple support workspace with custom rows, header, ticket card, receipt and composer.',
    props: const <String>[
      'itemBuilder',
      'headerBuilder',
      'mediaBlockBuilder',
      'readReceiptBuilder',
      'composerBuilder',
    ],
    primary: const Color(0xFF6750A4),
    theme: const ConvoKitUiThemeData(
      backgroundColor: Color(0xFFF8F6FF),
      surfaceColor: Colors.white,
      primaryColor: Color(0xFF6750A4),
      textColor: Color(0xFF211B2C),
      mutedTextColor: Color(0xFF716A7C),
      borderColor: Color(0xFFE4DFF0),
      errorColor: Color(0xFFB3261E),
      incomingBubbleColor: Colors.white,
      outgoingBubbleColor: Color(0xFF6750A4),
      outgoingTextColor: Colors.white,
      cornerRadius: 18,
      avatarRadius: 21,
    ),
    listItemBuilder: _supportListItem,
    headerBuilder: _supportHeader,
    mediaBlockBuilder: _supportMedia,
    readReceiptBuilder: _supportReceipt,
    composerBuilder: _supportComposer,
    typingUserIds: const <String>{'alex'},
    reverseMessages: false,
    showRefresh: false,
  ),
  ShowcaseVariant.compact => _VariantSpec(
    variant: ShowcaseVariant.compact,
    title: '3 · Compact operations view',
    description:
        'Dense list rows and message rendering for dashboards with limited space.',
    props: const <String>[
      'padding',
      'separatorBuilder',
      'messageBuilder',
      'typingIndicatorBuilder',
      'reverseMessages: false',
    ],
    primary: const Color(0xFF315B52),
    theme: const ConvoKitUiThemeData(
      backgroundColor: Color(0xFFF4F6F5),
      surfaceColor: Colors.white,
      primaryColor: Color(0xFF315B52),
      textColor: Color(0xFF18211F),
      mutedTextColor: Color(0xFF6C7773),
      borderColor: Color(0xFFDDE3E1),
      errorColor: Color(0xFFBA1A1A),
      incomingBubbleColor: Color(0xFFEEF2F0),
      outgoingBubbleColor: Color(0xFF315B52),
      outgoingTextColor: Colors.white,
      cornerRadius: 10,
      avatarRadius: 17,
    ),
    listWidth: 300,
    listPadding: const EdgeInsets.all(8),
    listSpacing: 3,
    listItemBuilder: _compactListItem,
    headerBuilder: _compactHeader,
    messageBuilder: _compactMessage,
    composerBuilder: _compactComposer,
    typingIndicatorBuilder: _compactTyping,
    typingUserIds: const <String>{'jordan'},
    reverseMessages: false,
    showBack: true,
    showRefresh: false,
  ),
};

Widget _supportListItem(
  BuildContext context,
  Conversation conversation,
  int index,
  VoidCallback onTap,
) {
  final unread = index == 0 ? 2 : 0;
  return Material(
    key: ValueKey('support-row-${conversation.id}'),
    color: index == 0 ? const Color(0xFFF0EAFF) : Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF6750A4),
              foregroundColor: Colors.white,
              child: Text(conversation.displayTitle.characters.first),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    index == 0 ? 'Waiting for your reply' : 'Last reply today',
                    style: const TextStyle(
                      color: Color(0xFF716A7C),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (unread > 0)
              Container(
                key: const ValueKey('support-unread-badge'),
                width: 23,
                height: 23,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0xFF6750A4),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Widget _supportHeader(
  BuildContext context,
  Conversation conversation,
  VoidCallback? onBack,
  FutureOr<void> Function()? onRefresh,
) {
  return Container(
    key: const ValueKey('support-header'),
    height: 72,
    padding: const EdgeInsets.symmetric(horizontal: 18),
    decoration: const BoxDecoration(
      color: Color(0xFF2E2440),
      border: Border(bottom: BorderSide(color: Color(0xFF4A3D61))),
    ),
    child: Row(
      children: [
        const CircleAvatar(
          backgroundColor: Color(0xFFEADDFF),
          child: Icon(Icons.support_agent_rounded, color: Color(0xFF6750A4)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                conversation.displayTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Text(
                'Priority support · SLA 18 min',
                key: ValueKey('support-sla'),
                style: TextStyle(color: Color(0xFFD8CFF0), fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Customer details',
          onPressed: () {},
          color: Colors.white,
          icon: const Icon(Icons.person_outline_rounded),
        ),
      ],
    ),
  );
}

Widget? _supportMedia(
  BuildContext context,
  Map<String, dynamic> block,
  Message message,
  bool isCurrentUser,
) {
  if (block['type'] != 'ticket') return null;
  return Container(
    key: const ValueKey('support-ticket'),
    width: 270,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF8F6FF),
      border: Border.all(color: const Color(0xFFD9D0EC)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Row(
      children: [
        Icon(Icons.confirmation_number_outlined, color: Color(0xFF6750A4)),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ticket CK-4821',
                style: TextStyle(
                  color: Color(0xFF211B2C),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'Payment verification',
                style: TextStyle(color: Color(0xFF514A5C), fontSize: 12),
              ),
            ],
          ),
        ),
        Chip(
          label: Text(
            'OPEN',
            style: TextStyle(color: Color(0xFF514A5C), fontSize: 9),
          ),
        ),
      ],
    ),
  );
}

Widget _supportReceipt(
  BuildContext context,
  Message message,
  Set<String> readerIds,
) {
  return const Padding(
    key: ValueKey('support-read-receipt'),
    padding: EdgeInsets.only(top: 4, right: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.done_all_rounded, size: 13, color: Color(0xFF6750A4)),
        SizedBox(width: 4),
        Text('Read by Alex Rivera', style: TextStyle(fontSize: 10)),
      ],
    ),
  );
}

Widget _supportComposer(
  BuildContext context,
  TextEditingController controller,
  bool isSending,
  VoidCallback send,
  VoidCallback? addAttachment,
) {
  return Container(
    key: const ValueKey('support-composer'),
    padding: const EdgeInsets.all(12),
    color: Colors.white,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Attach to ticket',
          onPressed: addAttachment,
          icon: const Icon(Icons.attach_file_rounded),
        ),
        Expanded(
          child: TextField(
            controller: controller,
            onSubmitted: (_) => send(),
            decoration: InputDecoration(
              hintText: 'Reply to customer…',
              filled: true,
              fillColor: const Color(0xFFF4F0FA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: isSending ? null : send,
          child: const Text('Send'),
        ),
      ],
    ),
  );
}

Widget _compactListItem(
  BuildContext context,
  Conversation conversation,
  int index,
  VoidCallback onTap,
) {
  return ListTile(
    key: ValueKey('compact-row-${conversation.id}'),
    dense: true,
    visualDensity: const VisualDensity(vertical: -3),
    contentPadding: const EdgeInsets.symmetric(horizontal: 9),
    onTap: onTap,
    leading: CircleAvatar(
      radius: 14,
      backgroundColor: const Color(0xFFDCE9E5),
      child: Text(
        conversation.displayTitle.characters.first,
        style: const TextStyle(fontSize: 11, color: Color(0xFF315B52)),
      ),
    ),
    title: Text(
      conversation.displayTitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
    trailing:
        index == 0
            ? const Icon(Icons.circle, size: 8, color: Color(0xFF2F8A72))
            : null,
  );
}

Widget _compactHeader(
  BuildContext context,
  Conversation conversation,
  VoidCallback? onBack,
  FutureOr<void> Function()? onRefresh,
) {
  return Container(
    key: const ValueKey('compact-header'),
    height: 52,
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: Color(0xFFDDE3E1))),
    ),
    child: Row(
      children: [
        if (onBack != null)
          IconButton(
            tooltip: 'Back to queue',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
        Expanded(
          child: Text(
            conversation.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
        const Chip(
          visualDensity: VisualDensity.compact,
          label: Text('LIVE', style: TextStyle(fontSize: 9)),
        ),
      ],
    ),
  );
}

Widget _compactMessage(
  BuildContext context,
  Message message,
  int chronologicalIndex,
  bool isCurrentUser,
  Participant? sender,
  Set<String> readerIds,
) {
  return Padding(
    key: ValueKey('compact-message-${message.id}'),
    padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Text(
            isCurrentUser
                ? 'YOU'
                : (sender?.name ?? message.senderId)
                    .split(' ')
                    .first
                    .toUpperCase(),
            style: TextStyle(
              color:
                  isCurrentUser
                      ? const Color(0xFF315B52)
                      : const Color(0xFF6C7773),
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            message.text ?? '[structured message]',
            style: const TextStyle(fontSize: 12, height: 1.3),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${message.createdAt.hour.toString().padLeft(2, '0')}:${message.createdAt.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 9, color: Color(0xFF7B8582)),
        ),
      ],
    ),
  );
}

Widget _compactComposer(
  BuildContext context,
  TextEditingController controller,
  bool isSending,
  VoidCallback send,
  VoidCallback? addAttachment,
) {
  return Container(
    key: const ValueKey('compact-composer'),
    height: 54,
    padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFDDE3E1))),
    ),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onSubmitted: (_) => send(),
            decoration: const InputDecoration(
              hintText: 'Message',
              isDense: true,
              border: InputBorder.none,
            ),
          ),
        ),
        IconButton.filled(
          tooltip: 'Send compact message',
          onPressed: isSending ? null : send,
          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
        ),
      ],
    ),
  );
}

Widget _compactTyping(
  BuildContext context,
  Set<String> userIds,
  String Function(String userId) displayNameForUser,
) {
  if (userIds.isEmpty) return const SizedBox.shrink();
  return Container(
    key: const ValueKey('compact-typing'),
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(10, 5, 10, 5),
    color: const Color(0xFFE8EFEC),
    child: Text(
      '${displayNameForUser(userIds.first)} is responding…',
      style: const TextStyle(fontSize: 10, color: Color(0xFF315B52)),
    ),
  );
}

const _currentUserId = 'me';
final _showcaseNow = DateTime.utc(2026, 9, 3, 9, 30);

final _showcaseConversations = <Conversation>[
  Conversation(
    id: 'launch-room',
    title: 'Product launch',
    appId: 'showcase',
    displayTitle: 'Product launch',
    description: 'Launch planning and assets',
    participants: _showcaseParticipants,
    createdAt: _showcaseNow.subtract(const Duration(days: 4)),
    updatedAt: _showcaseNow,
  ),
  Conversation(
    id: 'customer-ops',
    title: 'Customer operations',
    appId: 'showcase',
    displayTitle: 'Customer operations',
    participants: _showcaseParticipants,
    createdAt: _showcaseNow.subtract(const Duration(days: 3)),
    updatedAt: _showcaseNow.subtract(const Duration(minutes: 18)),
  ),
  Conversation(
    id: 'design-review',
    title: 'Design review',
    appId: 'showcase',
    displayTitle: 'Design review',
    participants: _showcaseParticipants,
    createdAt: _showcaseNow.subtract(const Duration(days: 2)),
    updatedAt: _showcaseNow.subtract(const Duration(hours: 2)),
  ),
  Conversation(
    id: 'incident-room',
    title: 'Incident room',
    appId: 'showcase',
    displayTitle: 'Incident room',
    participants: _showcaseParticipants,
    createdAt: _showcaseNow.subtract(const Duration(days: 1)),
    updatedAt: _showcaseNow.subtract(const Duration(hours: 6)),
  ),
];

const _showcaseParticipants = <Participant>[
  Participant(id: 'me', appUserId: 'me', name: 'Maya Chen', role: 'member'),
  Participant(
    id: 'alex',
    appUserId: 'alex',
    name: 'Alex Rivera',
    role: 'member',
  ),
  Participant(
    id: 'jordan',
    appUserId: 'jordan',
    name: 'Jordan Lee',
    role: 'member',
  ),
];

final _showcaseMessages = <Message>[
  Message(
    id: 'message-1',
    conversationId: 'launch-room',
    senderId: 'alex',
    text: 'The final launch checklist is ready for review.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 16)),
  ),
  Message(
    id: 'message-2',
    conversationId: 'launch-room',
    senderId: _currentUserId,
    text: 'Great. I approved the copy and shared the release notes.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 11)),
  ),
  Message(
    id: 'message-3',
    conversationId: 'launch-room',
    senderId: 'jordan',
    text: 'Attaching the final handoff document.',
    media: const <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'file',
        'name': 'launch-handoff.pdf',
        'size': 245760,
      },
    ],
    createdAt: _showcaseNow.subtract(const Duration(minutes: 7)),
  ),
  Message(
    id: 'message-4',
    conversationId: 'launch-room',
    senderId: _currentUserId,
    text: 'I linked this conversation to the support case.',
    media: const <Map<String, dynamic>>[
      <String, dynamic>{'type': 'ticket', 'name': 'Ticket CK-4821'},
    ],
    createdAt: _showcaseNow.subtract(const Duration(minutes: 3)),
  ),
];
