import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if let job = model.selectedJob, let settings = job.settings {
                Form {
                    settingsForm(settings, job: job)
                    if let error = job.errorMessage { Text(error).foregroundColor(.red).font(.caption) }
                }
            } else {
                VStack {
                    Spacer()
                    Text("Select an item").foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func settingsForm(_ settings: OutputSettings, job: MediaJob) -> some View {
        switch settings {
        case .image(let image): ImageSettingsForm(settings: image, sourceSize: job.probe?.dimensions) { model.updateSettings(.image($0), for: job.id) }
        case .svg(let svg): SVGSettingsForm(settings: svg) { model.updateSettings(.svg($0), for: job.id) }
        case .video(let video): VideoSettingsForm(settings: video, sourceSize: job.probe?.dimensions) { model.updateSettings(.video($0), for: job.id) }
        }
    }
}

private struct SVGSettingsForm: View {
    let settings: SVGOutputSettings
    let update: (SVGOutputSettings) -> Void

    var body: some View {
        Section(header: Text("SVG Optimization")) {
            Picker("Optimization", selection: Binding(
                get: { settings.preset },
                set: { update(.defaults(for: $0)) }
            )) {
                ForEach(SVGOptimizationPreset.allCases) { Text($0.localizedTitle).tag($0) }
            }
            HStack {
                Text("Decimal precision")
                Spacer()
                NumericValueField("Decimal precision", value: Binding(
                    get: { settings.decimalPrecision },
                    set: { var copy = settings; copy.decimalPrecision = $0; update(copy) }
                ), range: 0...6)
            }
            Toggle("Multipass optimization", isOn: binding(\.multipass))
            Toggle("Simplify paths", isOn: binding(\.simplifyPaths))
            Toggle("Preserve accessibility text", isOn: binding(\.preserveAccessibility))
            Toggle("Preserve IDs and CSS", isOn: binding(\.preserveIDsAndCSS))
            Toggle("Remove editor metadata", isOn: binding(\.removeMetadata))

            if settings.preset == .aggressive {
                Label("Aggressive optimization can slightly change complex artwork.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
            Text("Scripts, event handlers, foreign objects and external resources are always removed. Processing stays offline.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func binding<T>(_ path: WritableKeyPath<SVGOutputSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: path] }, set: {
            var copy = settings
            copy[keyPath: path] = $0
            update(copy)
        })
    }
}

private extension SVGOptimizationPreset {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .safe: return "Safe"
        case .balanced: return "Balanced"
        case .aggressive: return "Aggressive"
        }
    }
}

private struct ImageSettingsForm: View {
    let settings: ImageOutputSettings
    let sourceSize: CGSize?
    let update: (ImageOutputSettings) -> Void

    var body: some View {
        Section(header: Text("Format")) {
            Picker("Format", selection: binding(\.format)) { ForEach(ImageFormat.allCases) { Text($0.rawValue.uppercased()).tag($0) } }
        }
        qualitySection
        ResizeForm(settings: settings.resize, sourceSize: sourceSize) { var copy = settings; copy.resize = $0; update(copy) }
    }

    private var qualitySection: some View {
        Section(header: Text("Quality")) {
            Picker("Mode", selection: qualityMode) {
                Text("Percentage").tag(QualityMode.percentage)
                Text("Target size").tag(QualityMode.targetSize)
            }
            if settings.targetBytes == nil {
                HStack {
                    Text("Percentage")
                    Slider(value: binding(\.quality), in: 0.35...1)
                    NumericValueField("Percentage", value: qualityPercentage, range: 35...100, unit: "%", width: 42)
                }
            } else if let bytes = settings.targetBytes {
                HStack {
                    Text("Target size")
                    Spacer()
                    NumericValueField("Target size", value: Binding(
                        get: { Int(bytes / 1000) },
                        set: { var copy = settings; copy.targetBytes = Int64($0) * 1000; update(copy) }
                    ), range: 1...1_000_000, unit: "KB", width: 72)
                }
            }
        }
    }

    private var qualityMode: Binding<QualityMode> {
        Binding(
            get: { settings.targetBytes == nil ? .percentage : .targetSize },
            set: { mode in
                var copy = settings
                copy.targetBytes = mode == .targetSize ? (settings.targetBytes ?? 500_000) : nil
                update(copy)
            }
        )
    }

    private var qualityPercentage: Binding<Int> {
        Binding(
            get: { Int((settings.quality * 100).rounded()) },
            set: { var copy = settings; copy.quality = Double($0) / 100; update(copy) }
        )
    }

    private func binding<T>(_ path: WritableKeyPath<ImageOutputSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: path] }, set: { var copy = settings; copy[keyPath: path] = $0; update(copy) })
    }
}

private struct VideoSettingsForm: View {
    let settings: VideoOutputSettings
    let sourceSize: CGSize?
    let update: (VideoOutputSettings) -> Void

