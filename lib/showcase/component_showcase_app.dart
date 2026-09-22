import 'dart:async';

import 'package:convokit_flutter/convokit_flutter.dart';
import 'package:convokit_flutter_ui/convokit_flutter_ui.dart';
import 'package:flutter/material.dart';

/// Four configurations of the same public ConvoKit UI components.
enum ShowcaseVariant {
  /// Package defaults with no visual builder overrides.
  standard,

  /// Branded support UI assembled with theme and builder parameters.
  branded,

  /// Dense operational UI assembled with full-row builder parameters.
  compact,

  /// Package defaults with one override: message rows built from a
  /// [ConvoKitMessageItemScope] through `messageContextBuilder`.
  quoted;

  /// Resolves a URL-friendly variant name, defaulting to [standard].
  static ShowcaseVariant fromName(String? value) => switch (value) {
    'branded' => branded,
    'compact' => compact,
    'quoted' => quoted,
    _ => standard,
  };

  /// Short selector label; the configuration's full name is its title.
  String get label => switch (this) {
    standard => 'Standard',
    branded => 'Branded',
    compact => 'Compact',
    quoted => 'Quoted',
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
  // Rows the newest page holds; the fixture room is longer than that, so the
  // oldest messages start outside the rendered window exactly as they do
  // against a backend.
  static const int _livePageSize = 7;
  // Rows a jump brings back around its target, standing in for one
  // `getMessageContext` window.
  static const int _contextPageSize = 5;
  // Rows one older or newer page adds.
  static const int _pageStep = 3;

  late Conversation _selectedConversation = _showcaseConversations.first;
  // The whole fixture room, oldest first. A controlled view never renders it
  // directly: it renders `_window`, the range the host has loaded, the way an
  // SDK-backed controller renders the page it fetched.
  late List<Message> _history = List<Message>.of(_showcaseMessages);
  int _windowStart = 0;
  int _windowEnd = 0;
  // Whether the rendered window is a jumped-to one rather than the live tail.
  // It stays set for the whole of a jumped window, so the package's "Jump to
  // latest" control and its newer-edge trigger never disappear.
  bool _jumped = false;
  // Edit mode is owned by the host of a controlled view: the snapshot the
  // user picked with "Edit message", or null. The view prefills its composer
  // from it and routes the composer's send action to `onSaveEdit` while it
  // is set.
  Message? _editingMessage;
  // Reply mode, owned the same way: the row the user picked "Reply" on. The
  // package's composer shows its cancellable "Replying to" strip while it is
  // set, and the next send quotes it.
  Message? _replyTarget;
  // The row a jump is drawing attention to. The package scrolls it into the
  // middle of the list and flashes it, then reports back through
  // `onHighlightHandled` so this clears.
  String? _highlightedMessageId;
  // Quoted ids one batched `getReplyPreviews` has already answered for. A
  // reference is rendered before its preview lands, so an id stays out of the
  // map handed to the view until it is in here.
  final Set<String> _resolvedPreviewIds = <String>{};
  // How many rows this page has sent. Ids are minted from this counter and
  // never from `_history.length`: deleting a row shrinks the history, so a
  // length-derived id repeats one that is already in the list, and the
  // package keys every rendered row by its message id.
  int _localSendCount = 0;

  @override
  void initState() {
    super.initState();
    _showLiveTail();
  }

  @override
  void didUpdateWidget(covariant _ShowcasePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.variant != widget.variant) {
      _selectedConversation = _showcaseConversations.first;
      _history = List<Message>.of(_showcaseMessages);
      _editingMessage = null;
      _replyTarget = null;
      _highlightedMessageId = null;
      _resolvedPreviewIds.clear();
      _showLiveTail();
    }
  }

  /// The rendered window: what a controlled view is handed as `messages`.
  List<Message> get _window => _history.sublist(_windowStart, _windowEnd);

  // The newest page, which is where a room opens and where a send belongs.
  void _showLiveTail() {
    _windowEnd = _history.length;
    _windowStart =
        _windowEnd - _livePageSize < 0 ? 0 : _windowEnd - _livePageSize;
    _jumped = false;
  }

  // One bounded window centred on [index], which is what
  // `getMessageContext(conversationId, messageId: ...)` answers.
  void _showWindowAround(int index) {
    var start = index - _contextPageSize ~/ 2;
    if (start < 0) start = 0;
    var end = start + _contextPageSize;
    if (end > _history.length) {
      end = _history.length;
      start = end - _contextPageSize < 0 ? 0 : end - _contextPageSize;
    }
    _windowStart = start;
    _windowEnd = end;
    _jumped = true;
  }

