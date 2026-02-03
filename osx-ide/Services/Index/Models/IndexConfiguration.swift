import Foundation

public struct IndexConfiguration: Codable, Sendable {
    public var enabled: Bool
    public var debounceMs: Int
    public var excludePatterns: [String]

    public static let `default` = IndexConfiguration(
        enabled: true,
        debounceMs: 300,
        excludePatterns: [
            "*.generated.*",
            ".git/*",
            ".ide/*",

            "node_modules",
            "bower_components",
            "jspm_packages",
            ".next",
            ".nuxt",
            ".svelte-kit",
            ".astro",
            ".vite",
            ".vercel",
            ".output",
            "dist",
            "build",
            "out",
            "coverage",
            ".nyc_output",
            ".cache",
            ".parcel-cache",
            ".turbo",
            ".webpack",
            ".rollup.cache",

            "Pods",
            "Carthage",
            ".build",
            "DerivedData",

            "vendor",
            "composer.lock",
            ".composer",

            "__pycache__",
            ".pytest_cache",
            ".mypy_cache",
            ".ruff_cache",
            ".venv",
            "venv",
            "env",

            "target",
            ".gradle",
            "buildSrc",
            "bin",
            "obj",
            ".idea",
            ".vscode",
            ".DS_Store"
        ]
    )
}