    var body: some View {
        Section(header: Text("Format")) {
            Picker("Format", selection: binding(\.codec)) { ForEach(VideoCodec.allCases) { Text($0.title).tag($0) } }
            Toggle("Keep audio", isOn: binding(\.keepAudio))
        }
        Section(header: Text("Quality")) {
            Picker("Mode", selection: qualityMode) {
                Text("Percentage").tag(QualityMode.percentage)
                Text("Target size").tag(QualityMode.targetSize)
            }
            if settings.targetBytes == nil {
                HStack {
                    Text("Percentage")
                    Slider(value: binding(\.quality), in: 0.35...1)
                    NumericValueField("Percentage", value: qualityPercentage, range: 35...100, unit: "%", width: 42)
                }
            } else if let bytes = settings.targetBytes {
                HStack {
                    Text("Target size")
                    Spacer()
                    NumericValueField("Target size", value: Binding(
                        get: { Int(bytes / 1_000_000) },
                        set: { var copy = settings; copy.targetBytes = Int64($0) * 1_000_000; update(copy) }
                    ), range: 1...100_000, unit: "MB", width: 72)
                }
            }
        }
        ResizeForm(settings: settings.resize, sourceSize: sourceSize) { var copy = settings; copy.resize = $0; update(copy) }
    }

    private var qualityMode: Binding<QualityMode> {
        Binding(
            get: { settings.targetBytes == nil ? .percentage : .targetSize },
            set: { mode in
                var copy = settings
                copy.targetBytes = mode == .targetSize ? (settings.targetBytes ?? 20_000_000) : nil
                update(copy)
            }
        )
    }

    private func binding<T>(_ path: WritableKeyPath<VideoOutputSettings, T>) -> Binding<T> {
        Binding(get: { settings[keyPath: path] }, set: { var copy = settings; copy[keyPath: path] = $0; update(copy) })
    }

    private var qualityPercentage: Binding<Int> {
        Binding(
            get: { Int((settings.quality * 100).rounded()) },
            set: { var copy = settings; copy.quality = Double($0) / 100; update(copy) }
        )
    }
}

private struct ResizeForm: View {
    let settings: ResizeSettings
    let sourceSize: CGSize?
    let update: (ResizeSettings) -> Void

    var body: some View {
        Section(header: Text("Size")) {
            Picker("Mode", selection: mode) {
                Text("Percentage").tag(ResizeMode.percentage)
                Text("Dimensions").tag(ResizeMode.dimensions)
            }
            if settings.mode == .percentage {
                HStack {
                    Text("Scale")
                    Spacer()
                    NumericValueField("Scale", value: percentage, range: 1...400, unit: "%", width: 64)
                }
            } else {
                dimensionField("Width", value: dimensionsWidth)
                dimensionField("Height", value: dimensionsHeight)
                Toggle("Retain aspect ratio", isOn: retainAspectRatio)
            }
        }
    }

    private var percentage: Binding<Int> {
        Binding(
            get: { Int(settings.percentage.rounded()) },
            set: { var copy = settings; copy.percentage = Double($0); update(copy) }
        )
    }

    private var mode: Binding<ResizeMode> {
        Binding(
            get: { settings.mode },
            set: { newMode in
                var copy = settings
                copy.mode = newMode
                if newMode == .dimensions, settings.mode != .dimensions, let sourceSize {
                    copy.width = max(1, Int(sourceSize.width.rounded()))
                    copy.height = max(1, Int(sourceSize.height.rounded()))
                }
                update(copy)
            }
        )
    }

    private var dimensionsWidth: Binding<Int> {
        Binding(
            get: { settings.width },
            set: { value in
                var copy = settings
                copy.width = value
                if copy.retainAspectRatio, let ratio = sourceAspectRatio {
                    copy.height = max(1, Int((Double(value) / ratio).rounded()))
                }
                update(copy)
            }
        )
    }

    private var dimensionsHeight: Binding<Int> {
        Binding(
            get: { settings.height },
            set: { value in
                var copy = settings
                copy.height = value
                if copy.retainAspectRatio, let ratio = sourceAspectRatio {
                    copy.width = max(1, Int((Double(value) * ratio).rounded()))
                }
                update(copy)
            }
        )
    }

    private var retainAspectRatio: Binding<Bool> {
        Binding(
            get: { settings.retainAspectRatio },
            set: { value in
                var copy = settings
                copy.retainAspectRatio = value
                if value, let ratio = sourceAspectRatio {
                    copy.height = max(1, Int((Double(copy.width) / ratio).rounded()))
                }
                update(copy)
            }
        )
    }

    private var sourceAspectRatio: Double? {
        guard let sourceSize, sourceSize.width > 0, sourceSize.height > 0 else { return nil }
        return Double(sourceSize.width / sourceSize.height)
    }

    private func dimensionField(_ title: LocalizedStringKey, value: Binding<Int>) -> some View {
        HStack {
            Text(title)
            Spacer()
            NumericValueField(title, value: value, range: 1...32_768, unit: "px", width: 72)
        }
    }
}

private struct NumericValueField: View {
    let label: LocalizedStringKey
    let value: Binding<Int>
    let range: ClosedRange<Int>
    var unit = ""
    var width: CGFloat = 56

    init(
        _ label: LocalizedStringKey,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        unit: String = "",
        width: CGFloat = 56
    ) {
        self.label = label
        self.value = value
        self.range = range
        self.unit = unit
        self.width = width
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, value: clampedValue, formatter: integerFormatter)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: width)
            if !unit.isEmpty {
                Text(unit)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var clampedValue: Binding<Int> {
        Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(range.upperBound, max(range.lowerBound, $0)) }
        )
    }

    private var integerFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.allowsFloats = false
        formatter.usesGroupingSeparator = false
        return formatter
    }
}

private enum QualityMode: Hashable {
    case percentage
    case targetSize
}