  // What one batched `getReplyPreviews` call answers for the rendered rows:
  // one preview per quoted id that still exists, and nothing at all for one
  // that was deleted. Absence from a resolved result is the only deletion
  // signal, and the package renders it as "Original message unavailable"
  // while keeping the reference and the jump affordance. A quoted message
  // outside the window resolves just as well, because the request is by id.
  //
  // All three states the package renders are reachable here, because the
  // request is answered a frame after the rows that need it are built: a
  // quoted id this page has not requested yet is simply absent from the map,
  // which is the "not resolved yet" state and must not claim the original is
  // gone. Resolved ids are re-read from `_history` on every build rather than
  // cached, so an edit shows the new text and revision and a deletion turns
  // the entry terminal.
  Map<String, ReplyPreview?> _replyPreviews() {
    final previews = <String, ReplyPreview?>{};
    final unresolved = <String>[];
    for (final message in _window) {
      final quoted = message.replyToMessageId;
      if (quoted == null || previews.containsKey(quoted)) continue;
      if (_resolvedPreviewIds.contains(quoted)) {
        previews[quoted] = _previewOf(quoted);
      } else {
        unresolved.add(quoted);
      }
    }
    if (unresolved.isNotEmpty) {
      // One request for the whole window, never one per row.
      scheduleMicrotask(() => _resolveReplyPreviews(unresolved));
    }
    return previews;
  }

  void _resolveReplyPreviews(List<String> ids) {
    if (!mounted) return;
    setState(() => _resolvedPreviewIds.addAll(ids));
  }

