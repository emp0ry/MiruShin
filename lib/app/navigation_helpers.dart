import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

void goBackOrGo(BuildContext context, String fallbackLocation) {
  unawaited(_goBackOrGo(context, fallbackLocation));
}

Future<void> _goBackOrGo(
  BuildContext context,
  String fallbackLocation,
) async {
  final NavigatorState navigator = Navigator.of(context);
  if (await navigator.maybePop()) {
    return;
  }
  if (!context.mounted) return;

  final GoRouter router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
    return;
  }
  context.go(fallbackLocation);
}
