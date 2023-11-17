import Combine
import Defaults
import Foundation
import Lowtech
import SwiftUI

struct ResolutionField: View {
    enum Field: Hashable {
        case width
        case height
        case name
    }

    @ObservedObject var optimiser: Optimiser
    @FocusState private var focused: Field?

    @State private var tempWidth = 0
    @State private var tempHeight = 0
    @State private var isAspectRatio = false
    @State private var cropOrientation = CropOrientation.adaptive
    @State private var cropSize: CropSize?

    @State var size: NSSize = .zero
    @State var name = ""

    @Default(.savedCropSizes) var savedCropSizes

    @Environment(\.preview) var preview

    @ViewBuilder var viewer: some View {
        Button(
            action: {
                withAnimation(.easeOut(duration: 0.1)) { optimiser.editingResolution = true }
            },
            label: {
                HStack(spacing: 3) {
                    let hideOldSize = OM.compactResults && optimiser.newBytes > 0 && optimiser.newSize != nil && optimiser.newSize! != size // && (optimiser.newSize!.s + size.s).count > 14
                    if !hideOldSize {
                        Text(size == .zero ? "Crop" : "\(size.width.i)×\(size.height.i)")
                    }
                    if let newSize = optimiser.newSize, newSize != size {
                        if !hideOldSize {
                            SwiftUI.Image(systemName: "arrow.right")
                        }
                        Text("\(newSize.width.i)×\(newSize.height.i)")
                    }
                }
                .lineLimit(1)
            }
        )
        .focusable(false)
    }

    var aspectRatioPicker: some View {
        Picker("", selection: $cropOrientation) {
            Label("Portrait", systemImage: "rectangle.portrait").tag(CropOrientation.portrait)
            Label("Landscape", systemImage: "rectangle").tag(CropOrientation.landscape)
        }
        .pickerStyle(.segmented)
        .labelStyle(IconOnlyLabelStyle())
        .font(.heavy(10))
        .onChange(of: cropOrientation) { orientation in
            guard let cropSize = cropSize?.withOrientation(orientation) else {
                if orientation == .landscape {
                    let width = max(tempWidth, tempHeight)
                    let height = min(tempWidth, tempHeight)
                    tempWidth = width
                    tempHeight = height
                } else if orientation == .portrait {
                    let width = min(tempWidth, tempHeight)
                    let height = max(tempWidth, tempHeight)
                    tempWidth = width
                    tempHeight = height
                }
                cropSize = cropSize?.withOrientation(cropOrientation)
                return
            }
            self.cropSize = cropSize
            let size = cropSize.computedSize(from: size)
            tempWidth = size.width.evenInt
            tempHeight = size.height.evenInt
        }
    }

