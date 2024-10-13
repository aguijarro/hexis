import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';

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
  final FocusNode _questionFocusNode = FocusNode();
  List<String> _uploadedDocuments = [];

  @override
  void initState() {
    super.initState();
    _startConversation();
  }

  @override
  void dispose() {
    _questionFocusNode.dispose();
    super.dispose();
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
          // Clear the text input
          _questionController.clear();
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
            final responseData = await response.stream.bytesToString();
            final jsonResponse = json.decode(responseData);
            setState(() {
              _uploadedDocuments.add(file.name);
              _systemsMapUrl = jsonResponse['systems_map'];
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text('Document uploaded and processed successfully')),
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
        backgroundColor: Colors.blueGrey[800],
      ),
      backgroundColor: Colors.blueGrey[100],
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Expanded(
              flex: 1,
              child: _buildConversationArea(),
            ),
            SizedBox(width: 16),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  Expanded(
                    flex: 1,
                    child: _buildUploadDocumentsArea(),
                  ),
                  SizedBox(height: 16),
                  Expanded(
                    flex: 2,
                    child: _buildSystemsMapArea(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConversationArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 2,
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
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
                  return Card(
                    color: message['role'] == 'user'
                        ? Colors.blue[50]
                        : Colors.green[50],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      title: Text(message['content'].toString()),
                      leading: Icon(
                        message['role'] == 'user'
                            ? Icons.person
                            : Icons.android,
                        color: message['role'] == 'user'
                            ? Colors.blue
                            : Colors.green,
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _questionController,
              focusNode: _questionFocusNode,
              decoration: InputDecoration(
                hintText: 'Enter your question',
                filled: true,
                fillColor: Colors.grey[200],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _analyzeQuestion,
              child: _isLoading
                  ? CircularProgressIndicator(color: Colors.white)
                  : Text('Analyze'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 185, 222, 252),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUploadDocumentsArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 2,
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upload Documents',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _uploadDocument,
              child: Text('Upload Document'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 185, 222, 252),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
            SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _uploadedDocuments.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: Icon(Icons.description),
                    title: Text(_uploadedDocuments[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemsMapArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.5),
            spreadRadius: 2,
            blurRadius: 5,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Systems Map',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _buildSystemsMapContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemsMapContent() {
    if (_systemsMapUrl == null || _systemsMapUrl!.isEmpty) {
      return Center(child: Text('No systems map available'));
    }

    if (_systemsMapUrl!.startsWith('http')) {
      // It's a URL, load it as a network image
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: InteractiveViewer(
          boundaryMargin: EdgeInsets.all(20),
          minScale: 0.5,
          maxScale: 3,
          child: Image.network(
            _systemsMapUrl!,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, loadingProgress) {
              if (loadingProgress == null) return child;
              return Center(child: CircularProgressIndicator());
            },
            errorBuilder: (context, error, stackTrace) {
              return Center(child: Text('Error loading image'));
            },
          ),
        ),
      );
    } else {
      // Assume it's a base64 encoded image
      try {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: InteractiveViewer(
            boundaryMargin: EdgeInsets.all(20),
            minScale: 0.5,
            maxScale: 3,
            child: Image.memory(
              base64Decode(_systemsMapUrl!.split(',').last),
              fit: BoxFit.contain,
            ),
          ),
        );
      } catch (e) {
        return Center(child: Text('Error decoding image'));
      }
    }
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
