import 'dart:async';
import 'dart:convert';

import 'package:convokit_flutter/convokit_flutter.dart';
import 'package:convokit_flutter_ui/convokit_flutter_ui.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _backendUrl = String.fromEnvironment('CONVOKIT_BACKEND_URL');
const _clientId = String.fromEnvironment('CONVOKIT_CLIENT_ID');
const _tokenEndpoint = String.fromEnvironment('CONVOKIT_TOKEN_ENDPOINT');
const _userId = String.fromEnvironment(
  'CONVOKIT_APP_USER_ID',
  defaultValue: 'flutter_ui_example',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_clientId.isEmpty || _tokenEndpoint.isEmpty) {
    runApp(const _ConfigurationHelp());
    return;
  }
  ConvoKit.configure(
    backendUrl: _backendUrl.isEmpty ? ConvoKit.defaultBackendUrl : _backendUrl,
    clientId: _clientId,
    tokenProvider: _issueToken,
  );
  await ConvoKit.connectUser(_userId);
  runApp(const _ExampleApp());
}

Future<String> _issueToken(String appUserId) async {
  final response = await http.post(
    Uri.parse(_tokenEndpoint),
    headers: <String, String>{
      'content-type': 'application/json',
      'x-client-id': _clientId,
    },
    body: jsonEncode(<String, String>{'appUserId': appUserId}),
  );
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw StateError('The token endpoint rejected the example user.');
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  final token =
      body['token'] ??
      (body['data'] is Map<String, dynamic>
          ? (body['data'] as Map<String, dynamic>)['token']
          : null);
  if (token is! String || token.isEmpty) {
    throw StateError('The token endpoint returned no token.');
  }
  return token;
}

class _ExampleApp extends StatelessWidget {
  const _ExampleApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ConvoKit UI example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF148F78)),
        extensions: const <ThemeExtension<dynamic>>[
          ConvoKitUiThemeData.light(),
        ],
      ),
      home: const _InboxPage(),
    );
  }
}

class _InboxPage extends StatefulWidget {
  const _InboxPage();

  @override
  State<_InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<_InboxPage> {
  // Owned here rather than by the list widget so the room screen can mark a
  // conversation unread through the same controller that renders the list:
  // the response patches that row's summary at once and the default row
  // shows the numberless dot; other devices refetch on `inbox_activity`.
  final _listController = ConvoKitConversationListController();

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversations')),
      body: ConvoKitConversationList(
        controller: _listController,
        onConversationSelected: (conversation) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder:
                  (_) => _ConversationPage(
                    conversationId: conversation.id,
                    listController: _listController,
                  ),
            ),
          );
        },
      ),
    );
  }
}

class _ConversationPage extends StatelessWidget {
  const _ConversationPage({
    required this.conversationId,
    required this.listController,
  });

  final String conversationId;
  final ConvoKitConversationListController listController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The package's default rows and composer, bound to the room
      // controller: the connected user's own confirmed rows offer "Edit
      // message" / "Delete message" on a long press, the composer saves an
      // edit with the revision captured when it began (a conflict reloads
      // the row and keeps the draft), and a confirmed delete removes the row
      // here and on other devices. Nothing to wire for that.
      //
      // Quoting needs no wiring either: every confirmed row offers "Reply",
      // the composer shows its cancellable "Replying to" strip, the sent
      // message carries `replyToMessageId` and renders a quoted block whose
      // text the controller resolves in one batched request per rendered
      // page. Activating that block opens the quoted message, loading a
      // window around it when it is outside the loaded history and offering
      // "Jump to latest" until the room rejoins its newest page. The quoted
      // routes need the 0.9 backend: against an older one the controller
      // hides the jump affordance after the first answer and leaves quoted
      // text unresolved, and a quote sent to it is delivered without its
      // reference, so the quote disappears when the row is confirmed.
      body: ConvoKitConversation(
        conversationId: conversationId,
        onBack: () => Navigator.of(context).pop(),
        // An app bar in place of the default header, with a "Mark unread"
        // action. Opening the room acknowledged it with the private-state
        // version captured at open; the mark bumps that version, so this
        // room's later acknowledgements no longer clear the marker and it
        // survives until the next open. Leaving right away matches the
        // mark's intent.
        headerBuilder:
            (context, conversation, onBack, onRefresh) => AppBar(
              leading: onBack == null ? null : BackButton(onPressed: onBack),
              title: Text(conversation.displayTitle),
              actions: [
                IconButton(
                  tooltip: 'Mark unread',
                  icon: const Icon(Icons.mark_chat_unread_outlined),
                  onPressed: () {
                    unawaited(listController.markUnread(conversation.id));
                    onBack?.call();
                  },
                ),
                if (onRefresh != null)
                  IconButton(
                    tooltip: 'Refresh conversation',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => onRefresh(),
                  ),
              ],
            ),
      ),
    );
  }
}

class _ConfigurationHelp extends StatelessWidget {
  const _ConfigurationHelp();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Run with CONVOKIT_CLIENT_ID and CONVOKIT_TOKEN_ENDPOINT '
              'dart-defines.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