  ReplyPreview? _previewOf(String messageId) {
    for (final row in _history) {
      if (row.id != messageId) continue;
      return ReplyPreview(
        id: row.id,
        conversationId: row.conversationId,
        // The preview's author is `senderId`, the same value the message row
        // carries; the wire key it is decoded from is `appUserId`.
        senderId: row.senderId,
        text: row.text,
        createdAt: row.createdAt,
        revision: row.revision,
        mediaCount: row.media.length,
      );
    }
    return null;
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
      summaries: _showcaseSummaries,
      currentUserId: _currentUserId,
      onConversationSelected: (conversation) {
        setState(() => _selectedConversation = conversation);
      },
      onRefresh: () async {},
      padding: spec.listPadding,
      rowBuilder: spec.listRowBuilder,
      separatorBuilder: (_, __) => SizedBox(height: spec.listSpacing),
      scrollThreshold: 120,
    );
  }

  Widget _buildConversation(_VariantSpec spec) {
    return ConvoKitConversationView(
      key: ValueKey('chat-view-${widget.variant.name}'),
      conversation: _selectedConversation,
      messages: _window,
      currentUserId: _currentUserId,
      onSendMessage: _sendMessage,
      // The package decides which rows offer "Edit message" / "Delete
      // message" (the connected user's own confirmed rows, never a READ
      // role) and asks "Delete this message?" itself; these fixture callbacks
      // stand in for the SDK-backed controller and apply the result locally.
      editingMessage: _editingMessage,
      onEditMessage: _startEditing,
      onSaveEdit: _saveEdit,
      onCancelEdit: _cancelEditing,
      onDeleteMessage: _deleteMessage,
      // "Reply" appears on every confirmed row the caller's role allows, own
      // or not — any member may quote any row. The rest of the reply surface
      // is the same shape: host state in, callbacks out.
      replyTarget: _replyTarget,
      onReplyToMessage: _startReply,
      onCancelReply: _cancelReply,
      replyPreviewByMessageId: _replyPreviews(),
      // Jump, highlight and the window around it.
      onJumpToMessage: _jumpToMessage,
      highlightedMessageId: _highlightedMessageId,
      onHighlightHandled: _clearHighlight,
      hasOlderMessages: _windowStart > 0,
      onLoadOlder: _loadOlderMessages,
      hasNewerMessages: _jumped,
      onLoadNewer: _loadNewerMessages,
      onReturnToLatest: _returnToLatest,
      onBack: spec.showBack ? () => _showNotice('Back callback') : null,
      onRefresh: spec.showRefresh ? () {} : null,
      onAddAttachment: () => _showNotice('Attachment callback'),
      onAttachmentTap: (context, message, attachment) {
        _showNotice('Opened ${attachment['name'] ?? 'attachment'}');
      },
      typingUserIds: spec.typingUserIds,
      readPositionByUserId: <String, ReadPosition>{
        'alex': ReadPosition(
          messageId: _showcaseMessages.last.id,
          createdAt: _showcaseMessages.last.createdAt,
        ),
      },
      reverseMessages: spec.reverseMessages,
      headerBuilder: spec.headerBuilder,
      // The frozen positional row builder and the 0.9.0 scope builder are
      // separate parameters; a variant sets one of them. When a host sets
      // both, the package's scope builder wins.
      messageBuilder: spec.messageBuilder,
      messageContextBuilder: spec.messageContextBuilder,
      mediaBlockBuilder: spec.mediaBlockBuilder,
      readReceiptBuilder: spec.readReceiptBuilder,
      // The package's `ConvoKitComposerBuilder` is unchanged in 0.9.0: its
      // `send` saves while `editingMessage` is set and sends otherwise. The
      // custom composers only need the host's edit and reply state for their
      // own banners, so the page hands both to them alongside the package
      // arguments.
      composerBuilder:
          spec.composerBuilder == null
              ? null
              : (context, controller, isSending, send, addAttachment) =>
                  spec.composerBuilder!(
                    context,
                    controller,
                    isSending,
                    send,
                    addAttachment,
                    _editingMessage,
                    _cancelEditing,
                    _editingMessage == null ? _replyTarget : null,
                    _cancelReply,
                  ),
      typingIndicatorBuilder: spec.typingIndicatorBuilder,
      displayNameForUser: _showcaseUserName,
    );
  }

  // What the backend does on a successful `POST /api/v1/messages`: the row is
  // stored with the composer's reply target as `replyToMessageId`, so it
  // renders its quoted block straight away.
  FutureOr<bool> _sendMessage(String text) {
    setState(() {
      final replyTo = _replyTarget;
      _history = <Message>[
        ..._history,
        Message(
          id: 'local-${_localSendCount++}',
          conversationId: _selectedConversation.id,
          senderId: _currentUserId,
          text: text,
          createdAt: DateTime.now().toUtc(),
          revision: 0,
          replyToMessageId: replyTo?.id,
        ),
      ];
      // A send belongs to the live tail, so a jumped window rejoins it
      // first; the reply target survives that switch and the send clears it.
      _showLiveTail();
      _replyTarget = null;
    });
    return true;
  }

  // Editing and replying are mutually exclusive.
  void _startEditing(Message message) => setState(() {
    _editingMessage = message;
    _replyTarget = null;
  });

  // What the backend does on a successful `PATCH /api/v1/messages/:id/own`:
  // the trimmed text replaces the message text (empty clears the caption of
  // a message with attachments), the attachments stay and `revision` moves
  // by one, so the row renders the package's "Edited" caption.
  FutureOr<bool> _saveEdit(Message message, String text) {
    final trimmed = text.trim();
    setState(() {
      _history = <Message>[
        for (final row in _history)
          if (row.id == message.id)
            // `Message.copyWith`, never a rebuilt literal: a literal
            // silently drops whatever it forgets, and dropping
            // `replyToMessageId` would strip the quoted block and the jump
            // affordance off an edited reply. An edit never changes what a
            // message quotes — the reference is written once, when it is
            // sent.
            row.copyWith(
              text: trimmed.isEmpty ? null : trimmed,
              updatedAt: DateTime.now().toUtc(),
              revision: row.revision + 1,
            )
          else
            row,
      ];
      _editingMessage = null;
    });
    return true;
  }

  void _cancelEditing() => setState(() => _editingMessage = null);

  void _startReply(Message message) => setState(() {
    _replyTarget = message;
    _editingMessage = null;
  });

  void _cancelReply() => setState(() => _replyTarget = null);

  // Runs after the package's "Delete this message?" confirmation. Replies to
  // the removed row keep their reference: the next preview resolution simply
  // finds nothing for that id, so their quoted block becomes "Original
  // message unavailable".
  FutureOr<bool> _deleteMessage(Message message) {
    setState(() {
      _history = <Message>[
        for (final row in _history)
          if (row.id != message.id) row,
      ];
      if (_editingMessage?.id == message.id) _editingMessage = null;
      if (_replyTarget?.id == message.id) _replyTarget = null;
      if (_highlightedMessageId == message.id) _highlightedMessageId = null;
      if (_windowEnd > _history.length) _windowEnd = _history.length;
      if (_windowStart >= _windowEnd) _showLiveTail();
    });
    return true;
  }

  // A row already in the rendered window is only highlighted and scrolled
  // to; anything else replaces the window with a bounded one centred on it,
  // which is what the controller does through `getMessageContext`.
  void _jumpToMessage(String messageId) {
    final index = _history.indexWhere((row) => row.id == messageId);
    if (index < 0) {
      // The quoted message is gone — a coded `404 MESSAGE_NOT_FOUND`, not a
      // failure to reach the backend. The reference and the affordance stay
      // and the quoted block already reads "Original message unavailable".
      _showNotice('That message is no longer available');
      return;
    }
    setState(() {
      if (index < _windowStart || index >= _windowEnd) {
        _showWindowAround(index);
      }
      _highlightedMessageId = messageId;
    });
  }

  // The package reports the flash is over — a timeout, a user-initiated
  // scroll, or a target it could not reach.
  void _clearHighlight() {
    if (!mounted || _highlightedMessageId == null) return;
    setState(() => _highlightedMessageId = null);
  }

  FutureOr<void> _loadOlderMessages() {
    if (_windowStart == 0) return null;
    setState(() {
      _windowStart =
          _windowStart - _pageStep < 0 ? 0 : _windowStart - _pageStep;
    });
    return null;
  }

  // The newer edge only exists while a jumped window is rendered. A page that
  // reaches the room's newest message returns to the live tail rather than
  // flipping the window's mode in place.
  FutureOr<void> _loadNewerMessages() {
    if (_windowEnd >= _history.length) {
      _returnToLatest();
      return null;
    }
    setState(() {
      final end = _windowEnd + _pageStep;
      if (end >= _history.length) {
        _showLiveTail();
      } else {
        _windowEnd = end;
      }
    });
    return null;
  }

  void _returnToLatest() => setState(_showLiveTail);

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        final brand = Row(
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
          ],
        );
        final selector =
            narrow
                ? InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Example configuration',
                    border: OutlineInputBorder(),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ShowcaseVariant>(
                      key: const ValueKey('variant-selector'),
                      value: variant,
                      isExpanded: true,
                      items: [
                        for (final value in ShowcaseVariant.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) onVariantChanged(value);
                      },
                    ),
                  ),
                )
                : SegmentedButton<ShowcaseVariant>(
                  key: const ValueKey('variant-selector'),
                  segments: <ButtonSegment<ShowcaseVariant>>[
                    for (final value in ShowcaseVariant.values)
                      ButtonSegment<ShowcaseVariant>(
                        value: value,
                        label: Text(value.label),
                      ),
                  ],
                  selected: <ShowcaseVariant>{variant},
                  onSelectionChanged:
                      (values) => onVariantChanged(values.single),
                );
        return Material(
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child:
                narrow
                    ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [brand, const SizedBox(height: 16), selector],
                    )
                    : Row(
                      children: [
                        Expanded(child: brand),
                        const SizedBox(width: 24),
                        selector,
                      ],
                    ),
          ),
        );
      },
    );
  }
}

