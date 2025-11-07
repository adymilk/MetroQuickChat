import SwiftUI

/// 语音消息视图 - 参考设计图样式
struct VoiceMessageView: View {
    let message: Message
    let isPlaying: Bool
    let progress: Double
    let duration: Int
    let onPlay: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // 左侧：白色播放图标（三角形）- 参考设计图
            Button(action: onPlay) {
                ZStack {
                    // 半透明圆形背景
                    Circle()
                        .fill(Color.white.opacity(0.25))
                        .frame(width: 32, height: 32)
                    
                    // 播放/暂停图标
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .offset(x: isPlaying ? 0 : 1) // 播放图标稍微右移，看起来更居中
                }
            }
            .buttonStyle(.plain)
            
            // 中间：波形可视化 + 时长 - 参考设计图
            VStack(alignment: .leading, spacing: 4) {
                // 波形可视化
                WaveformView(progress: progress, isPlaying: isPlaying)
                    .frame(height: 20)
                
                // 时长显示（格式：0:02）- 参考设计图
                Text(formatDuration(duration))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
            }
            
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 2)
    }
    
    /// 格式化时长（格式：0:02）
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

/// 波形可视化组件 - 参考设计图的波形样式
struct WaveformView: View {
    let progress: Double
    let isPlaying: Bool
    
    // 生成模拟波形数据（更真实的波形效果）
    private var waveformData: [CGFloat] {
        var data: [CGFloat] = []
        let barCount = 35 // 增加条数，更精细
        let baseHeight: CGFloat = 3 // 最小高度
        
        for i in 0..<barCount {
            let position = Double(i) / Double(barCount)
            let isPlayed = position <= progress
            
            // 生成波形高度（使用正弦波模拟）
            let wavePhase = Double(i) * 0.4
            let timePhase = isPlaying ? Date().timeIntervalSince1970 * 3.0 : 0
            let heightVariation = sin(wavePhase + timePhase) * 0.4 + 0.6
            
            // 基础高度范围：3-16
            let maxHeight: CGFloat = 16
            let height = baseHeight + (maxHeight - baseHeight) * CGFloat(heightVariation)
            
            data.append(height)
        }
        return data
    }
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(waveformData.enumerated()), id: \.offset) { index, height in
                let position = Double(index) / Double(waveformData.count)
                let isPlayed = position <= progress
                
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        // 已播放部分：高亮白色，未播放部分：半透明白色
                        Color.white.opacity(isPlayed ? 0.95 : 0.35)
                    )
                    .frame(width: 2.5, height: height)
                    .animation(
                        isPlayed && isPlaying
                            ? .easeInOut(duration: 0.2).repeatForever(autoreverses: true)
                            : .default,
                        value: isPlaying
                    )
            }
        }
        .frame(height: 20)
    }
}

