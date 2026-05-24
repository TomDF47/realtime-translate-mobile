import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:realtime_translate_mobile/src/session/translated_audio_playback.dart';

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

  test('method channel playback sends start, PCM16, and stop calls', () async {
    channel = const MethodChannel(
      'realtime_translate_mobile/test_translated_audio_playback',
    );
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel!, (call) async {
          calls.add(call);
          return null;
        });
    final gateway = MethodChannelTranslatedAudioPlaybackGateway(
      methodChannel: channel!,
    );

    await gateway.start(const TranslatedAudioPlaybackConfig.openAiRealtime());
    await gateway.enqueuePcm16(
      TranslatedAudioPcm16Chunk(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        sampleRateHz: 24000,
        channelCount: 1,
      ),
    );
    await gateway.stop(clearQueue: true);

    expect(gateway.isOpen, isFalse);
    expect(calls.map((call) => call.method), ['start', 'enqueuePcm16', 'stop']);
    expect(calls[0].arguments, {'sampleRateHz': 24000, 'channelCount': 1});
    final enqueueArguments = calls[1].arguments as Map<Object?, Object?>;
    expect(enqueueArguments['sampleRateHz'], 24000);
    expect(enqueueArguments['channelCount'], 1);
    expect(List<int>.from(enqueueArguments['bytes']! as Uint8List), [
      1,
      2,
      3,
      4,
    ]);
    expect(calls[2].arguments, {'clearQueue': true});
  });

  test('method channel playback no-ops when native plugin is absent', () async {
    channel = const MethodChannel(
      'realtime_translate_mobile/test_missing_translated_audio_playback',
    );
    final gateway = MethodChannelTranslatedAudioPlaybackGateway(
      methodChannel: channel!,
    );

    await gateway.start(const TranslatedAudioPlaybackConfig.openAiRealtime());
    await gateway.enqueuePcm16(
      TranslatedAudioPcm16Chunk(
        bytes: Uint8List.fromList([5, 6]),
        sampleRateHz: 24000,
        channelCount: 1,
      ),
    );
    await gateway.stop(clearQueue: true);

    expect(gateway.isOpen, isFalse);
  });

  test('method channel playback rejects enqueue before start', () async {
    channel = const MethodChannel(
      'realtime_translate_mobile/test_closed_translated_audio_playback',
    );
    final gateway = MethodChannelTranslatedAudioPlaybackGateway(
      methodChannel: channel!,
    );

    await expectLater(
      gateway.enqueuePcm16(
        TranslatedAudioPcm16Chunk(
          bytes: Uint8List.fromList([1, 2]),
          sampleRateHz: 24000,
          channelCount: 1,
        ),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
