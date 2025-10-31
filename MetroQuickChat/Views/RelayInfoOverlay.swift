import SwiftUI

/// Relay information overlay for chat bubbles
struct RelayInfoOverlay: View {
    let hops: Int
    let latency: TimeInterval?
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.3.trianglepath")
                .font(.caption2)
            
            Text("via \(hops) 跳")
                .font(.caption2)
            
            if let latency = latency {
                Text("· \(Int(latency)) 秒前")
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(0.6))
        .foregroundStyle(.white)
        .cornerRadius(8)
        .padding(4)
    }
}

