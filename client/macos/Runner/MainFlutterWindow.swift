import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Ink floor and a dark title bar, so the window never flashes white
    // and the chrome matches the console. Narrower than the phone layout
    // is not a useful window.
    self.appearance = NSAppearance(named: .darkAqua)
    self.backgroundColor = NSColor(
      srgbRed: 0x16 / 255.0, green: 0x17 / 255.0, blue: 0x1C / 255.0, alpha: 1)
    self.titlebarAppearsTransparent = true
    self.title = "OpenHuman"
    self.minSize = NSSize(width: 380, height: 560)
    if windowFrame.width < 1100 {
      self.setContentSize(NSSize(width: 1280, height: 800))
      self.center()
    }

    super.awakeFromNib()
  }
}
