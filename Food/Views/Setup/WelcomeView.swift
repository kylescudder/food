import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var persistence: PersistenceController
    @State private var householdName = "The Scudders"
    @State private var errorMessage: String?
    @State private var showingJoinHelp = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Welcome")
                        .font(.largeTitle.bold())
                    Text("Plan meals and shop together.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    TextField("Household name", text: $householdName)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.organizationName)

                    Button {
                        createHousehold()
                    } label: {
                        Text("Create Household")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button("Join Shared Household") {
                        showingJoinHelp = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 420)

                Spacer()
            }
            .padding(24)
            .alert("Couldn’t Create Household", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .alert("Join a Household", isPresented: $showingJoinHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Open Kyle’s iCloud invitation from Messages or Mail and tap Accept. The shared household will appear here after CloudKit finishes importing it.")
            }
        }
    }

    private func createHousehold() {
        do {
            _ = try persistence.createHousehold(named: householdName)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