    var editor: some View {
        VStack {
            VStack(alignment: .leading) {
                Text("Size presets")
                    .heavy(10)
                    .foregroundColor(.secondary)
                ForEach(savedCropSizes.filter { !$0.isAspectRatio && $0.width <= size.width.i && $0.height <= size.height.i }.sorted(by: \.area)) { size in
                    cropSizeButton(size)
                }
                cropSizeButton(CropSize(width: size.width, height: size.height, name: "Default size"))
                if !isAspectRatio {
                    HStack(spacing: 9) {
                        TextField("", text: $name, prompt: Text("Name"))
                            .textFieldStyle(.roundedBorder)
                            .focused($focused, equals: .name)
                            .frame(width: 198, alignment: .leading)

                        Button(action: {
                            guard !preview, !name.isEmpty, tempWidth > 0 || tempHeight > 0
                            else { return }

                            savedCropSizes.append(CropSize(width: tempWidth, height: tempHeight, name: name))
                        }, label: {
                            SwiftUI.Image(systemName: "plus")
                                .font(.heavy(10))
                                .foregroundColor(.mauvish)
                        })
                        .buttonStyle(.bordered)
                        .fontDesign(.rounded)
                        .disabled(name.isEmpty || (tempWidth == 0 && tempHeight == 0))
                    }
                }
            }

            Divider()
            VStack(alignment: .leading) {
                Text("Aspect ratios")
                    .heavy(10)
                    .foregroundColor(.secondary)
                Grid(alignment: .leading) {
                    GridRow {
                        ForEach(DEFAULT_CROP_ASPECT_RATIOS[0 ..< 5].map { $0.withOrientation(cropOrientation) }) { size in
                            aspectRatioButton(size)
                        }
                    }
                    GridRow {
                        ForEach(DEFAULT_CROP_ASPECT_RATIOS[5 ..< 10].map { $0.withOrientation(cropOrientation) }) { size in
                            aspectRatioButton(size)
                        }
                    }
                    GridRow {
                        ForEach(DEFAULT_CROP_ASPECT_RATIOS[10 ..< 15].map { $0.withOrientation(cropOrientation) }) { size in
                            aspectRatioButton(size)
                        }
                    }
                }
            }

            Divider()

            HStack {
                TextField("", value: $tempWidth, formatter: NumberFormatter(), prompt: Text("Width"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .width)
                    .frame(width: 60, alignment: .center)
                    .multilineTextAlignment(.center)
                    .disabled(isAspectRatio)
                Text("×")
                TextField("", value: $tempHeight, formatter: NumberFormatter(), prompt: Text("Height"))
                    .textFieldStyle(.roundedBorder)
                    .focused($focused, equals: .height)
                    .frame(width: 60, alignment: .center)
                    .multilineTextAlignment(.center)
                    .disabled(isAspectRatio)
            }

            let sizeStr = isAspectRatio ? (cropSize?.name ?? "\(tempWidth):\(tempHeight)") : "\(tempWidth == 0 ? "Auto" : tempWidth.s)×\(tempHeight == 0 ? "Auto" : tempHeight.s)"
            Button("Crop and resize to \(sizeStr)") {
                guard !preview, tempWidth > 0 || tempHeight > 0 else { return }

                if isAspectRatio {
                    optimiser.crop(to: CropSize(
                        width: cropOrientation == .adaptive ? tempWidth : (cropOrientation == .landscape ? max(tempWidth, tempHeight) : min(tempWidth, tempHeight)),
                        height: cropOrientation == .adaptive ? tempHeight : (cropOrientation == .portrait ? max(tempWidth, tempHeight) : min(tempWidth, tempHeight)),
                        longEdge: cropOrientation == .adaptive, isAspectRatio: true
                    ))
                } else if tempWidth != 0, tempHeight != 0 {
                    optimiser.crop(to: CropSize(width: tempWidth, height: tempHeight))
                } else {
                    optimiser.downscale(toFactor: tempWidth == 0 ? tempHeight.d / size.height.d : tempWidth.d / size.width.d)
                }
            }
            .buttonStyle(.bordered)
            .fontDesign(.rounded)
            .monospacedDigit()
            .disabled(optimiser.running || (tempWidth == 0 && tempHeight == 0))

            if isAspectRatio {
                aspectRatioPicker.frame(width: 100)
            }
        }
        .padding()
        .defaultFocus($focused, .width)
    }

    @State private var hoveringHelpButton = false
    @State private var lastFocusState: Field?

    @ViewBuilder var editorViewer: some View {
        viewer
            .onAppear {
                guard let size = optimiser.oldSize else { return }
                tempWidth = size.width.i
                tempHeight = size.height.i
                cropOrientation = size.orientation
                self.size = size
            }
            .onChange(of: optimiser.oldSize) { size in
                guard let size else { return }
                tempWidth = size.width.i
                tempHeight = size.height.i
                cropOrientation = size.orientation
                self.size = size
            }
            .popover(isPresented: $optimiser.editingResolution, arrowEdge: .bottom) {
                PaddedPopoverView(background: Color.bg.warm.any) {
                    ZStack(alignment: .bottomTrailing) {
                        editor
                        SwiftUI.Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .padding(5)
                            .onHover { hovering in
                                hoveringHelpButton = hovering
                            }
                            .helpTag(
                                isPresented: $hoveringHelpButton,
                                alignment: .bottomTrailing,
                                offset: CGSize(width: -5, height: -25),
                                """
                                Width and height need to be smaller
                                than the original size.

                                Set the width or height to 0 to have it
                                calculated automatically while keeping
                                the original aspect ratio.
                                """
                            )
                    }
                    .onChange(of: tempWidth) { width in
                        if let size = optimiser.oldSize, width > size.width.evenInt {
                            tempWidth = size.width.evenInt
                        }
                    }
                    .onChange(of: tempHeight) { height in
                        if let size = optimiser.oldSize, height > size.height.evenInt {
                            tempHeight = size.height.evenInt
                        }
                    }
                    .foregroundColor(.fg.warm)
                }
            }
    }

    var body: some View {
        editorViewer
            .onChange(of: optimiser.running) { running in
                if running {
                    optimiser.editingResolution = false
                }
            }
    }

    @ViewBuilder func aspectRatioButton(_ size: CropSize) -> some View {
        Button(size.name) {
            isAspectRatio = true
            cropSize = size.withOrientation(cropOrientation)

            let newSize = (cropSize ?? size).computedSize(from: self.size)
            tempWidth = newSize.width.evenInt
            tempHeight = newSize.height.evenInt
        }.buttonStyle(.bordered)
    }

    @ViewBuilder func cropSizeButton(_ size: CropSize, noDelete: Bool = false) -> some View {
        HStack(spacing: 10) {
            Button(action: {
                isAspectRatio = false
                tempWidth = size.width
                tempHeight = size.height
                cropSize = size
            }, label: {
                HStack {
                    Text(size.name)
                        .allowsTightening(false)
                        .fontDesign(.rounded)
                    Spacer()
                    Text(size.id)
                        .monospaced()
                        .allowsTightening(false)
                }
                .frame(width: 180)
                .lineLimit(1)
            })
            .buttonStyle(.bordered)

            Button(action: {
                withAnimation(.easeOut(duration: 0.1)) {
                    savedCropSizes.removeAll(where: { $0.id == size.id })
                }
            }, label: {
                SwiftUI.Image(systemName: "trash")
                    .foregroundColor(.red)
            })
            .buttonStyle(.bordered)
            .disabled(noDelete)
            .opacity(noDelete ? 0.0 : 1.0)
        }
    }

}

extension CropSize: Defaults.Serializable {}
