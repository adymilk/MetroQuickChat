# MetroQuickChat - Production Architecture

## System Overview

MetroQuickChat is a production-ready, scalable Bluetooth social channel system supporting **20+ users per logical channel** using:

1. **Sub-channel Auto Sharding** - Max 6 users per physical BLE channel
2. **BLE Mesh Routing** - Multi-hop message forwarding with TTL and deduplication
3. **Wi-Fi Direct Fallback** - MultipeerConnectivity for large files (>2MB)

## Architecture Components

### 1. Sub-channel Sharding System

#### Logical Channels
- A **Logical Channel** represents the user-facing channel (e.g., "早八吐槽大会")
- Each logical channel can have multiple **Sub-channels** (e.g., "早八吐槽大会-2", "早八吐槽大会-3")
- Each sub-channel supports up to 6 concurrent users

#### Auto-creation Logic
```swift
// When joining a channel:
1. Find least populated sub-channel
2. If all full (or none exist), create new sub-channel
3. User joins least populated sub-channel
4. Broadcast all sub-channels in advertising data
```

#### Files
- `Models/SubChannel.swift` - Sub-channel data model
- `Services/EnhancedChannelManager.swift` - Sharding logic

### 2. BLE Mesh Routing

#### Routing Table
- Each device maintains a routing table: `{peerId: UUID, hop: Int, lastSeen: Date}`
- Direct neighbors have `hop = 1`
- Routes are updated every 5 seconds via sync protocol

#### Message Format
```json
{
  "msgId": "uuid",
  "ttl": 3,
  "hops": ["uuid1", "uuid2"],
  "payload": "..."
}
```

#### Flooding with Deduplication
- Messages include `msgId` for deduplication
- Each peer maintains a `seenMessages` cache (TTL: 60s)
- Messages are forwarded only if:
  - Not seen before
  - TTL > 0
  - Not already forwarded by this peer

#### Files
- `Models/RoutingTable.swift` - Routing table management
- `Services/MeshRoutingManager.swift` - Message forwarding logic

### 3. Wi-Fi Direct Acceleration

#### MultipeerConnectivity Integration
- After BLE connection, negotiate Wi-Fi P2P via MultipeerConnectivity
- Files > 2MB automatically switch to Wi-Fi/TCP
- Fallback to BLE chunking if Wi-Fi fails

#### Transfer Flow
```
1. Check file size
2. If > 2MB and Wi-Fi available → Use TCP socket (port 8080)
3. If Wi-Fi unavailable → Fallback to BLE chunking
4. Small messages (< 2MB) → Use BLE (faster for small data)
```

#### Files
- `Services/WiFiDirectService.swift` - MultipeerConnectivity wrapper

### 4. Unified Message Protocol

#### Message Structure
```json
{
  "type": "text|image|video|voice|join|system|routing_sync",
  "channel": "早八吐槽大会",
  "subChannel": 2,
  "msgId": "uuid",
  "ttl": 3,
  "hops": ["uuid1", "uuid2"],
  "sender": "nickname",
  "payload": "base64 or text",
  "timestamp": 1733212345,
  "duration": 5,  // For voice
  "fileSize": 1024  // For large files
}
```

#### Message Types
- `text` - Text messages
- `image` - Image files
- `video` - Video files (future)
- `voice` - Voice messages
- `join` - User join events
- `system` - System messages
- `routing_sync` - Routing table synchronization
- `subchannel_info` - Sub-channel metadata

#### Files
- `Models/UnifiedMessage.swift` - Protocol implementation

## Integration Guide

### Using EnhancedChannelManager

Replace `ChannelManager` with `EnhancedChannelManager`:

```swift
// Before
let manager = ChannelManager(
    central: BluetoothCentralManager(),
    peripheral: BluetoothPeripheralManager(),
    selfPeer: peer
)

// After
let manager = EnhancedChannelManager(
    central: BluetoothCentralManager(),
    peripheral: BluetoothPeripheralManager(),
    selfPeer: peer
)
```

### Migration Checklist

1. ✅ Replace `ChannelManager` with `EnhancedChannelManager`
2. ✅ Update `ChatViewModel` to use `EnhancedChannelManager`
3. ✅ Update UI to display sub-channel info
4. ✅ Test with 10+ concurrent users
5. ✅ Verify Wi-Fi fallback for large files

## Performance Characteristics

### Sub-channel Sharding
- **Max users per sub-channel**: 6
- **Theoretical max per logical channel**: Unlimited (auto-creates sub-channels)
- **Auto-creation threshold**: When all sub-channels have 6 users

### BLE Mesh Routing
- **Routing table sync interval**: 5 seconds
- **Message TTL**: 3 hops (configurable)
- **Seen message cache TTL**: 60 seconds
- **Routing entry TTL**: 30 seconds

### Wi-Fi Direct
- **Wi-Fi threshold**: 2MB
- **TCP port**: 8080
- **Fallback**: Automatic to BLE if Wi-Fi unavailable

## Testing Strategy

### Unit Tests
- Sub-channel sharding logic
- Routing table merge
- Message deduplication
- Wi-Fi fallback

### Integration Tests
- 20+ users joining same logical channel
- Multi-hop message forwarding
- Large file transfer (>2MB) via Wi-Fi
- BLE fallback when Wi-Fi fails

### Performance Tests
- Message latency across hops
- Sub-channel creation under load
- Routing table sync overhead

## Future Enhancements

1. **Video support** - Full video streaming via Wi-Fi Direct
2. **Sub-channel balancing** - Auto-rebalance users across sub-channels
3. **Routing optimization** - AODV-like routing instead of flooding
4. **Encryption** - End-to-end encryption for messages
5. **Offline sync** - Sync missed messages on reconnect

## Troubleshooting

### Messages not forwarding
- Check routing table has direct neighbors (`routingTable.directNeighbors`)
- Verify TTL > 0
- Check seen message cache not blocking

### Sub-channels not created
- Verify `maxUsersPerSubChannel = 6` limit
- Check `createSubChannel` logic
- Ensure advertising includes sub-channel info

### Wi-Fi not connecting
- Check MultipeerConnectivity permissions
- Verify devices on same network (for Wi-Fi Direct)
- Check TCP listener is running on port 8080

