import 'package:flutter/services.dart';

import '../storage/local_storage_models.dart';
import '../ui/live_translate_models.dart';

class MeetingExportDocument {
  const MeetingExportDocument({
    required this.type,
    required this.subject,
    required this.body,
    required this.recipients,
  });

  final ExportType type;
  final String subject;
  final String body;
  final List<String> recipients;

  Map<String, Object?> toMethodArguments() {
    return {
      'type': type.name,
      'subject': subject,
      'body': body,
      'recipients': recipients,
    };
  }
}

enum NativeShareResult { launched, unavailable }

abstract interface class NativeShareGateway {
  Future<NativeShareResult> shareMeetingExport(MeetingExportDocument document);
}

class MethodChannelNativeShareGateway implements NativeShareGateway {
  const MethodChannelNativeShareGateway({
    this.channel = const MethodChannel(
      'realtime_translate_mobile/native_share',
    ),
  });

  final MethodChannel channel;

  @override
  Future<NativeShareResult> shareMeetingExport(
    MeetingExportDocument document,
  ) async {
    final result = await channel.invokeMethod<String>(
      'shareMeetingExport',
      document.toMethodArguments(),
    );
    return switch (result) {
      'launched' => NativeShareResult.launched,
      _ => NativeShareResult.unavailable,
    };
  }
}

class SummaryExportUnavailableException implements Exception {
  const SummaryExportUnavailableException();
}

abstract final class LocalMeetingExportComposer {
  static MeetingExportDocument compose({
    required StoredMeeting meeting,
    required ExportType type,
    required List<String> recipients,
  }) {
    if (type != ExportType.transcript) {
      throw const SummaryExportUnavailableException();
    }

    return MeetingExportDocument(
      type: type,
      subject: 'Live Translate - ${meeting.title}',
      body: _transcriptBody(meeting),
      recipients: recipients,
    );
  }

  static String _transcriptBody(StoredMeeting meeting) {
    final lines = <String>[
      meeting.title,
      'Route: ${meeting.sourceLanguageLabel} -> ${meeting.targetLanguageLabel}',
      'Created: ${_timeLabel(meeting.createdAt)}',
      'Last activity: ${_timeLabel(meeting.updatedAt)}',
      '',
      'Transcript',
      '',
    ];

    if (meeting.transcriptEntries.isEmpty) {
      lines.add('No transcript lines are stored for this meeting yet.');
    } else {
      for (final entry in meeting.transcriptEntries) {
        lines
          ..add('[${_timeLabel(entry.timestamp)}] ${entry.languageCode}')
          ..add('Original: ${entry.originalText}')
          ..add('Translation: ${entry.translatedText}');
        if (entry.speakerLabel != null && entry.speakerLabel!.isNotEmpty) {
          lines.add('Speaker: ${entry.speakerLabel}');
        }
        lines.add('');
      }
    }

    lines.add(
      'Prepared locally on this device. Review before sending from your chosen mail or share app.',
    );
    return lines.join('\n');
  }

  static String _timeLabel(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}
