import SwiftUI

struct SettingsView: View {
    let speeds: [String]
    let frameRates: [Int]
    @State var speed: String
    @State var frameRate: Int
    let onSpeed: (String) -> Void
    let onFrameRate: (Int) -> Void
    private static let labelWidth: CGFloat = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("> SETTINGS").font(Retro.title)
            row("SPEED", speeds, chosen: speed, name: { $0.uppercased() }) {
                speed = $0
                onSpeed($0)
            }
            row("FRAME RATE", frameRates, chosen: frameRate, name: { "\($0) FPS" }) {
                frameRate = $0
                onFrameRate($0)
            }
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("QUIT").font(Retro.body).foregroundStyle(Retro.dim)
            }
            .buttonStyle(.plain)
        }
        .padding(EdgeInsets(top: 34, leading: 22, bottom: 20, trailing: 22))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Retro.screen)
        .overlay(CRTOverlay())
        .foregroundStyle(Retro.phosphor)
    }

    private func row<Choice: Hashable>(_ label: String, _ choices: [Choice], chosen: Choice, name: @escaping (Choice) -> String, pick: @escaping (Choice) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label).font(Retro.body).foregroundStyle(Retro.dim).frame(width: Self.labelWidth, alignment: .leading)
            ForEach(choices, id: \.self) { choice in
                Button {
                    pick(choice)
                } label: {
                    Text(name(choice))
                        .font(Retro.body)
                        .foregroundStyle(choice == chosen ? Retro.screen : Retro.phosphor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(choice == chosen ? Retro.phosphor : .clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
