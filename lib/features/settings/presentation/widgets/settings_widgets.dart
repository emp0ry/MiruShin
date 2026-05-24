import 'package:flutter/material.dart';

import '../../../../app/localization/app_localizations.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/widgets/glass_card.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
    super.key,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  context.t(title),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ...children,
        ],
      ),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    this.subtitle,
    this.trailing,
    this.fullWidthTrailing = false,
    this.labelFlex = 1,
    this.trailingFlex = 1,
    this.stackBreakpoint = 560,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final bool fullWidthTrailing;
  final int labelFlex;
  final int trailingFlex;
  final double stackBreakpoint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget label = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.t(title),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.t(subtitle!),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          );

          if (trailing == null) {
            return label;
          }

          if (fullWidthTrailing || constraints.maxWidth < stackBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                label,
                const SizedBox(height: AppSpacing.md),
                trailing!,
              ],
            );
          }

          return Row(
            children: <Widget>[
              Expanded(flex: labelFlex, child: label),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                flex: trailingFlex,
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          );
        },
      ),
    );
  }
}
