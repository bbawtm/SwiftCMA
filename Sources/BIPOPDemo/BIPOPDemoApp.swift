import SwiftUI
import AppKit

@main
struct BIPOPDemoApp: App {
	init() {
		// SPM executables aren't proper .app bundles, so the app starts as a
		// background process. Activate it so the window appears and gets focus.
		NSApplication.shared.setActivationPolicy(.regular)
		NSApplication.shared.activate(ignoringOtherApps: true)
	}

	var body: some Scene {
		WindowGroup("BIPOP-CMA-ES Demo") {
			ContentView()
				.frame(minWidth: 700, minHeight: 600)
		}
		.defaultSize(width: 800, height: 900)
	}
}