class _VariantSummary extends StatelessWidget {
  const _VariantSummary({required this.spec});

  final _VariantSpec spec;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 700;
        final description = Column(
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
        );
        final props = Wrap(
          alignment: narrow ? WrapAlignment.start : WrapAlignment.end,
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final prop in spec.props)
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(prop, style: const TextStyle(fontSize: 11)),
              ),
          ],
        );
        return narrow
            ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [description, const SizedBox(height: 12), props],
            )
            : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: description),
                const SizedBox(width: 20),
                Flexible(child: props),
              ],
            );
      },
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

/// A showcase composer: the package's [ConvoKitComposerBuilder] arguments plus
/// the host-owned edit and reply state (the message being edited or quoted,
/// or null, and the cancel actions), which a custom composer renders as its
/// own banners. The package typedef itself is unchanged; the page adapts one
/// to the other.
typedef _ShowcaseComposerBuilder =
    Widget Function(
      BuildContext context,
      TextEditingController controller,
      bool isSending,
      VoidCallback send,
      VoidCallback? addAttachment,
      Message? editing,
      VoidCallback cancelEdit,
      Message? replying,
      VoidCallback cancelReply,
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
    this.listRowBuilder,
    this.headerBuilder,
    this.messageBuilder,
    this.messageContextBuilder,
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
  final ConvoKitInboxItemBuilder? listRowBuilder;
  final ConvoKitConversationHeaderBuilder? headerBuilder;
  final ConvoKitMessageItemBuilder? messageBuilder;
  final ConvoKitMessageItemContextBuilder? messageContextBuilder;
  final ConvoKitMediaBlockBuilder? mediaBlockBuilder;
  final ConvoKitReadReceiptBuilder? readReceiptBuilder;
  final _ShowcaseComposerBuilder? composerBuilder;
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
        'Default list rows with previews, unread badges and the mark-unread dot, header, bubbles with the "Edited" caption, quoted blocks and long-press reply/edit/delete actions, receipts, attachments and a composer with its edit mode and its "Replying to" strip.',
    props: <String>[
      'summaries',
      'currentUserId',
      'onRefresh',
      'onAddAttachment',
      'readPositionByUserId',
      'reverseMessages: true',
      'editingMessage',
      'onEditMessage',
      'onSaveEdit',
      'onDeleteMessage',
      'replyTarget',
      'onReplyToMessage',
      'replyPreviewByMessageId',
      'onJumpToMessage',
    ],
    primary: Color(0xFF148F78),
    theme: ConvoKitUiThemeData.light(),
  ),
  ShowcaseVariant.branded => _VariantSpec(
    variant: ShowcaseVariant.branded,
    title: '2 · Branded customer support',
    description:
        'A purple support workspace with custom rows (count badge or mark-unread dot), header, ticket card, receipt and a composer that shows its own banner while a message is edited or quoted.',
    props: const <String>[
      'rowBuilder',
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
    listRowBuilder: _supportListItem,
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
        'Dense list rows and message rendering (with the "Edited" caption from Message.isEdited) for dashboards with limited space. Its rows keep the frozen six-parameter ConvoKitMessageItemBuilder of 0.8.0 and render exactly as they did.',
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
    listRowBuilder: _compactListItem,
    headerBuilder: _compactHeader,
    messageBuilder: _compactMessage,
    composerBuilder: _compactComposer,
    typingIndicatorBuilder: _compactTyping,
    typingUserIds: const <String>{'jordan'},
    reverseMessages: false,
    showBack: true,
    showRefresh: false,
  ),
  ShowcaseVariant.quoted => const _VariantSpec(
    variant: ShowcaseVariant.quoted,
    title: '4 · Quoted rows',
    description:
        'The standard configuration with one override: message rows built from ConvoKitMessageItemScope through messageContextBuilder, so a custom row renders its own quoted block, "Reply" action and jump affordance. Everything else, including the composer and its "Replying to" strip, stays the package default.',
    props: <String>[
      'messageContextBuilder',
      'ConvoKitMessageItemScope',
      'onReplyToMessage',
      'replyPreviewByMessageId',
      'onJumpToMessage',
      'highlightColor',
    ],
    primary: Color(0xFF1B5E8C),
    theme: ConvoKitUiThemeData(
      backgroundColor: Color(0xFFF2F6FA),
      surfaceColor: Colors.white,
      primaryColor: Color(0xFF1B5E8C),
      textColor: Color(0xFF16222C),
      mutedTextColor: Color(0xFF6A7681),
      borderColor: Color(0xFFDCE5EC),
      errorColor: Color(0xFFBA1A1A),
      incomingBubbleColor: Color(0xFFEDF3F8),
      outgoingBubbleColor: Color(0xFF1B5E8C),
      outgoingTextColor: Colors.white,
      cornerRadius: 14,
      avatarRadius: 19,
      // The flash behind a row a jump landed on; null would use the accent
      // colour at low opacity.
      highlightColor: Color(0x3FF2B705),
    ),
    messageContextBuilder: _quotedMessage,
  ),
};

