# 蓝牙调试故障排除指南

## "XPC connection invalid" 错误

### 问题原因

"XPC connection invalid" 错误通常由以下原因引起：

1. **队列配置问题**：`CBCentralManager` 或 `CBPeripheralManager` 初始化时使用 `queue: nil` 可能导致 XPC 连接失败
2. **蓝牙权限未授予**：应用未获得蓝牙权限
3. **蓝牙状态未知**：蓝牙正在初始化中（状态为 `.unknown`）
4. **真机调试配置**：Info.plist 配置不完整

### 已实施的修复

1. ✅ **队列修复**：
   - 将 `CBCentralManager(delegate: self, queue: nil)` 改为 `queue: .main`
   - 将 `CBPeripheralManager(delegate: self, queue: nil)` 改为 `queue: .main`

2. ✅ **状态检查增强**：
   - 添加了详细的蓝牙状态日志
   - 添加了等待蓝牙初始化的逻辑（状态为 `.unknown` 时延迟重试）

3. ✅ **错误日志**：
   - 更清晰的中文状态描述
   - 包含 rawValue 便于调试

### 解决步骤

#### 1. 检查蓝牙权限

在真机上：
- 打开 **设置 → 隐私与安全性 → 蓝牙**
- 确保你的应用有蓝牙权限
- 如果未显示，删除应用重新安装

#### 2. 检查 Info.plist 配置

确保 `Info.plist` 包含：
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>用于发现附近用户并进行频道聊天。</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>用于广播频道并接收消息通知。</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>用于蓝牙相关功能的更好体验。</string>
```

#### 3. 检查蓝牙状态

在 Xcode 控制台查看日志：
- `状态更新 - 未知`：蓝牙正在初始化，等待几秒
- `状态更新 - 未授权`：需要在设置中授予权限
- `状态更新 - 已关闭`：需要在系统设置中开启蓝牙
- `状态更新 - 已开启`：蓝牙正常工作

#### 4. 真机调试检查清单

- [ ] 蓝牙已开启（系统设置）
- [ ] 应用已获得蓝牙权限
- [ ] Info.plist 包含所有必要的权限描述
- [ ] Xcode 签名配置正确
- [ ] 设备已解锁且信任此电脑

### 蓝牙状态代码

| rawValue | 状态 | 含义 | 解决方法 |
|----------|------|------|----------|
| 0 | unknown | 正在初始化 | 等待几秒后重试 |
| 1 | resetting | 重置中 | 等待完成 |
| 2 | unsupported | 不支持 | 设备不支持 BLE |
| 3 | unauthorized | 未授权 | 在设置中授予权限 |
| 4 | poweredOff | 已关闭 | 在系统设置中开启蓝牙 |
| 5 | poweredOn | 已开启 | ✅ 正常工作 |

### 调试建议

1. **查看详细日志**：
   ```
   BluetoothCentralManager: 状态更新 - 未知 (rawValue: 0)
   BluetoothCentralManager: 蓝牙状态未知，等待初始化完成...
   ```

2. **等待状态更新**：
   - 蓝牙初始化可能需要 1-2 秒
   - 如果一直显示 "未知"，检查权限和 Info.plist

3. **重新安装应用**：
   - 如果权限问题持续，删除应用并重新安装
   - 重新安装时会重新请求权限

### 常见问题

**Q: 为什么状态一直是 0 (unknown)?**
A: 
- 可能是权限未授予
- 可能是 Info.plist 配置缺失
- 等待几秒后应该会更新状态

**Q: XPC connection invalid 一直出现**
A:
- 检查是否使用 `queue: nil`（应使用 `queue: .main`）
- 确保在真机上测试（模拟器可能不支持）
- 检查应用签名和权限

**Q: 蓝牙权限在哪里授予？**
A:
- iOS 设置 → 隐私与安全性 → 蓝牙
- 或在应用首次请求时弹出的权限对话框

### 测试步骤

1. 在真机上运行应用
2. 查看 Xcode 控制台日志
3. 检查蓝牙状态是否变为 `.poweredOn`
4. 如果未授权，进入设置授予权限
5. 重新运行应用测试

