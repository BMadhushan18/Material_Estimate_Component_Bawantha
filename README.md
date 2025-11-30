# material_estimate

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Speech-to-Text (Voice button)

The home screen contains a "Voice" button. When pressed, it will start listening using the platform's speech recognition and display the recognized text in the square container on the home screen in real-time.

Platform permissions
- Android: The app requests RECORD_AUDIO permission. Ensure the permission is allowed in Settings or runtime permission dialog when prompted.
- iOS: Info.plist contains NSMicrophoneUsageDescription. You will be asked for microphone access on first use.

To try it manually, run the app on a physical device or Android/iOS emulator and press the "Voice" button; speak into the microphone and you should see the text update in the square.

