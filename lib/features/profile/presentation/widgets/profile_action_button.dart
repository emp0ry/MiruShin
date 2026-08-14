import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_radius.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/glass_card.dart';

class ProfileActionButton extends StatelessWidget {
  const ProfileActionButton({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.compact = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      child: GlassCard(
        onTap: onTap,
        radius: AppRadius.xl,
        padding: compact
            ? const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              )
            : const EdgeInsets.all(AppSpacing.lg),
        child: compact
            ? Row(
                children: <Widget>[
                  _ActionIcon(icon: icon, color: primary, compact: true),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: _ActionCopy(
                      title: title,
                      subtitle: subtitle,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.48),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _ActionIcon(icon: icon, color: primary),
                  const SizedBox(height: AppSpacing.xs),
                  Flexible(
                    child: _ActionCopy(title: title, subtitle: subtitle),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.color,
    this.compact = false,
  });

  final IconData icon;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double size = compact ? 42 : 44;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadius.all(compact ? AppRadius.md : AppRadius.lg),
      ),
      child: Icon(icon, size: compact ? 21 : 24, color: color),
    );
  }
}

class _ActionCopy extends StatelessWidget {
  const _ActionCopy({
    required this.title,
    required this.subtitle,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final Widget subtitleText = Text(
      context.t(subtitle),
      maxLines: compact ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
      ),
    );
    return Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          context.t(title),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (compact) subtitleText else Flexible(child: subtitleText),
      ],
    );
  }
}
