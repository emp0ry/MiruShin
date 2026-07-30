import 'package:flutter/material.dart';

abstract final class AppGradients {
  static LinearGradient accent(Color accent) => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[accent, accent],
  );
}
