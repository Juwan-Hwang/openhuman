/// System Event Card — displays non-message system events.
///
/// ## Architectural Principle
///
/// System events (session connected, capability updated, errors)
/// are **not chat messages**. They are rendered as lightweight
/// notification cards that are visually distinct from the message
/// timeline.
///
/// These cards appear inline in the timeline but with a different
/// visual style — centered, muted background, no author avatar —
/// so the user can distinguish "system happened" from "someone said something".
library;

import 'package:flutter/material.dart';
import 'package:openhuman_client/app/theme.dart';

/// A compact card that displays a system event.
///
/// Used for:
/// - "Connected" / "Disconnected" state changes
/// - "Agent session started" / "Capability updated"
/// - Error messages from the server
class SystemEventCard extends StatelessWidget {
  const SystemEventCard({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.color,
  });

  /// The event text (e.g., "Connected as hum_demo_alice").
  final String text;

  /// The icon to display.
  final IconData icon;

  /// Override color (e.g., red for errors).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = color ?? theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: effectiveColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  text,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: effectiveColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
