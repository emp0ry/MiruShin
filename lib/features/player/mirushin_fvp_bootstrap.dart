import 'package:fvp/fvp.dart' as fvp;

/// Register FVP once with MiruShin-friendly defaults.
///
/// Keep this call in main.dart before runApp(). Remove any older duplicate
/// fvp.registerWith(...) calls from the project.
void configureMiruShinFvp() {
  fvp.registerWith();
}
