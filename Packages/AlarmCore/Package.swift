// swift-tools-version: 6.2
import PackageDescription

// The app's logic, with no Apple-only framework in it: the API, the pairing
// link, what to schedule and what to cancel, and the acknowledgements that
// wait for a connection. It builds and tests on Linux in the Swift image
// (`make test`) and on macOS in CI. AlarmKit and the Keychain stay in the
// app target, behind the protocols in Ports.swift.
let package = Package(
    name: "AlarmCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "AlarmCore", targets: ["AlarmCore"])
    ],
    dependencies: [
        // SHA-256 for alarm ids on Linux. Apple platforms use CryptoKit.
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "AlarmCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
            ]
        ),
        .testTarget(name: "AlarmCoreTests", dependencies: ["AlarmCore"])
    ],
    swiftLanguageModes: [.v6]
)
