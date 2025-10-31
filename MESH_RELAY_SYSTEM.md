# User-as-Relay Mesh System Documentation

## 概述

生产级用户中继 Mesh 系统，每个用户都作为中继节点，实现更快传输和更长距离覆盖。

## 核心特性

### 1. 节点发现与心跳

- **心跳广播**: 每2秒广播一次，包含：
  - `userId`: 用户ID
  - `channelId`: 频道ID
  - `nickname`: 昵称
  - `hop`: 跳数
  - `battery`: 电池电量 (0-100)
  - `rssi`: 信号强度 (从BLE获取)

- **扫描与发现**: 自动扫描并建立本地中继表

### 2. 动态路由表

```swift
@Published var relays: [RelayNode] = []
```

- **自动更新**: 根据心跳更新跳数和带宽估计
- **自动清理**: 5秒无心跳的节点自动移除
- **智能评分**: 
  ```
  Score = (RSSI × 0.5) + (Battery × 0.3) + (Bandwidth × 0.2)
  ```
- **跳数偏好**: 优先选择 hop < 3 的节点

### 3. 多路径视频传输

- **文件分块**: 100KB 每块
- **路径选择**: 选择 Top K 条路径 (K = min(10, availableRelays))
- **并行传输**: 通过 `writeValue` 发送 `{seq, total, pathId, data}`
- **重组验证**: 去重 + SHA256 校验和

### 4. 智能中继选择

选择算法：
1. 计算每个节点的中继评分
2. 偏好跳数 < 3 的节点
3. 选择评分最高的 K 条路径
4. 轮询分配块到不同路径

### 5. 距离与速度UI

**频道卡片显示**:
```
500 米覆盖 · 50 人在线
10× 速度
```

**聊天气泡**:
```
via 3 跳中继 · 8 秒前
```

## 架构组件

### Models

#### `RelayNode.swift`
- 中继节点模型
- 包含：ID、频道、跳数、电池、RSSI、带宽估计
- 中继评分计算

#### `RelayPath.swift`
- 中继路径模型
- 包含：节点列表、总评分、估计延迟
- 路径带宽计算（瓶颈节点）

#### `HeartbeatAdvertisement.swift`
- 心跳广播协议
- 每2秒发送一次

### Services

#### `MeshRelayManager.swift`
核心管理器，负责：
- 心跳广播和接收
- 路由表维护
- 多路径文件传输
- 统计数据更新

**主要方法**:
```swift
func sendFile(data: Data, fileName: String, mimeType: String)
func getTopPaths(count: Int) -> [RelayPath]
```

#### `FileChunker.swift`
文件分块和重组：
- `chunk()`: 将文件分割成100KB块
- `reassemble()`: 重组块，去重和校验
- `ReassemblyBuffer`: 内存重组缓冲区

### Views

#### `MeshStatusView.swift`
实时网格状态显示：
- 覆盖范围（米）
- 在线人数
- 速度倍数
- 活跃中继路径列表
- 中继节点卡片

#### `RelayInfoOverlay.swift`
聊天气泡中继信息覆盖层：
- 跳数显示
- 延迟显示

## 使用示例

### 初始化 Mesh Relay Manager

```swift
let meshManager = MeshRelayManager(
    selfPeerId: peer.id,
    channelId: channel.id,
    nickname: peer.nickname,
    central: centralManager,
    peripheral: peripheralManager
)
```

### 发送大文件

```swift
meshManager.onFileReceived = { data, fileName, mimeType in
    // 处理接收到的文件
}

meshManager.sendFile(
    data: imageData,
    fileName: "photo.jpg",
    mimeType: "image/jpeg"
)
```

### 显示网格状态

```swift
MeshStatusView(meshManager: meshManager)
```

### 在频道卡片中显示网格统计

```swift
ChannelCardView(...)
    .meshStatsOverlay(stats: meshManager.stats)
```

## 性能特性

| 特性 | 值 |
|------|-----|
| **心跳间隔** | 2秒 |
| **节点超时** | 5秒 |
| **块大小** | 100KB |
| **最大路径数** | 10 |
| **路由更新间隔** | 5秒 |
| **重组超时** | 30秒 |

## 测试策略

### 单元测试
- 中继评分计算
- 文件分块/重组
- 路由表更新
- 路径选择算法

### 集成测试
- 3+ 真实设备测试
- 50节点网络模拟
- 多路径传输验证
- 丢包和重传测试

### 模拟测试

```swift
let mockManager = MockMeshRelayManager()
// 模拟50节点网络
```

## 未来增强

1. **视频流传输**: 支持实时视频流的多路径传输
2. **自适应路径选择**: 根据实时网络状况动态调整
3. **加密传输**: 端到端加密中继消息
4. **负载均衡**: 更智能的块分配策略
5. **故障恢复**: 自动切换到备用路径

## 故障排除

### 节点未发现
- 检查心跳广播是否正常
- 验证频道ID匹配
- 检查BLE权限和状态

### 文件传输失败
- 检查路径选择（至少1条路径）
- 验证块重组超时设置
- 检查校验和错误

### UI不更新
- 确保在主线程更新 `@Published` 属性
- 检查 `MeshRelayManager` 的生命周期

