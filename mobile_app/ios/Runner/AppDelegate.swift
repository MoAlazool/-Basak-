import Flutter
import LocalAuthentication
import PassKit
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let walletPasses = WalletPassPresenter()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Vote reminders (flutter_local_notifications) also show while the app is open.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Student Wallet card: the app receives an already signed .pkpass from the
    // server and only asks iOS to show its "add this pass" sheet.
    let channel = FlutterMethodChannel(
      name: "basak/wallet", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { [walletPasses] call, result in
      walletPasses.handle(call, result: result)
    }
    engineBridge.pluginRegistry.registrar(forPlugin: "BasakWallet")?
      .register(AddPassButtonFactory(), withId: "basak/add_pass_button")

    // Signing in with Face ID / Touch ID: the system's own state of what is
    // enrolled. It is different once a face or a finger is added or removed,
    // and the app then drops its stored sign-in (lib/.../biometric_device.dart).
    let biometrics = FlutterMethodChannel(
      name: "basak/biometrics", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    biometrics.setMethodCallHandler { call, result in
      switch call.method {
      case "enrollmentMark":
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error),
          let state = context.evaluatedPolicyDomainState
        {
          result(state.base64EncodedString())
        } else {
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Notifications: the unread count on the app icon, and the way to this
    // app's page in Settings when notifications were switched off there.
    let notifications = FlutterMethodChannel(
      name: "basak/notifications", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    notifications.setMethodCallHandler { call, result in
      switch call.method {
      case "setBadge":
        let count = max(0, call.arguments as? Int ?? 0)
        if #available(iOS 16.0, *) {
          UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        } else {
          UIApplication.shared.applicationIconBadgeNumber = count
        }
        result(nil)
      case "openSettings", "openAppSettings":
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return result(false) }
        UIApplication.shared.open(url) { opened in result(opened) }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Presents PKAddPassesViewController for a pass and reports "added" or "cancelled".
final class WalletPassPresenter: NSObject, PKAddPassesViewControllerDelegate {
  private var pending: FlutterResult?
  private var pass: PKPass?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "addPass" else { return result(FlutterMethodNotImplemented) }
    guard let data = (call.arguments as? FlutterStandardTypedData)?.data else {
      return result(FlutterError(code: "invalid_pass", message: "No pass data.", details: nil))
    }
    guard pending == nil else {
      return result(FlutterError(code: "busy", message: "A pass is already being added.", details: nil))
    }
    guard PKAddPassesViewController.canAddPasses() else {
      return result(FlutterError(code: "unavailable", message: "This device cannot add passes.", details: nil))
    }
    do {
      let pass = try PKPass(data: data)
      guard let sheet = PKAddPassesViewController(pass: pass), let presenter = Self.topViewController() else {
        return result(FlutterError(code: "unavailable", message: "Cannot present the pass.", details: nil))
      }
      sheet.delegate = self
      self.pass = pass
      pending = result
      presenter.present(sheet, animated: true)
    } catch {
      result(FlutterError(code: "invalid_pass", message: error.localizedDescription, details: nil))
    }
  }

  func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
    controller.dismiss(animated: true) { [weak self] in
      guard let self = self else { return }
      let added = self.pass.map { PKPassLibrary().containsPass($0) } ?? false
      self.pending?(added ? "added" : "cancelled")
      self.pending = nil
      self.pass = nil
    }
  }

  private static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

/// Apple's official "Add to Apple Wallet" button, shown inside the Flutter screen.
final class AddPassButtonFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    return AddPassButtonView(frame: frame)
  }
}

final class AddPassButtonView: NSObject, FlutterPlatformView {
  private let button: PKAddPassButton

  init(frame: CGRect) {
    button = PKAddPassButton(addPassButtonStyle: .black)
    button.frame = frame
    // Taps are handled on the Flutter side, which requests the pass first.
    button.isUserInteractionEnabled = false
  }

  func view() -> UIView { button }
}
