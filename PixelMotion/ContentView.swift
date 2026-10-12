import SwiftUI
import AppKit
import Combine
import ServiceManagement

// Shared settings

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var isOverlayVisible = true
    @Published var isAnimating = true
    @Published var fps = 30
    @Published var size: Double = 70
    @Published var opacity: Double = 0.9
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var statusMessage = ""

    private init() {}

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            launchAtLogin =
                SMAppService.mainApp.status == .enabled

            statusMessage = launchAtLogin
                ? "Launch at login enabled."
                : "Launch at login disabled."
        } catch {
            launchAtLogin =
                SMAppService.mainApp.status == .enabled

            statusMessage =
                "Login setting failed: \(error.localizedDescription)"
        }
    }
}

// Menu bar settings

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("PixelMotion", systemImage: "checkerboard.rectangle")
                .font(.headline)

            Divider()

            Text("Frame rate")
            Picker("Frame rate", selection: $model.fps) {
                Text("30 FPS").tag(30)
                Text("60 FPS").tag(60)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("Size: \(Int(model.size)) px")
            Slider(value: $model.size, in: 70...200, step: 10)

            Text("Opacity: \(Int(model.opacity * 100))%")
            Slider(value: $model.opacity, in: 0.15...1.0)

            Divider()

            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )

            if !model.statusMessage.isEmpty {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Button("Quit PixelMotion") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 250)
    }
}

// Floating window controller

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        NSApplication.shared.setActivationPolicy(.accessory)

        let model = AppModel.shared
        createPanel(model: model)
        updatePanel()

        subscription = model.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async {
                    self?.updatePanel()
                }
            }
    }

    private func createPanel(model: AppModel) {
        let side = CGFloat(model.size)

        let panel = NSPanel(
            contentRect: NSRect(
                x: 0, y: 0, width: side, height: side
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        panel.contentView = NSHostingView(
            rootView: OverlayView(model: model)
        )

        self.panel = panel
    }

    private func updatePanel() {
        guard let panel else { return }

        let model = AppModel.shared
        let side = CGFloat(model.size)

        guard model.isOverlayVisible else {
            panel.orderOut(nil)
            return
        }

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame

            let origin = NSPoint(
                x: visible.maxX - side - 24,
                y: visible.maxY - side - 20
            )

            panel.setFrame(
                NSRect(
                    origin: origin,
                    size: NSSize(width: side, height: side)
                ),
                display: false
            )
        }

        panel.orderFrontRegardless()
    }
}

//  Animation


struct OverlayView: View {
    @ObservedObject var model: AppModel

    private let amber = Color(
        red: 0.79,
        green: 0.59,
        blue: 0.34
    )

    private struct Node {
        let x: CGFloat
        let y: CGFloat
        let phase: Double
        let speed: Double
        let radius: CGFloat
    }

    // Fixed node positions give the network a stable identity.
    private let nodes: [Node] = [
        Node(x: 0.12, y: 0.28, phase: 0.2, speed: 0.65, radius: 1.5),
        Node(x: 0.30, y: 0.16, phase: 1.4, speed: 0.48, radius: 2.0),
        Node(x: 0.48, y: 0.34, phase: 2.1, speed: 0.55, radius: 1.6),
        Node(x: 0.72, y: 0.18, phase: 0.8, speed: 0.42, radius: 1.8),
        Node(x: 0.88, y: 0.38, phase: 2.7, speed: 0.60, radius: 1.4),
        Node(x: 0.18, y: 0.65, phase: 1.1, speed: 0.52, radius: 1.8),
        Node(x: 0.40, y: 0.80, phase: 2.5, speed: 0.45, radius: 1.5),
        Node(x: 0.63, y: 0.62, phase: 0.4, speed: 0.58, radius: 2.0),
        Node(x: 0.84, y: 0.80, phase: 1.8, speed: 0.50, radius: 1.6)
    ]

    private let connections: [(Int, Int)] = [
        (0, 1), (0, 5),
        (1, 2), (1, 5),
        (2, 3), (2, 5), (2, 6), (2, 7),
        (3, 4), (3, 7),
        (4, 7), (4, 8),
        (5, 6),
        (6, 7), (6, 8),
        (7, 8)
    ]

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / Double(max(model.fps, 1)),
                paused: !model.isAnimating
            )
        ) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                drawNetwork(
                    context: &context,
                    size: size,
                    time: time
                )
            }
            .opacity(model.opacity)
        }
        .frame(
            width: CGFloat(model.size),
            height: CGFloat(model.size)
        )
        .background(.clear)
    }

    private func drawNetwork(
        context: inout GraphicsContext,
        size: CGSize,
        time: Double
    ) {
        guard size.width > 0, size.height > 0 else {
            return
        }

        let inset = min(size.width, size.height) * 0.08

        let usableWidth = max(0, size.width - inset * 2)
        let usableHeight = max(0, size.height - inset * 2)

        // Calculate slowly drifting node positions.
        var positions: [CGPoint] = []
        positions.reserveCapacity(nodes.count)

        for node in nodes {
            let driftX = sin(time * node.speed + node.phase) * 3.0
            let driftY = cos(time * node.speed * 0.8 + node.phase) * 3.0

            let x = inset
                + usableWidth * node.x
                + CGFloat(driftX)

            let y = inset
                + usableHeight * node.y
                + CGFloat(driftY)

            positions.append(CGPoint(x: x, y: y))
        }

        // Draw fine connections between nearby network nodes.
        var lines = Path()

        for connection in connections {
            let start = positions[connection.0]
            let end = positions[connection.1]

            lines.move(to: start)
            lines.addLine(to: end)
        }

        context.stroke(
            lines,
            with: .color(amber.opacity(0.32)),
            lineWidth: 0.7
        )

        // Draw small, crisp points.
        for (index, node) in nodes.enumerated() {
            let point = positions[index]

            let pulse = 0.78 + 0.22 * sin(
                time * 0.9 + node.phase
            )

            let radius = node.radius * CGFloat(pulse)

            let dot = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )

            context.fill(
                Path(ellipseIn: dot),
                with: .color(amber.opacity(0.85))
            )
        }
    }
}
