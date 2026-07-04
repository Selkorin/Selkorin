import SwiftUI

/// Reusable banner + acknowledgement control shown above network-facing
/// features. Nothing that touches other hosts runs until the operator confirms
/// they own or are authorized to test the network.
struct AuthorizationGateView: View {
    @Binding var authorized: Bool
    let featureName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.orange)
                Text("Authorized use only")
                    .font(.headline)
            }
            Text("""
            \(featureName) touches other devices on the network. Only use it on a \
            network and cameras you own, or that you have explicit written \
            authorization to test. Scanning or connecting to systems you are not \
            authorized to test may be illegal.
            """)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: $authorized) {
                Text("I own this network / I am authorized to test it")
                    .font(.callout.weight(.medium))
            }
            .toggleStyle(.switch)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.4)))
    }
}
