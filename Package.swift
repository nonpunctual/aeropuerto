// swift-tools-version:5.9
import Foundation
import PackageDescription

let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "aeropuerto",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "aeropuerto",
            exclude: ["Info.plist", "aeropuerto.entitlements"],
            linkerSettings: [
                // Embeds an Info.plist section directly into the Mach-O binary so macOS's TCC
                // daemon can find NSLocationUsageDescription for a bare command-line tool (no
                // .app bundle). Without this, requesting Location Services authorization either
                // silently fails or shows a blank/garbled prompt.
                //
                // Uses an absolute path derived from this manifest's own location rather than a
                // path relative to Sources/aeropuerto/Info.plist, so it resolves correctly no
                // matter what directory `swift build` is invoked from.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "\(packageDirectory)/Sources/aeropuerto/Info.plist",
                ])
            ]
        )
    ]
)
