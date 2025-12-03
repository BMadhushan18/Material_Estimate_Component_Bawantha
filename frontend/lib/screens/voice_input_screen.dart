import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';

class VoiceInputScreen extends StatefulWidget {
  const VoiceInputScreen({super.key});

  @override
  State<VoiceInputScreen> createState() => _VoiceInputScreenState();
}

class _VoiceInputScreenState extends State<VoiceInputScreen> {
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _transcription = '';
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (status.isGranted) {
      final available = await _speech.initialize();
      setState(() => _speechAvailable = available);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice Input'),
        backgroundColor: Colors.blue[700],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Describe your building structure:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'Example: "There are 3 bedrooms. The master bedroom on the right side is 12 feet by 10 feet. The living room is 15 feet by 12 feet..."',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // Transcription display
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blue),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey[50],
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _transcription.isEmpty
                        ? 'Tap microphone to start speaking...'
                        : _transcription,
                    style: TextStyle(
                      fontSize: 16,
                      color: _transcription.isEmpty
                          ? Colors.grey
                          : Colors.black,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Microphone button
                FloatingActionButton.large(
                  onPressed: _speechAvailable
                      ? (_isListening ? _stopListening : _startListening)
                      : null,
                  backgroundColor: _isListening ? Colors.red : Colors.blue,
                  child: Icon(_isListening ? Icons.stop : Icons.mic, size: 32),
                ),

                // Submit button
                ElevatedButton.icon(
                  onPressed: _transcription.isEmpty
                      ? null
                      : () => Navigator.pop(context, _transcription),
                  icon: const Icon(Icons.check),
                  label: const Text('Submit'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                  ),
                ),

                // Clear button
                IconButton(
                  onPressed: _transcription.isEmpty
                      ? null
                      : () => setState(() => _transcription = ''),
                  icon: const Icon(Icons.clear),
                  iconSize: 32,
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Status indicator
            Center(
              child: Text(
                _isListening
                    ? 'Listening...'
                    : _speechAvailable
                    ? 'Ready to listen'
                    : 'Speech recognition not available',
                style: TextStyle(
                  color: _isListening ? Colors.red : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) return;

    setState(() => _isListening = true);

    await _speech.listen(
      onResult: (result) {
        setState(() {
          _transcription = result.recognizedWords;
        });
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _isListening = false);
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }
}
