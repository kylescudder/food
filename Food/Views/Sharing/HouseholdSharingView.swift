import CloudKit
import Dispatch
import SwiftUI
import UIKit

struct HouseholdSharingView: UIViewControllerRepresentable {
    @EnvironmentObject private var persistence: PersistenceController
    @ObservedObject var household: Household
    @Binding var errorMessage: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            title: household.name ?? "Shared Household",
            errorMessage: $errorMessage
        )
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller: UICloudSharingController
        let cloudContainer = CKContainer(
            identifier: PersistenceController.cloudKitContainerIdentifier
        )

        if let existingShare = persistence.existingShare(for: household) {
            controller = UICloudSharingController(share: existingShare, container: cloudContainer)
        } else {
            controller = UICloudSharingController { _, completion in
                persistence.container.share([household], to: nil) { _, share, container, error in
                    if let share {
                        share[CKShare.SystemFieldKey.title] = (household.name ?? "Shared Household") as CKRecordValue
                    }
                    completion(share, container, error)
                }
            }
        }

        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String
        private let errorMessage: Binding<String?>

        init(title: String, errorMessage: Binding<String?>) {
            self.title = title
            self.errorMessage = errorMessage
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            let message = error.localizedDescription
            DispatchQueue.main.async {
                self.errorMessage.wrappedValue = message
            }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    }
}

struct HouseholdSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var persistence: PersistenceController
    @ObservedObject var household: Household
    @State private var showingShare = false
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Household") {
                    LabeledContent("Name", value: household.name ?? "Household")
                }

                Section {
                    Button {
                        shareError = nil
                        showingShare = true
                    } label: {
                        Label("Invite or Manage People", systemImage: "person.2.badge.gearshape")
                    }
                    .disabled(!persistence.cloudKitEnabled)
                } footer: {
                    if persistence.cloudKitEnabled {
                        Text("People you invite can plan meals and update the shopping list with you.")
                    } else {
                        Text("Sharing isn’t available in this build.")
                    }
                }
            }
            .navigationTitle("Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingShare) {
                HouseholdSharingView(household: household, errorMessage: $shareError)
                    .environmentObject(persistence)
                    .alert("Couldn’t Share Household", isPresented: Binding(
                        get: { shareError != nil },
                        set: { if !$0 { shareError = nil } }
                    )) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(shareError ?? "Please check iCloud and your connection, then try again.")
                    }
            }
        }
    }
}
