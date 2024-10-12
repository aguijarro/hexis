import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Systems Thinking Assistant',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _questionController = TextEditingController();
  String _analysis = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _conversation = [];
  String? _conversationId;
  String? _systemsMapUrl;

  @override
  void initState() {
    super.initState();
    _startConversation();
  }

  Future<void> _startConversation() async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:8000/start_conversation'),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        setState(() {
          _conversationId = result['conversation_id'];
        });
      } else {
        throw Exception('Failed to start conversation');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error starting conversation: $e')),
      );
    }
  }

  Future<void> _analyzeQuestion() async {
    setState(() => _isLoading = true);

    try {
      if (_conversationId == null) {
        await _startConversation();
      }

      final response = await http.post(
        Uri.parse('http://localhost:8000/analyze'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode({
          'query': _questionController.text,
          'conversation_id': _conversationId,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        setState(() {
          _analysis = result['analysis'];
          _conversation =
              List<Map<String, dynamic>>.from(result['conversation']);
        });

        await _generateSystemsMap();
      } else {
        throw Exception('Failed to analyze question: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadDocument() async {
    final result = await FilePicker.platform.pickFiles();

    if (result != null) {
      final file = result.files.first;
      final bytes = file.bytes;

      if (bytes != null) {
        try {
          final request = http.MultipartRequest(
            'POST',
            Uri.parse('http://localhost:8000/upload-document'),
          );
          request.files.add(http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: file.name,
          ));

          final response = await request.send();

          if (response.statusCode == 200) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Document uploaded successfully')),
            );
          } else {
            throw Exception(
                'Failed to upload document: ${response.statusCode}');
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  Future<void> _generateSystemsMap() async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:8000/systems-map'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'elements': ['Element 1', 'Element 2', 'Element 3'],
          'relationships': [
            {
              'source': 'Element 1',
              'target': 'Element 2',
              'type': 'influences'
            },
            {'source': 'Element 2', 'target': 'Element 3', 'type': 'affects'},
          ],
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _systemsMapUrl = 'http://localhost:8000/systems-map';
        });
      } else {
        throw Exception(
            'Failed to generate systems map: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Systems Thinking Assistant'),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _conversation.length,
                      itemBuilder: (context, index) {
                        final message = _conversation[index];
                        return ListTile(
                          title: Text(message['content'].toString()),
                          leading: Icon(
                            message['role'] == 'user'
                                ? Icons.person
                                : Icons.android,
                          ),
                        );
                      },
                    ),
                  ),
                  TextField(
                    controller: _questionController,
                    decoration: InputDecoration(
                      hintText: 'Enter your question',
                    ),
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _analyzeQuestion,
                    child: Text('Analyze'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton(
                    onPressed: _uploadDocument,
                    child: Text('Upload Document'),
                  ),
                  SizedBox(height: 16),
                  Expanded(
                    child: _systemsMapUrl != null
                        ? Image.network(_systemsMapUrl!)
                        : Center(child: Text('No systems map available')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Conversation {
  final String id;
  final List<Map<String, dynamic>> messages;

  Conversation({required this.id, required this.messages});

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'],
      messages: List<Map<String, dynamic>>.from(json['messages']),
    );
  }
}