Widget _supportListItem(
  BuildContext context,
  ConvoKitInboxRow row,
  VoidCallback onTap,
) {
  final conversation = row.conversation;
  final summary = row.summary;
  final unreadCount = summary?.unreadCount ?? 0;
  final unreadCapped = summary?.unreadCountCapped ?? false;
  final counted = unreadCount > 0 || unreadCapped;
  // `isUnread` also covers the user's own "mark unread" marker with no count.
  final unread = counted || (summary?.isUnread ?? false);
  final preview =
      convoKitInboxPreview(
        conversation: conversation,
        summary: summary,
        currentUserId: row.currentUserId,
      ) ??
      'No messages yet';
  return Material(
    key: ValueKey('support-row-${conversation.id}'),
    color: unread ? const Color(0xFFF0EAFF) : Colors.white,
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
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF716A7C),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (counted)
              ConvoKitUnreadBadge(
                key: const ValueKey('support-unread-badge'),
                unreadCount: unreadCount,
                capped: unreadCapped,
              )
            else if (unread)
              const ConvoKitUnreadDot(key: ValueKey('support-unread-dot')),
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
    constraints: const BoxConstraints(minHeight: 72),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
            mainAxisSize: MainAxisSize.min,
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
  final readers = <String>[
    for (final participant in _showcaseParticipants)
      if (readerIds.contains(participant.appUserId)) participant.name,
  ];
  return Padding(
    key: const ValueKey('support-read-receipt'),
    padding: const EdgeInsets.only(top: 4, right: 4),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.done_all_rounded, size: 13, color: Color(0xFF6750A4)),
        const SizedBox(width: 4),
        Text(
          'Read by ${readers.join(', ')}',
          style: const TextStyle(fontSize: 10),
        ),
      ],
    ),
  );
}

