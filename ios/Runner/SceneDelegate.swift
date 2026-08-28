import Flutter
import UIKit

/// Root Flutter controller used by the iOS app.
///
/// Keeping the home indicator auto-hidden at the controller level makes the
/// behavior survive Flutter route changes (including auto-next episode
/// transitions) instead of relying only on transient SystemChrome requests.
@objc(MiruShinFlutterViewController)
final class MiruShinFlutterViewController: FlutterViewController {
  override var prefersHomeIndicatorAutoHidden: Bool { true }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    setNeedsUpdateOfHomeIndicatorAutoHidden()
  }

  override func viewWillTransition(
    to size: CGSize,
    with coordinator: UIViewControllerTransitionCoordinator
  ) {
    super.viewWillTransition(to: size, with: coordinator)
    coordinator.animate(alongsideTransition: nil) { [weak self] _ in
      self?.setNeedsUpdateOfHomeIndicatorAutoHidden()
    }
  }
}

class SceneDelegate: FlutterSceneDelegate {

}
