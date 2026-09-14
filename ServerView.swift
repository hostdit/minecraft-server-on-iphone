import Network
import SwiftUI

struct ServerView: View {
    @State private var server = Server()
    @State private var message = ""

    var body: some View {
        NavigationStack {
            List(server.lines) { line in
                Text(line.text)
                    .font(.system(.caption, design: .monospaced))
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", systemImage: "trash") { server.clear() }
                        .disabled(server.lines.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) { controls }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            server.start()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            server.stop()
        }
    }

    private var title: String {
        guard server.isRunning else { return "Stopped" }
        let players = server.playerCount
        return players == 0 ? "Running on :\(Server.port.rawValue)" : "\(players) playing"
    }

    private var controls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("Say something in game", text: $message)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(send)

                Button("Send", systemImage: "paperplane.fill", action: send)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSend)
            }

            HStack(spacing: 12) {
                Circle()
                    .fill(server.isRunning ? .green : .red)
                    .frame(width: 10, height: 10)

                Button(server.isRunning ? "Stop Server" : "Start Server") {
                    if server.isRunning {
                        server.stop()
                    } else {
                        server.start()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(server.isRunning ? .red : .green)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(.bar)
    }

    private var canSend: Bool {
        server.isRunning && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend else { return }
        server.say(message)
        message = ""
    }
}

#Preview {
    ServerView()
}
