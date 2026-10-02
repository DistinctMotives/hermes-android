/// The sheet behind Home's global **New** button.
///
/// Presentation only: every decision about which modes exist, which are
/// runnable, and what a drafted chat looks like lives in the pure
/// `lib/core/utils/new_chat_options.dart` helper.
///
/// The one rule this file owns is the roadmap's capability-discovery rule made
/// visible: a mode that cannot run is drawn *disabled with its reason*, never
/// removed from the sheet. A user who cannot start a Project chat should learn
/// why, not wonder where the option went.
///
/// See `docs/ANDROID_DAILY_DRIVER_ROADMAP.md`.
library;

import 'package:flutter/material.dart';

import '../models/hermes_project.dart';
import '../theme/hermes_theme.dart';
import '../utils/new_chat_options.dart';

/// Asks which chat to start. Pops the chosen mode, or null when dismissed.
class NewChatSheet extends StatelessWidget {
  final List<NewChatOption> options;

  const NewChatSheet({required this.options, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HermesSpacing.lg,
              HermesSpacing.lg,
              HermesSpacing.lg,
              HermesSpacing.sm,
            ),
            child: Text(
              'Start something new',
              style: tokens.typography.title.copyWith(color: tokens.onSurface),
            ),
          ),
          for (final option in options)
            ListTile(
              enabled: option.enabled,
              // A disabled row still explains itself, so the reason replaces
              // the description rather than hiding beside it.
              title: Text(option.label),
              subtitle: Text(option.disabledReason ?? option.description),
              leading: Icon(
                option.mode == NewChatMode.quickChat
                    ? Icons.bolt_outlined
                    : Icons.folder_outlined,
              ),
              onTap: option.enabled
                  ? () => Navigator.of(context).pop(option.mode)
                  : null,
            ),
          const SizedBox(height: HermesSpacing.md),
        ],
      ),
    );
  }
}

/// Asks which project a new Project chat belongs to.
///
/// Only shown when the choice is real: a single project carries no decision,
/// so the caller skips this sheet entirely.
class ProjectPickerSheet extends StatelessWidget {
  final List<HermesProject> projects;

  const ProjectPickerSheet({required this.projects, super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = HermesTokens.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              HermesSpacing.lg,
              HermesSpacing.lg,
              HermesSpacing.lg,
              HermesSpacing.sm,
            ),
            child: Text(
              'Which project?',
              style: tokens.typography.title.copyWith(color: tokens.onSurface),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final project in projects)
                  ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(project.name),
                    subtitle: project.workingDirectory == null
                        ? null
                        : Text(
                            project.workingDirectory!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => Navigator.of(context).pop(project),
                  ),
              ],
            ),
          ),
          const SizedBox(height: HermesSpacing.md),
        ],
      ),
    );
  }
}