// The package prefilled `controller` with the edited text and `send` saves
// while `editing` is set and sends otherwise — quoting the reply target when
// one is set. This composer only adds its own banners and label.
Widget _supportComposer(
  BuildContext context,
  TextEditingController controller,
  bool isSending,
  VoidCallback send,
  VoidCallback? addAttachment,
  Message? editing,
  VoidCallback cancelEdit,
  Message? replying,
  VoidCallback cancelReply,
) {
  return Container(
    key: const ValueKey('support-composer'),
    padding: const EdgeInsets.all(12),
    color: Colors.white,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (replying != null)
          Padding(
            key: const ValueKey('support-reply-banner'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.reply_rounded,
                  size: 16,
                  color: Color(0xFF6750A4),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quoting ${_showcaseUserName(replying.senderId)} · '
                    '${replying.text ?? 'attachment'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF514A5C),
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: isSending ? null : cancelReply,
                  child: const Text('Cancel quote'),
                ),
              ],
            ),
          ),
        if (editing != null)
          Padding(
            key: const ValueKey('support-edit-banner'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: Color(0xFF6750A4),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Editing your reply · ${editing.text ?? 'attachment caption'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF514A5C),
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: isSending ? null : cancelEdit,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        Row(
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
              child: Text(editing == null ? 'Send' : 'Save'),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _compactListItem(
  BuildContext context,
  ConvoKitInboxRow row,
  VoidCallback onTap,
) {
  final conversation = row.conversation;
  final summary = row.summary;
  // A dense row shows one dot for any unread state: new messages or the
  // user's own "mark unread" marker (`isUnread` with a count of 0).
  final unread =
      summary != null &&
      (summary.isUnread ||
          summary.unreadCount > 0 ||
          summary.unreadCountCapped);
  return Material(
    color: Colors.transparent,
    child: ListTile(
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
          summary == null
              ? null
              : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unread) ...[
                    const Icon(
                      Icons.circle,
                      key: ValueKey('compact-unread-dot'),
                      size: 8,
                      color: Color(0xFF2F8A72),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    convoKitInboxTimeLabel(summary.activityAt),
                    style: const TextStyle(
                      fontSize: 9,
                      color: Color(0xFF7B8582),
                    ),
                  ),
                ],
              ),
    ),
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
        // `Message.isEdited` (revision > 0) is the package's edited signal;
        // the row never derives it from timestamps.
        if (message.isEdited) ...[
          const Text(
            'Edited',
            style: TextStyle(
              fontSize: 9,
              fontStyle: FontStyle.italic,
              color: Color(0xFF7B8582),
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          isConvoKitPendingMessage(message)
              ? 'Sending…'
              : _localMessageTime(message.createdAt),
          style: const TextStyle(fontSize: 9, color: Color(0xFF7B8582)),
        ),
      ],
    ),
  );
}

String _localMessageTime(DateTime createdAt) {
  final local = createdAt.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

// `replying` is always null in this configuration: its rows keep the frozen
// positional `ConvoKitMessageItemBuilder`, which receives no reply members
// and therefore offers no "Reply" action. That is the trade the compact
// configuration demonstrates, and `messageContextBuilder` is the way out of
// it — see the quoted-rows configuration.
Widget _compactComposer(
  BuildContext context,
  TextEditingController controller,
  bool isSending,
  VoidCallback send,
  VoidCallback? addAttachment,
  Message? editing,
  VoidCallback cancelEdit,
  Message? replying,
  VoidCallback cancelReply,
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
        // A dense composer marks edit mode inline: a chip in place of the
        // hint plus a cancel action; `send` saves through the package.
        if (editing != null) ...[
          InputChip(
            key: const ValueKey('compact-edit-chip'),
            visualDensity: VisualDensity.compact,
            label: const Text('Editing', style: TextStyle(fontSize: 10)),
            deleteButtonTooltipMessage: 'Cancel edit',
            onDeleted: isSending ? null : cancelEdit,
          ),
          const SizedBox(width: 6),
        ],
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
          tooltip:
              editing == null ? 'Send compact message' : 'Save compact message',
          onPressed: isSending ? null : send,
          icon: Icon(
            editing == null ? Icons.arrow_upward_rounded : Icons.check_rounded,
            size: 18,
          ),
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

// A message row built from `ConvoKitMessageItemScope`, the 0.9.0 row context,
// through the package's `messageContextBuilder`.
//
// The scope carries every argument the frozen positional
// `ConvoKitMessageItemBuilder` carries — `message`, `chronologicalIndex`,
// `isCurrentUser`, `sender`, `readerIds` — so a row can migrate to it without
// losing one, plus the quoted-reply members used below. Reply and jump state
// stays with the host: the row only calls what the scope hands it.
Widget _quotedMessage(BuildContext context, ConvoKitMessageItemScope scope) {
  final message = scope.message;
  final theme = ConvoKitUiThemeData.of(context);
  final mine = scope.isCurrentUser;
  final foreground = mine ? theme.outgoingTextColor : theme.textColor;
  // The author comes off the scope's `sender` participant, not from the
  // page's own lookup, and the row's place in the loaded window comes off
  // `chronologicalIndex`: both are frozen-builder arguments the scope still
  // carries, so a row migrating to it loses neither.
  final author = scope.sender?.name ?? _showcaseUserName(message.senderId);
  return Semantics(
    container: true,
    label: 'Row ${scope.chronologicalIndex + 1} from $author',
    child: Padding(
      key: ValueKey('quoted-message-${message.id}'),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
            decoration: BoxDecoration(
              color:
                  mine ? theme.outgoingBubbleColor : theme.incomingBubbleColor,
              border: mine ? null : Border.all(color: theme.borderColor),
              borderRadius: BorderRadius.circular(theme.cornerRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mine ? 'You' : author,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                // `isReply` is `message.replyToMessageId != null`: the
                // reference is what makes a row a reply, and it survives the
                // quoted message being edited or deleted.
                if (scope.isReply) ...[
                  const SizedBox(height: 5),
                  _quotedBlock(context, scope, foreground),
                ],
                const SizedBox(height: 5),
                Text(
                  message.text ?? '[structured message]',
                  style: TextStyle(
                    color: foreground,
                    fontSize: 14,
                    height: 1.3,
                  ),
                ),
                if (message.media.isNotEmpty)
                  Text(
                    message.media.length == 1
                        ? '1 attachment'
                        : '${message.media.length} attachments',
                    style: TextStyle(
                      color: foreground.withValues(alpha: 0.75),
                      fontSize: 11,
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isConvoKitPendingMessage(message)
                          ? 'Sending…'
                          : _localMessageTime(message.createdAt),
                      style: TextStyle(
                        color: foreground.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                    // `Message.isEdited` (revision > 0), never a timestamp
                    // comparison.
                    if (message.isEdited)
                      Text(
                        ' · Edited',
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.7),
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    if (mine && scope.readerIds.isNotEmpty)
                      Text(
                        ' · Read by ${scope.readerIds.length}',
                        style: TextStyle(
                          color: foreground.withValues(alpha: 0.7),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // `reply` is non-null exactly when `canReply`: a confirmed row while
          // the caller's role allows quoting, own or not.
          if (scope.canReply)
            TextButton.icon(
              key: ValueKey('quoted-reply-${message.id}'),
              onPressed: scope.reply,
              icon: const Icon(Icons.reply_rounded, size: 15),
              label: const Text('Reply', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
        ],
      ),
    ),
  );
}

// The quoted block has three states and they are never collapsed into two: a
// resolved preview, the terminal "the original is gone" answer, and a
// reference whose preview has not resolved yet, which must not claim the
// original is unavailable.
Widget _quotedBlock(
  BuildContext context,
  ConvoKitMessageItemScope scope,
  Color foreground,
) {
  final preview = scope.replyPreview;
  final muted = foreground.withValues(alpha: 0.72);
  final String label;
  if (preview != null) {
    final text = preview.text?.trim() ?? '';
    final body =
        text.isEmpty
            ? (preview.mediaCount > 0 ? 'Attachment' : 'No text')
            : (preview.textTruncated ? '$text…' : text);
    label = '${_showcaseUserName(preview.senderId)}: $body';
  } else if (scope.replyTargetUnavailable) {
    label = 'Original message unavailable';
  } else {
    label = 'Quoted message';
  }
  final block = Container(
    key: ValueKey('quoted-quote-${scope.message.id}'),
    padding: const EdgeInsets.fromLTRB(7, 4, 7, 5),
    decoration: BoxDecoration(
      color: foreground.withValues(alpha: 0.12),
      border: Border(left: BorderSide(color: muted, width: 3)),
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
    ),
    child: Text(
      label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: muted, fontSize: 11.5),
    ),
  );
  // The affordance stays even when the original is gone: `jumpToReplyTarget`
  // is non-null while the row carries a reference and jumping is reachable.
  if (scope.jumpToReplyTarget == null) {
    return Semantics(label: 'Quoted message: $label', child: block);
  }
  return Semantics(
    button: true,
    label: 'Show quoted message: $label',
    child: InkWell(onTap: scope.jumpToReplyTarget, child: block),
  );
}

const _currentUserId = 'me';

String _showcaseUserName(String userId) => switch (userId) {
  _currentUserId => 'Maya Chen',
  'alex' => 'Alex Rivera',
  'jordan' => 'Jordan Lee',
  _ => userId,
};

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

/// Inbox data for every showcase room, shaped like the entries of
/// `GET /api/v1/inbox`: the newest message, the unread count, the activity
/// time and the connected user's private "mark unread" state (`isUnread`,
/// `unreadMarkedAt`, `privateStateVersion`). The first room has unread
/// messages (a numeric badge); the last one was marked unread by the user with
/// nothing new in it, so `isUnread` is true while `unreadCount` stays 0 and the
/// rows render a numberless dot.
final _showcaseSummaries = <String, InboxSummary>{
  'launch-room': InboxSummary(
    latestMessage: _showcaseMessages.last,
    unreadCount: 2,
    activityAt: _showcaseMessages.last.createdAt,
    isUnread: true,
    unreadMarkedAt: null,
    privateStateVersion: 0,
  ),
  'customer-ops': InboxSummary(
    latestMessage: Message(
      id: 'customer-ops-latest',
      conversationId: 'customer-ops',
      senderId: 'alex',
      text: 'Refund approved, closing the ticket.',
      createdAt: _showcaseNow.subtract(const Duration(minutes: 18)),
      revision: 0,
    ),
    activityAt: _showcaseNow.subtract(const Duration(minutes: 18)),
    isUnread: false,
    unreadMarkedAt: null,
    privateStateVersion: 0,
  ),
  'design-review': InboxSummary(
    latestMessage: Message(
      id: 'design-review-latest',
      conversationId: 'design-review',
      senderId: 'jordan',
      media: const <Map<String, dynamic>>[
        <String, dynamic>{'type': 'image', 'name': 'onboarding-v3.png'},
      ],
      createdAt: _showcaseNow.subtract(const Duration(hours: 2)),
      revision: 0,
    ),
    activityAt: _showcaseNow.subtract(const Duration(hours: 2)),
    isUnread: false,
    unreadMarkedAt: null,
    privateStateVersion: 0,
  ),
  'incident-room': InboxSummary(
    latestMessage: Message(
      id: 'incident-room-latest',
      conversationId: 'incident-room',
      senderId: _currentUserId,
      text: 'Postmortem scheduled for Thursday.',
      createdAt: _showcaseNow.subtract(const Duration(hours: 6)),
      revision: 0,
    ),
    activityAt: _showcaseNow.subtract(const Duration(hours: 6)),
    isUnread: true,
    unreadMarkedAt: _showcaseNow.subtract(const Duration(minutes: 40)),
    privateStateVersion: 1,
  ),
};

/// The open room's whole history, shaped like `GET /api/v1/messages` rows and
/// ordered oldest first. Every row carries the server `revision` (0 as
/// created, +1 per content edit); the connected user's second message was
/// edited once, so `Message.isEdited` is true and the rows render the
/// "Edited" caption beside its time.
///
/// The page renders a window of this list rather than all of it, so the nine
/// oldest rows start outside the loaded window exactly as they would against
/// a backend, and `message-3` quotes one of them — activating its quoted
/// block loads the window around it. `message-5` and `message-7` quote rows
/// inside the window, and `message-6` quotes `message-gone`, a message
/// deleted before this snapshot: a reply keeps its reference for good, so
/// that block renders "Original message unavailable" while staying
/// activatable. `message-5` is both a reply and an edited row, because an
/// edit never changes what a message quotes.
final _showcaseMessages = <Message>[
  Message(
    id: 'message-a',
    conversationId: 'launch-room',
    senderId: 'alex',
    text: 'Kickoff notes from the launch sync are in the shared drive.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 95)),
    revision: 0,
  ),
  Message(
    id: 'message-b',
    conversationId: 'launch-room',
    senderId: _currentUserId,
    text: 'Thanks — I will fold them into the checklist.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 92)),
    revision: 0,
  ),
  Message(
    id: 'message-c',
    conversationId: 'launch-room',
    senderId: 'jordan',
    text: 'Reminder: the embargo lifts on Thursday at 09:00 UTC.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 88)),
    revision: 0,
  ),
  Message(
    id: 'message-d',
    conversationId: 'launch-room',
    senderId: 'alex',
    text: 'Pricing page copy is with legal until tomorrow.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 80)),
    revision: 0,
  ),
  Message(
    id: 'message-e',
    conversationId: 'launch-room',
    senderId: _currentUserId,
    text: 'Noted. I will hold the announcement draft until it clears.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 74)),
    revision: 0,
  ),
  Message(
    id: 'message-f',
    conversationId: 'launch-room',
    senderId: 'jordan',
    text: 'Support macros for the new plan are written.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 66)),
    revision: 0,
  ),
  Message(
    id: 'message-g',
    conversationId: 'launch-room',
    senderId: 'alex',
    text: 'Design has the hero image queued for export.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 58)),
    revision: 0,
  ),
  Message(
    id: 'message-h',
    conversationId: 'launch-room',
    senderId: _currentUserId,
    text: 'Perfect. That unblocks the press kit.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 50)),
    revision: 0,
  ),
  Message(
    id: 'message-i',
    conversationId: 'launch-room',
    senderId: 'jordan',
    text: 'Status call moved to 15:00 so the whole team can join.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 44)),
    revision: 0,
  ),
  Message(
    id: 'message-1',
    conversationId: 'launch-room',
    senderId: 'alex',
    text: 'The final launch checklist is ready for review.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 16)),
    revision: 0,
  ),
  Message(
    id: 'message-2',
    conversationId: 'launch-room',
    senderId: _currentUserId,
    text: 'Great. I approved the copy and shared the release notes.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 11)),
    revision: 0,
  ),
  Message(
    id: 'message-3',
    conversationId: 'launch-room',
    senderId: 'alex',
    text: 'Pulling the kickoff notes back up so nothing is lost.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 10)),
    revision: 0,
    replyToMessageId: 'message-a',
  ),
  Message(
    id: 'message-4',
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
    revision: 0,
  ),
  Message(
    id: 'message-5',
    conversationId: 'launch-room',
    senderId: _currentUserId,
    text: 'Filing this with the release record.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 6)),
    updatedAt: _showcaseNow.subtract(const Duration(minutes: 4)),
    revision: 1,
    replyToMessageId: 'message-4',
  ),
  Message(
    id: 'message-6',
    conversationId: 'launch-room',
    senderId: 'jordan',
    text: 'Still waiting on an answer to this one.',
    createdAt: _showcaseNow.subtract(const Duration(minutes: 5)),
    revision: 0,
    replyToMessageId: 'message-gone',
  ),
  Message(
    id: 'message-7',
    conversationId: 'launch-room',
    senderId: _currentUserId,
    text: 'I linked this conversation to the support case.',
    media: const <Map<String, dynamic>>[
      <String, dynamic>{'type': 'ticket', 'name': 'Ticket CK-4821'},
    ],
    createdAt: _showcaseNow.subtract(const Duration(minutes: 3)),
    revision: 0,
    replyToMessageId: 'message-5',
  ),
];
