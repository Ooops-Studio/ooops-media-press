import Foundation
import JavaScriptCore

protocol SVGProcessing: Sendable {
    func render(source: URL, settings: SVGOutputSettings, destination: URL) async throws -> PreviewArtifact
}

actor SVGProcessor: SVGProcessing {
    func render(source: URL, settings: SVGOutputSettings, destination: URL) async throws -> PreviewArtifact {
        try Task.checkCancellation()
        let input = try String(contentsOf: source, encoding: .utf8)
        let bundleURL = Bundle.module.url(forResource: "svgo.bundle", withExtension: "js", subdirectory: "SVGO")
            ?? Bundle.module.url(forResource: "svgo.bundle", withExtension: "js")
        guard let bundleURL else { throw MediaPressError.toolMissing("SVGO") }
        let script = try String(contentsOf: bundleURL, encoding: .utf8)
        guard let context = JSContext() else { throw MediaPressError.processingFailed("Could not start the SVG optimizer.") }

        var exceptionMessage: String?
        context.exceptionHandler = { _, exception in exceptionMessage = exception?.toString() }
        context.evaluateScript(script)
        if let exceptionMessage { throw MediaPressError.processingFailed(exceptionMessage) }

        let settingsData = try JSONEncoder().encode(settings)
        guard let settingsJSON = String(data: settingsData, encoding: .utf8),
              let namespace = context.objectForKeyedSubscript("OoopsSVGO"),
              let function = namespace.objectForKeyedSubscript("optimize"),
              let responseJSON = function.call(withArguments: [input, settingsJSON])?.toString(),
              let responseData = responseJSON.data(using: .utf8) else {
            throw MediaPressError.processingFailed("SVGO returned no result.")
        }

        let response = try JSONDecoder().decode(SVGOResponse.self, from: responseData)
        if let error = response.error { throw MediaPressError.processingFailed(error) }
        guard let output = response.data, output.contains("<svg") else {
            throw MediaPressError.processingFailed("SVGO returned an invalid SVG document.")
        }
        try Task.checkCancellation()
        try output.write(to: destination, atomically: true, encoding: .utf8)
        return PreviewArtifact(outputURL: destination, byteCount: destination.fileByteCount)
    }
}

private struct SVGOResponse: Decodable {
    let data: String?
    let error: String?
}
