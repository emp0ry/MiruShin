import 'package:flutter/material.dart';

import '../theme/app_animations.dart';

/// Motion patterns used by app routes.
///
/// Top-level destinations fade through because neither page is conceptually
/// above the other. Drill-in pages move along the horizontal axis to show
/// hierarchy, while immersive content gently fades over the shell.
enum AppPageMotion { fadeThrough, sharedAxis, immersiveFade }

class AppPageTransition extends StatelessWidget {
  const AppPageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.motion,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final AppPageMotion motion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (AppAnimations.reduceMotion(context)) return child;

    return switch (motion) {
      AppPageMotion.fadeThrough => _FadeThroughTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      ),
      AppPageMotion.sharedAxis => _SharedAxisTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      ),
      AppPageMotion.immersiveFade => _ImmersiveFadeTransition(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      ),
    };
  }
}

class _FadeThroughTransition extends StatelessWidget {
  const _FadeThroughTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double> incoming = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.18, 1, curve: AppAnimations.emphasized),
      reverseCurve: const Interval(0, 0.82, curve: AppAnimations.exit),
    );
    final Animation<double> outgoing = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: secondaryAnimation,
        curve: const Interval(0, 0.42, curve: AppAnimations.exit),
        reverseCurve: const Interval(0.58, 1, curve: AppAnimations.emphasized),
      ),
    );

    return FadeTransition(
      opacity: outgoing,
      child: FadeTransition(
        opacity: incoming,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(incoming),
          child: child,
        ),
      ),
    );
  }
}

class _SharedAxisTransition extends StatelessWidget {
  const _SharedAxisTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double> incoming = CurvedAnimation(
      parent: animation,
      curve: AppAnimations.emphasized,
      reverseCurve: AppAnimations.exit,
    );
    final Animation<double> outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppAnimations.standard,
      reverseCurve: AppAnimations.standard,
    );
    final Animation<double> outgoingOpacity = Tween<double>(
      begin: 1,
      end: 0.72,
    ).animate(outgoing);

    return FadeTransition(
      opacity: outgoingOpacity,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.018, 0),
        ).animate(outgoing),
        child: FadeTransition(
          opacity: incoming,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.045, 0),
              end: Offset.zero,
            ).animate(incoming),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ImmersiveFadeTransition extends StatelessWidget {
  const _ImmersiveFadeTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double> incoming = CurvedAnimation(
      parent: animation,
      curve: AppAnimations.emphasized,
      reverseCurve: AppAnimations.exit,
    );
    final Animation<double> outgoing = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: secondaryAnimation, curve: AppAnimations.exit),
    );

    return ColoredBox(
      color: Colors.black,
      child: FadeTransition(
        opacity: outgoing,
        child: FadeTransition(
          opacity: incoming,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.012, end: 1).animate(incoming),
            child: child,
          ),
        ),
      ),
    );
  }
}
