import SwiftUI

struct DeployView: View {
    @EnvironmentObject private var appState: OpenClawAppState

    var body: some View {
        NavigationStack {
            Form {
                Section("Deployment Status") {
                    Text(appState.statusText)
                        .font(.subheadline)
                    Text(appState.deploymentState.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Credentials") {
                    SecureField("Discord Bot Token", text: $appState.discordBotToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Discord Channel ID", text: $appState.discordChannelID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("OpenAI API Key", text: $appState.openAIAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Agent Personality") {
                    TextEditor(text: $appState.personality)
                        .frame(minHeight: 120)
                }

                Section {
                    Button("Deploy Agent") {
                        Task {
                            await appState.deploy()
                        }
                    }
                    .disabled(appState.deploymentState == .starting || appState.deploymentState == .running)

                    Button("Stop Deployment", role: .destructive) {
                        Task {
                            await appState.stopDeployment()
                        }
                    }
                    .disabled(appState.deploymentState == .stopped || appState.deploymentState == .stopping)
                }
            }
            .navigationTitle("Deploy")
        }
    }
}

#Preview {
    DeployView()
        .environmentObject(OpenClawAppState())
}
