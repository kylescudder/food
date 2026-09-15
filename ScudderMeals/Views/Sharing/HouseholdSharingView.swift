import CloudKit
import SwiftUI
import UIKit

struct HouseholdSharingView: UIViewControllerRepresentable {
    @EnvironmentObject private var persistence: PersistenceController
    @ObservedObject var household: Household

    func makeCoordinator() -> Coordinator {
        Coordinator(title: household.name ?? "Shared Household")
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

        init(title: String) { self.title = title }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(
            _ csc: UICloudSharingController,
            failedToSaveShareWithError error: Error
        ) {
            assertionFailure("Cloud sharing failed: \(error.localizedDescription)")
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Household") {
                    LabeledContent("Name", value: household.name ?? "Household")
                    LabeledContent(
                        "Storage",
                        value: persistence.cloudKitEnabled ? "iCloud + offline" : "Local only"
                    )
                }

                Section {
                    Button {
                        showingShare = true
                    } label: {
                        Label("Share or Manage People", systemImage: "person.2.badge.gearshape")
                    }
                    .disabled(!persistence.cloudKitEnabled)
                } footer: {
                    if persistence.cloudKitEnabled {
                        Text("Invitations use Apple’s iCloud sharing. People you invite can edit this household.")
                    } else {
                        Text("Cloud sharing is disabled while using the -LocalStore launch argument.")
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
                HouseholdSharingView(household: household)
                    .environmentObject(persistence)
            }
        }
    }
}
