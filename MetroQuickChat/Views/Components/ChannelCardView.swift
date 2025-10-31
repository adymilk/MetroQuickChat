import SwiftUI

struct ChannelCardView: View {
    let channel: Channel
    let memberCountText: String
    let isFavorite: Bool
    let onTap: () -> Void
    let onFavoriteToggle: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    HStack(spacing: 6) {
                        Text(channel.name)
                            .font(.headline)
                            .lineLimit(1)
                        
                        // 在线状态指示器
                        if channel.isOnline {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                        } else {
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 6, height: 6)
                        }
                    }
                    Spacer()
                    
                    // 收藏按钮（明显可见）
                    if let onFavoriteToggle = onFavoriteToggle {
                        Button(action: {
                            onFavoriteToggle()
                        }) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 16))
                                .foregroundStyle(isFavorite ? .yellow : .secondary)
                                .symbolEffect(.bounce, value: isFavorite)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 8)
                    }
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                    Text(memberCountText)
                        .font(.caption)
                    Spacer()
                    
                    // 显示离线时间（如果离线）
                    if !channel.isOnline, let lastDiscovered = channel.lastDiscoveredAt {
                        let secondsAgo = Int(Date().timeIntervalSince(lastDiscovered))
                        if secondsAgo < 60 {
                            Text("\(secondsAgo)秒前离线")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else if secondsAgo < 3600 {
                            Text("\(secondsAgo / 60)分钟前离线")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        } else {
                            Text(channel.createdAt, style: .time)
                                .font(.caption2)
                        }
                    } else {
                        Text(channel.createdAt, style: .time)
                            .font(.caption2)
                    }
                }
            }
            .padding(12)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(.separator), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onFavoriteToggle = onFavoriteToggle {
                Button(action: onFavoriteToggle) {
                    Label(isFavorite ? "取消收藏" : "收藏", systemImage: isFavorite ? "star.slash.fill" : "star.fill")
                }
            }
        }
    }
}

struct ChannelCardView_Previews: PreviewProvider {
    static var previews: some View {
        ChannelCardView(
            channel: Channel(name: "晚高峰 2号线 A车厢", hostPeerId: UUID()),
            memberCountText: "12 人",
            isFavorite: false,
            onTap: {},
            onFavoriteToggle: nil
        )
        .padding()
        .preferredColorScheme(.dark)
    }
}


