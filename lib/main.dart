import 'package:flutter/material.dart';

void main() {
  runApp(const LiveTranslateApp());
}

class LiveTranslateApp extends StatelessWidget {
  const LiveTranslateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Translate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _AppColors.background,
        colorScheme: const ColorScheme.dark(
          primary: _AppColors.teal,
          secondary: _AppColors.blue,
          surface: _AppColors.surface,
        ),
      ),
      home: const LocalSetupScreen(),
    );
  }
}

class LocalSetupScreen extends StatelessWidget {
  const LocalSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: const Padding(
                  padding: EdgeInsets.fromLTRB(24, 32, 24, 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _HeroBlock(),
                      _StartupActions(),
                      _FooterBadges(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      children: [
        const SizedBox(height: 36),
        const _WaveLogo(),
        const SizedBox(height: 28),
        Text(
          'Live Translate',
          textAlign: TextAlign.center,
          style: textTheme.displaySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Live conversation translation for meetings and face-to-face moments',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium?.copyWith(
            color: _AppColors.mutedText,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 44),
        const _AudioWavePanel(),
      ],
    );
  }
}

class _WaveLogo extends StatelessWidget {
  const _WaveLogo();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Live Translate audio wave logo',
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _AppColors.teal.withValues(alpha: 0.14),
          border: Border.all(color: _AppColors.teal.withValues(alpha: 0.55)),
        ),
        child: const Icon(
          Icons.graphic_eq_rounded,
          color: _AppColors.teal,
          size: 42,
        ),
      ),
    );
  }
}

class _AudioWavePanel extends StatelessWidget {
  const _AudioWavePanel();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Teal audio wave illustration',
      child: Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              _AppColors.teal.withValues(alpha: 0.04),
              _AppColors.teal.withValues(alpha: 0.22),
              _AppColors.blue.withValues(alpha: 0.08),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: const Center(
          child: Icon(
            Icons.multitrack_audio_rounded,
            color: _AppColors.teal,
            size: 64,
          ),
        ),
      ),
    );
  }
}

class _StartupActions extends StatelessWidget {
  const _StartupActions();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StartupActionButton(
          key: const Key('startNewMeetingButton'),
          label: 'Start new meeting',
          icon: Icons.add_circle_outline_rounded,
          isPrimary: true,
          onPressed: () {},
        ),
        const SizedBox(height: 14),
        _StartupActionButton(
          key: const Key('openMeetingHistoryButton'),
          label: 'Open meeting history',
          icon: Icons.history_rounded,
          onPressed: () {},
        ),
        const SizedBox(height: 26),
        const _PrivacyNote(),
      ],
    );
  }
}

class _StartupActionButton extends StatelessWidget {
  const _StartupActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.isPrimary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isPrimary ? _AppColors.teal : _AppColors.surface;
    final foregroundColor = isPrimary ? _AppColors.background : Colors.white;

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isPrimary
                  ? _AppColors.teal
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 26),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: foregroundColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 28),
          ],
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Privacy note',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, color: _AppColors.teal),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              'Transcripts are stored on device only. Your conversations stay private.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: _AppColors.mutedText,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterBadges extends StatelessWidget {
  const _FooterBadges();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const _FooterBadge(
            icon: Icons.shield_outlined,
            label: 'Secure & Private',
          ),
          Container(
            height: 24,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            color: Colors.white.withValues(alpha: 0.16),
          ),
          const _FooterBadge(icon: Icons.android_rounded, label: 'Android MVP'),
        ],
      ),
    );
  }
}

class _FooterBadge extends StatelessWidget {
  const _FooterBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _AppColors.mutedText, size: 18),
        const SizedBox(width: 8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: _AppColors.mutedText),
        ),
      ],
    );
  }
}

abstract final class _AppColors {
  static const background = Color(0xFF041421);
  static const surface = Color(0xFF0A2134);
  static const teal = Color(0xFF20D6C9);
  static const blue = Color(0xFF1B8FEF);
  static const mutedText = Color(0xFFB3C2D3);
}
