import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/session/spoken_translation_output.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MethodChannel? channel;

  tearDown(() {
    final activeChannel = channel;
    if (activeChannel != null) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(activeChannel, null);
    }
    channel = null;
  });

  test('method channel spoken output sends speak and stop calls', () async {
    channel = const MethodChannel(
      'realtime_translate_mobile/test_spoken_translation_output',
    );
    final calls = <MethodCall>[];
    final speakCompleter = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel!, (call) async {
          calls.add(call);
          if (call.method == 'speak') {
            return speakCompleter.future;
          }
          return;
        });
    final gateway = MethodChannelSpokenTranslationOutputGateway(
      methodChannel: channel!,
    );

    final speakFuture = gateway.speak(
      const SpokenTranslationUtterance(
        id: 'entry-1',
        routeSide: SpokenTranslationRouteSide.source,
        sourceLanguageCode: 'en',
        outputLanguageCode: 'it',
        text: 'Ciao Marco',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(gateway.isSpeaking, isTrue);

    await gateway.stop();
    speakCompleter.complete();
    await speakFuture;

    expect(gateway.isSpeaking, isFalse);
    expect(calls.map((call) => call.method), ['speak', 'stop']);
    final speakArguments = calls.first.arguments as Map<Object?, Object?>;
    expect(speakArguments['utteranceId'], 'entry-1');
    expect(speakArguments['routeSide'], 'source');
    expect(speakArguments['sourceLanguageCode'], 'en');
    expect(speakArguments['outputLanguageCode'], 'it');
    expect(speakArguments['text'], 'Ciao Marco');
  });

  test('method channel spoken output no-ops when native plugin is absent', () async {
    channel = const MethodChannel(
      'realtime_translate_mobile/test_missing_spoken_translation_output',
    );
    final gateway = MethodChannelSpokenTranslationOutputGateway(
      methodChannel: channel!,
    );

    await gateway.speak(
      const SpokenTranslationUtterance(
        id: 'entry-2',
        routeSide: SpokenTranslationRouteSide.target,
        sourceLanguageCode: 'it',
        outputLanguageCode: 'en',
        text: 'Hello',
      ),
    );
    await gateway.stop();

    expect(gateway.isSpeaking, isFalse);
  });
}
