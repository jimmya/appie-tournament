import PackageDescription

let package = Package(
    name: "TournamentServer",
    targets: [
        Target(name: "Executable", dependencies: ["App"])
    ],
    dependencies: [
        .Package(url: "https://github.com/vapor/vapor.git", majorVersion: 1, minor: 5),
        .Package(url: "https://github.com/vapor/postgresql-provider.git", majorVersion: 1, minor: 1),
        .Package(url: "https://github.com/vapor/jwt.git", majorVersion: 0, minor: 8),
        .Package(url: "https://github.com/nodes-vapor/flash.git", majorVersion: 0, minor: 1)
    ],
    exclude: [
        "Config",
        "Database",
        "Localization",
        "Public",
        "Resources",
    ]
)
