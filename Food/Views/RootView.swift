import CoreData
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var persistence: PersistenceController

    var body: some View {
        Group {
            if persistence.loadErrorMessage != nil {
                ContentUnavailableView(
                    "Couldn’t Open Food",
                    systemImage: "externaldrive.badge.exclamationmark",
                    description: Text("Close Food and try again.")
                )
            } else if !persistence.isReady {
                ProgressView("Opening meal planner…")
            } else {
                HouseholdRouterView()
            }
        }
        .alert("Sharing", isPresented: Binding(
            get: { persistence.shareStatusMessage != nil },
            set: { if !$0 { persistence.clearShareStatus() } }
        )) {
            Button("OK", role: .cancel) { persistence.clearShareStatus() }
        } message: {
            Text(persistence.shareStatusMessage ?? "")
        }
    }
}

private struct HouseholdRouterView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Household.createdAt, ascending: true)],
        animation: .default
    ) private var households: FetchedResults<Household>

    var body: some View {
        if let household = households.first {
            MainTabView(household: household)
        } else {
            WelcomeView()
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var persistence: PersistenceController
    @ObservedObject var household: Household

    var body: some View {
        TabView {
            WeekView(household: household)
                .tabItem { Label("Week", systemImage: "calendar") }

            RecipesView(household: household)
                .tabItem { Label("Recipes", systemImage: "book.closed") }

            ShoppingView(household: household)
                .tabItem { Label("Shopping", systemImage: "cart") }
        }
        .onAppear { persistence.ensureSeedData(for: household) }
    }
}
