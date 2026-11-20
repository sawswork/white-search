import SwiftUI

@main
struct WhiteSearchApp: App {
    @StateObject private var model = SearchModel()

    var body: some Scene {
        WindowGroup {
            SearchView()
                .environmentObject(model)
        }
    }
}
