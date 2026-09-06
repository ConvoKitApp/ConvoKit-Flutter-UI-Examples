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

class _InboxPage extends StatelessWidget {
  const _InboxPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversations')),
      body: ConvoKitConversationList(
        onConversationSelected: (conversation) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder:
                  (_) => Scaffold(
                    body: ConvoKitConversation(
                      conversationId: conversation.id,
                      onBack: () => Navigator.of(context).pop(),
                    ),
                  ),
            ),
          );
        },
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
