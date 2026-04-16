import SwiftUI

// MARK: - Animation Curves

enum NotchAnimation {
    /// Expand panel: gentle overshoot for liveliness
    static let open = Animation.spring(response: 0.42, dampingFraction: 0.82)
    /// Collapse panel: critically damped, no overshoot (prevents exposing notch edge)
    static let close = Animation.spring(response: 0.38, dampingFraction: 1.0)
    /// Pop notification: quick bounce for completion/approval auto-expand
    static let pop = Animation.spring(response: 0.3, dampingFraction: 0.65)
    /// Micro-interactions: hover state changes, button highlights
    static let micro = Animation.easeOut(duration: 0.12)
}

// MARK: - Blur + Fade Transition

private struct BlurFadeModifier: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .compositingGroup()
            .blur(radius: active ? 2 : 0)
            .opacity(active ? 0.25 : 1)
    }
}

extension AnyTransition {
    /// Blur out + fade — smoother than plain opacity for notch content switches.
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurFadeModifier(active: true),
            identity: BlurFadeModifier(active: false)
        )
    }
}

// MARK: - MorphText — blur morph on text change

/// Text that briefly blurs when its content changes, creating a smooth "morph" effect.
struct MorphText: View {
    let text: String
    var font: Font = .system(size: 12)
    var color: Color = .white
    var lineLimit: Int? = 1

    @State private var displayed: String
    @State private var blur: CGFloat = 0
    @State private var generation = 0

    init(text: String, font: Font = .system(size: 12), color: Color = .white, lineLimit: Int? = 1) {
        self.text = text
        self.font = font
        self.color = color
        self.lineLimit = lineLimit
        _displayed = State(initialValue: text)
    }

    var body: some View {
        Text(displayed)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .blur(radius: blur * 4)
            .opacity(1 - blur * 0.15)
            .compositingGroup()
            .onChange(of: text) { newText in
                guard newText != displayed else { return }
                generation += 1
                let gen = generation
                withAnimation(.easeOut(duration: 0.1)) { blur = 1 }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    guard gen == generation else { return }
                    displayed = newText
                    withAnimation(.easeOut(duration: 0.15)) { blur = 0 }
                }
            }
    }
}

// MARK: - Typing Indicator — scan highlight

/// A label with a moving gradient highlight that conveys "actively working".
struct TypingIndicator: View {
    let fontSize: CGFloat
    var label: String
    var bright: Bool = false
    var color: Color = .white

    @State private var phase: CGFloat = -60

    private var bandWidth: CGFloat { bright ? 80 : 60 }
    private var duration: Double { 2.5 }
    private var endPhase: CGFloat { bright ? 100 : 80 }
    private var startPhase: CGFloat { bright ? -80 : -60 }
    private var baseOpacity: Double { bright ? 0.6 : 0.35 }
    private var peakOpacity: Double { bright ? 0.8 : 0.5 }
    private var midOpacity: Double { bright ? 0.5 : 0.3 }

    var body: some View {
        Text(label)
            .font(.system(size: fontSize, design: .monospaced))
            .foregroundStyle(color.opacity(baseOpacity))
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(midOpacity), location: bright ? 0.35 : 0.4),
                        .init(color: .white.opacity(peakOpacity), location: 0.5),
                        .init(color: .white.opacity(midOpacity), location: bright ? 0.65 : 0.6),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: bandWidth)
                .offset(x: phase)
                .mask(
                    Text(label)
                        .font(.system(size: fontSize, design: .monospaced))
                )
            )
            .onAppear {
                phase = startPhase
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: false)) {
                    phase = endPhase
                }
            }
            .onDisappear { phase = startPhase }
    }
}
