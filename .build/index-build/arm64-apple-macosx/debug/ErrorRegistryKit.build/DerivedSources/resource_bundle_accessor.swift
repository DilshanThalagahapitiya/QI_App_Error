import Foundation

extension Foundation.Bundle {
    static let module: Bundle = {
        let mainPath = Bundle.main.bundleURL.appendingPathComponent("ErrorRegistryKit_ErrorRegistryKit.bundle").path
        let buildPath = "/Users/dilshanthalagahapitiya/Documents/GitHub/QI_App_Error/.build/index-build/arm64-apple-macosx/debug/ErrorRegistryKit_ErrorRegistryKit.bundle"

        let preferredBundle = Bundle(path: mainPath)

        guard let bundle = preferredBundle ?? Bundle(path: buildPath) else {
            // Users can write a function called fatalError themselves, we should be resilient against that.
            Swift.fatalError("could not load resource bundle: from \(mainPath) or \(buildPath)")
        }

        return bundle
    }()
}