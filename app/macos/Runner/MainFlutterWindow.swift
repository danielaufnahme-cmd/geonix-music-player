import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // No visible title bar, like the Linux build: the app draws its own UI
    // edge to edge. The traffic-light buttons stay (top left) and the top
    // strip still drags the window. The title is kept for the Dock, Mission
    // Control and the Window menu.
    self.title = "Music Player"
    self.titleVisibility = .hidden
    self.titlebarAppearsTransparent = true
    self.styleMask.insert(.fullSizeContentView)
    self.backgroundColor = .black

    // The UI is designed for 1000x650 and up; open at 1440x900 when it fits.
    self.contentMinSize = NSSize(width: 1000, height: 650)
    let visible = self.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    let size = NSSize(width: min(1440, visible?.width ?? 1440), height: min(900, visible?.height ?? 900))
    self.setContentSize(size)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
