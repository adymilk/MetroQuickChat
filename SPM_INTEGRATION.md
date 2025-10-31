# Swift Package Manager Integration Guide

## Adding Exyte/Chat Library

### Steps:

1. Open your Xcode project
2. Go to **File → Add Package Dependencies...**
3. Enter the package URL: `https://github.com/exyte/Chat`
4. Select version: **2.0.0** or later
5. Click **Add Package**
6. Select the **Chat** library and click **Add Package**

### Alternative: Using Package.swift

If your project uses a `Package.swift` file, add:

```swift
dependencies: [
    .package(url: "https://github.com/exyte/Chat", from: "2.0.0")
]
```

Then add to your target dependencies:

```swift
.target(
    name: "MetroQuickChat",
    dependencies: [
        .product(name: "ExyteChat", package: "Chat")
    ]
)
```

### After Installation

Import in your files:
```swift
import ExyteChat
```

The ChatView implementation is ready to use once the package is added.

