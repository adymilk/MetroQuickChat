import SwiftUI

struct VoiceMessageView: View {
    let message: Message
    let isPlaying: Bool
    let progress: Double
    let duration: Int
    let onPlay: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.tint)
                    .scaleEffect(isPlaying ? 1.1 : 1.0)
                    .animation(.spring(response: 0.3), value: isPlaying)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                // Waveform visualization (simple progress bar)
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                        
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * progress, height: 4)
                    }
                }
                .frame(height: 20)
                
                Text("\(duration)秒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
}

