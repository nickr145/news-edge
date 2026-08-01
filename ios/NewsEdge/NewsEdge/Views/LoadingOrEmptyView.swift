import SwiftUI

/// Shared empty/loading state for panels fed by the initial concurrent
/// fetch in TickerScreen — distinguishes "still loading" from "backend
/// returned nothing" instead of flashing the empty message first.
struct LoadingOrEmptyView: View {
    let isLoading: Bool
    let message: String

    var body: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
