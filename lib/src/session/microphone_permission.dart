import 'package:flutter/services.dart';

enum MicrophonePermissionStatus {
  unknown,
  granted,
  denied,
  permanentlyDenied,
  restricted,
}

extension MicrophonePermissionStatusLabels on MicrophonePermissionStatus {
  String get methodValue {
    return switch (this) {
      MicrophonePermissionStatus.unknown => 'unknown',
      MicrophonePermissionStatus.granted => 'granted',
      MicrophonePermissionStatus.denied => 'denied',
      MicrophonePermissionStatus.permanentlyDenied => 'permanentlyDenied',
      MicrophonePermissionStatus.restricted => 'restricted',
    };
  }

  bool get isGranted => this == MicrophonePermissionStatus.granted;
}

abstract class MicrophonePermissionGateway {
  Future<MicrophonePermissionStatus> checkStatus();

  Future<MicrophonePermissionStatus> request();

  Future<void> openAppSettings();
}

class MethodChannelMicrophonePermissionGateway
    implements MicrophonePermissionGateway {
  MethodChannelMicrophonePermissionGateway({
    this.channel = const MethodChannel(
      'realtime_translate_mobile/microphone_permission',
    ),
  });

  final MethodChannel channel;

  @override
  Future<MicrophonePermissionStatus> checkStatus() async {
    return _invokeStatus('checkStatus');
  }

  @override
  Future<MicrophonePermissionStatus> request() async {
    return _invokeStatus('request');
  }

  @override
  Future<void> openAppSettings() async {
    await channel.invokeMethod<void>('openAppSettings');
  }

  Future<MicrophonePermissionStatus> _invokeStatus(String method) async {
    try {
      final value = await channel.invokeMethod<String>(method);
      return MicrophonePermissionStatusParser.fromMethodValue(value);
    } on MissingPluginException {
      return MicrophonePermissionStatus.unknown;
    }
  }
}

abstract final class MicrophonePermissionStatusParser {
  static MicrophonePermissionStatus fromMethodValue(String? value) {
    return switch (value) {
      'granted' => MicrophonePermissionStatus.granted,
      'denied' => MicrophonePermissionStatus.denied,
      'permanentlyDenied' => MicrophonePermissionStatus.permanentlyDenied,
      'restricted' => MicrophonePermissionStatus.restricted,
      _ => MicrophonePermissionStatus.unknown,
    };
  }
}
