import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum MediaDropHandler {
    static let typeIdentifiers = [
        UTType.fileURL.identifier,
        UTType.image.identifier,
        UTType.movie.identifier
    ]

    @MainActor
    static func importProviders(_ providers: [NSItemProvider], into model: AppModel) -> Bool {
        let supported = providers.filter { provider in
            typeIdentifiers.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }
        guard !supported.isEmpty else { return false }

        for provider in supported {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                importFileURL(from: provider, into: model)
            } else if let typeIdentifier = mediaTypeIdentifier(for: provider) {
                importMediaData(from: provider, typeIdentifier: typeIdentifier, into: model)
            }
        }
        return true
    }

    static func fileURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let text = item as? String {
            return text.hasPrefix("/") ? URL(fileURLWithPath: text) : URL(string: text)
        }
        guard let data = item as? Data ?? (item as? NSData).map({ $0 as Data }) else { return nil }
        return URL(dataRepresentation: data, relativeTo: nil)
            ?? String(data: data, encoding: .utf8).flatMap(URL.init(string:))
    }

    @MainActor
    private static func importFileURL(from provider: NSItemProvider, into model: AppModel) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard let url = fileURL(from: item) else {
                Task { @MainActor in
                    model.statusMessage = error?.localizedDescription ?? "The dropped file could not be opened."
                }
                return
            }
            Task { @MainActor in model.addURLs([url]) }
        }
    }

    private static func mediaTypeIdentifier(for provider: NSItemProvider) -> String? {
        provider.registeredTypeIdentifiers.first { identifier in
            guard let type = UTType(identifier) else { return false }
            return type.conforms(to: .image) || type.conforms(to: .movie)
        }
    }

    @MainActor
    private static func importMediaData(
        from provider: NSItemProvider,
        typeIdentifier: String,
        into model: AppModel
    ) {
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
            guard let data else {
                Task { @MainActor in
                    model.statusMessage = error?.localizedDescription ?? "The dropped media could not be opened."
                }
                return
            }
            Task { @MainActor in model.addDroppedMediaData(data, typeIdentifier: typeIdentifier) }
        }
    }
}

private struct MediaDropTargetModifier: ViewModifier {
    @ObservedObject var model: AppModel

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onDrop(of: MediaDropHandler.typeIdentifiers, isTargeted: $model.dropIsTargeted) { providers in
                MediaDropHandler.importProviders(providers, into: model)
            }
    }
}

extension View {
    func mediaDropTarget(_ model: AppModel) -> some View {
        modifier(MediaDropTargetModifier(model: model))
    }
}
