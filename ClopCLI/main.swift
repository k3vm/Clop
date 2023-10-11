//
//  main.swift
//  ClopCLI
//
//  Created by Alin Panaitiu on 25.09.2023.
//

import ArgumentParser
import Cocoa
import Foundation
import PDFKit
import System
import UniformTypeIdentifiers

let SIZE_REGEX = #/(\d+)\s*[xX×]\s*(\d+)/#
let CLOP_APP: URL = {
    let u = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
    return u.pathExtension == "app" ? u : URL(fileURLWithPath: "/Applications/Clop.app")
}()

var currentRequestIDs: [String] = []
func ensureAppIsRunning() {
    guard !isClopRunning() else {
        return
    }
    NSWorkspace.shared.open(CLOP_APP)
}

func isURLOptimisable(_ url: URL, type: UTType? = nil) -> Bool {
    guard url.isFileURL, let type = type ?? url.contentTypeResourceValue ?? url.fetchFileType() else {
        return true
    }
    return IMAGE_VIDEO_FORMATS.contains(type) || type == .pdf
}

extension FilePath: ExpressibleByArgument {
    public init?(argument: String) {
        guard FileManager.default.fileExists(atPath: argument) else {
            return nil
        }
        self.init(argument)
    }
}

extension NSSize: ExpressibleByArgument {
    public init?(argument: String) {
        if let size = Int(argument) {
            self.init(width: size, height: size)
            return
        }

        guard let match = try? SIZE_REGEX.firstMatch(in: argument) else {
            return nil
        }
        let width = Int(match.1)!
        let height = Int(match.2)!
        self.init(width: width, height: height)
    }
}

let DEVICES_STR = """
Devices:
  iPad:        "iPad 3"  "iPad 4"  "iPad 5"  "iPad 6"
               "iPad 7"  "iPad 8"  "iPad 9"  "iPad 10"

  iPad Air:    "iPad Air 1"  "iPad Air 2"    "iPad Air 3"
               "iPad Air 4"  "iPad Air 5"

  iPad mini:   "iPad mini 1"   "iPad mini 2"   "iPad mini 3"
               "iPad mini 4"   "iPad mini 5"   "iPad mini 6"

  iPad Pro:    "iPad Pro 1 12.9inch"   "iPad Pro 1 9.7inch"
               "iPad Pro 2 10.5inch"   "iPad Pro 2 12.9inch"
               "iPad Pro 3 11inch"     "iPad Pro 3 12.9inch"
               "iPad Pro 4 11inch"     "iPad Pro 4 12.9inch"
               "iPad Pro 5 11inch"     "iPad Pro 5 12.9inch"
               "iPad Pro 6 11inch"     "iPad Pro 6 12.9inch"

  iPhone:      "iPhone 15"    "iPhone 15 Plus"  "iPhone 15 Pro"      "iPhone 15 Pro Max"
               "iPhone 14"    "iPhone 14 Plus"  "iPhone 14 Pro"      "iPhone 14 Pro Max"
               "iPhone 13"    "iPhone 13 mini"  "iPhone 13 Pro"      "iPhone 13 Pro Max"
               "iPhone 12"    "iPhone 12 mini"  "iPhone 12 Pro"      "iPhone 12 Pro Max"
               "iPhone 11"    "iPhone 11 Pro"   "iPhone 11 Pro Max"
               "iPhone X"     "iPhone XR"       "iPhone XS"          "iPhone XS Max"
               "iPhone SE 1"  "iPhone SE 2"     "iPhone SE 3"
               "iPhone 7"     "iPhone 7 Plus"   "iPhone 8"           "iPhone 8 Plus"
               "iPhone 6"     "iPhone 6 Plus"   "iPhone 6s"          "iPhone 6s Plus"
               "iPhone 4"     "iPhone 4S"       "iPhone 5"           "iPhone 5S"

  iPod touch:  "iPod touch 4" "iPod touch 5" "iPod touch 6" "iPod touch 7"
"""

let PAPER_SIZES_STR = """
Paper sizes:
  A:              "2A0"  "4A0"  "A0"   "A0+"  "A1"   "A1+"  "A10"  "A11"  "A12"  "A13"
                  "A2"   "A3"   "A3+"  "A4"   "A5"   "A6"   "A7"   "A8"   "A9"

  B:              "B0"   "B0+"  "B1"   "B1+"  "B10"  "B11"  "B12"  "B13"  "B2"   "B2+"
                  "B3"   "B4"   "B5"   "B6"   "B7"   "B8"   "B9"

  US:             "ANSI A"  "ANSI B"  "ANSI C"  "ANSI D"  "ANSI E"
                  "Arch A"  "Arch B"  "Arch C"  "Arch D"  "Arch E"  "Arch E1"  "Arch E2"  "Arch E3"
                  "Letter"  "Government Letter" "Half Letter"
                  "Government Legal"  "Junior Legal"  "Ledger"  "Legal"  "Tabloid"

  Photography:    "2LD, DSCW"    "2LW"  "2R"  "3R, L"    "4R, KG"    "5R, 2L"    "6R"
                  "A3+ Super B"  "KGD"  "LW"  "LD, DSC"  "Passport"  "S8R, 6PW"  "8R, 6P"

  Newspaper:      "British Broadsheet"  "South African Broadsheet"  "Broadsheet"   "US Broadsheet"
                  "Canadian Tabloid"    "Norwegian Tabloid"    "Newspaper Tabloid"
                  "Berliner"  "Ciner"   "Compact"     "Nordisch"         "Rhenish"
                  "Swiss"     "Wall Street Journal"   "New York Times"

  Books:          "12mo"  "16mo"  "18mo"  "32mo"  "48mo"  "64mo"
                  "A Format"  "B Format"  "C Format" "Folio"  "Quarto"
                  "Octavo"        "Royal Octavo"     "Medium Octavo"
                  "Crown Octavo"  "Imperial Octavo"  "Super Octavo"
"""

func getURLsFromFolder(_ folder: URL, recursive: Bool) -> [URL] {
    guard let enumerator = FileManager.default.enumerator(
        at: folder,
        includingPropertiesForKeys: [.isRegularFileKey, .nameKey, .isDirectoryKey, .contentTypeKey],
        options: [.skipsPackageDescendants]
    ) else {
        return []
    }

    var urls: [URL] = []

    for case let fileURL as URL in enumerator {
        guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .nameKey, .isDirectoryKey, .contentTypeKey]),
              let isDirectory = resourceValues.isDirectory, let isRegularFile = resourceValues.isRegularFile, let name = resourceValues.name
        else {
            continue
        }

        if isDirectory {
            if !recursive || name.hasPrefix(".") || ["node_modules", ".git"].contains(name) {
                enumerator.skipDescendants()
            }
            continue
        }

        if !isRegularFile {
            continue
        }

        if !isURLOptimisable(fileURL, type: resourceValues.contentType) {
            continue
        }
        urls.append(fileURL)
    }
    return urls
}

func validateItems(_ items: [String], recursive: Bool, skipErrors: Bool) throws -> [URL] {
    var dirs: [URL] = []
    var urls: [URL] = try items.compactMap { item in
        let url = item.contains(":") ? (URL(string: item) ?? URL(fileURLWithPath: item)) : URL(fileURLWithPath: item)
        var isDir = ObjCBool(false)

        if url.isFileURL, !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if skipErrors {
                return nil
            }

            throw ValidationError("File \(url.path) does not exist")
        }

        if isDir.boolValue {
            dirs.append(url)
            return nil
        }
        return url
    }.filter { isURLOptimisable($0) }
    urls += dirs.flatMap { getURLsFromFolder($0, recursive: recursive) }

    ensureAppIsRunning()
    sleep(1)

    guard isClopRunning() else {
        Clop.exit(withError: CLIError.appNotRunning)
    }
    return urls
}

func sendRequest(urls: [URL], showProgress: Bool, async: Bool, gui: Bool, operation: String, _ requestCreator: () -> OptimisationRequest) throws {
    if !async {
        progressPrinter = ProgressPrinter(urls: urls)
        Task.init {
            await progressPrinter!.startResponsesThread()

            guard showProgress else { return }
            await progressPrinter!.printProgress()
        }
    }

    currentRequestIDs = urls.map(\.absoluteString)
    let req = requestCreator()
    signal(SIGINT, stopCurrentRequests(_:))
    signal(SIGTERM, stopCurrentRequests(_:))

    if showProgress, !async, let progressPrinter {
        for url in urls where url.isFileURL {
            Task.init { await progressPrinter.startProgressListener(url: url) }
        }
    }

    guard !async else {
        try OPTIMISATION_PORT.sendAndForget(data: req.jsonData)
        print("Queued \(urls.count) items for \(operation)")
        if !gui {
            printerr("Use the `--gui` flag to see progress")
        }
        Clop.exit()
    }

    let respData = try OPTIMISATION_PORT.sendAndWait(data: req.jsonData)
    guard respData != nil else {
        Clop.exit(withError: CLIError.optimisationError)
    }

    awaitSync {
        await progressPrinter!.waitUntilDone()

        if showProgress {
            await progressPrinter!.printProgress()
            fflush(stderr)
        }
        await progressPrinter!.printResults()
    }
}

struct Clop: ParsableCommand {
    struct CropPdf: ParsableCommand {
        @Option(help: "Crops pages to fit the screen of a specific device (e.g. iPad Air)")
        var forDevice: String? = nil

        @Option(help: "Crops pages to fit a specific paper size (e.g. A4, Letter)")
        var paperSize: String? = nil

        @Option(help: "Crops pages to fit the aspect ratio of a resolution (e.g. 1640x2360)")
        var resolution: NSSize? = nil

        @Option(help: "Crops the PDF pages to fit a specific aspect ratio (e.g. 1.7777777778 for 16:9)")
        var aspectRatio: Double? = nil

        @Flag(name: .shortAndLong, help: "Crop all PDFs in subfolders (when using a folder as input)")
        var recursive = false

        @Flag(name: .long, help: "List possible devices that can be passed to --for-device")
        var listDevices = false

        @Flag(name: .long, help: "List possible paper sizes that can be passed to --paper-size")
        var listPaperSizes = false

        @Option(help: "Output file path (defaults to modifying the PDF in place). In case of cropping multiple files, this needs to be a folder.")
        var output: String? = nil

        @Argument(help: "PDFs to crop (can be a folder)")
        var pdfs: [FilePath] = []

        var foundPDFs: [FilePath] = []
        var ratio: Double!

        func getPDFsFromFolder(_ folder: FilePath) -> [FilePath] {
            guard let enumerator = FileManager.default.enumerator(
                at: folder.url,
                includingPropertiesForKeys: [.isRegularFileKey, .nameKey, .isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else {
                return []
            }

            var pdfs: [FilePath] = []

            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .nameKey, .isDirectoryKey]),
                      let isDirectory = resourceValues.isDirectory, let isRegularFile = resourceValues.isRegularFile, let name = resourceValues.name
                else {
                    continue
                }

                if isDirectory {
                    if !recursive || name.hasPrefix(".") || ["node_modules", ".git"].contains(name) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                if !isRegularFile {
                    continue
                }

                if !name.lowercased().hasSuffix(".pdf") {
                    continue
                }
                pdfs.append(FilePath(fileURL.path))
            }
            return pdfs
        }

        mutating func validate() throws {
            if listDevices {
                print(DEVICES_STR)
                throw ExitCode.success
            }

            if listPaperSizes {
                print(PAPER_SIZES_STR)
                throw ExitCode.success
            }

            ratio = DEVICE_SIZES[forDevice ?? ""]?.aspectRatio ?? PAPER_SIZES[paperSize ?? ""]?.aspectRatio ?? resolution?.aspectRatio ?? aspectRatio
            guard let ratio else {
                throw ValidationError("Invalid aspect ratio, at least one of --for-device, --paper-size, --resolution or --aspect-ratio must be specified")
            }
            guard ratio > 0 else {
                throw ValidationError("Invalid aspect ratio, must be greater than 0")
            }
            if pdfs.count > 1, let output, output.hasSuffix(".pdf") {
                throw ValidationError("Output path must be a folder when cropping multiple PDFs")
            }
            guard output == nil || !output!.isEmpty else {
                throw ValidationError("Output path cannot be empty")
            }
            guard !pdfs.isEmpty else {
                throw ValidationError("At least one PDF or folder must be specified")
            }

            var isDir: ObjCBool = false
            if let folder = pdfs.first, FileManager.default.fileExists(atPath: folder.string, isDirectory: &isDir), isDir.boolValue {
                foundPDFs = getPDFsFromFolder(folder)
            } else {
                foundPDFs = pdfs
            }
        }

        mutating func run() throws {
            var outputDir: FilePath? = nil
            if let output, foundPDFs.count > 1 || output.last == "/" {
                outputDir = output.first! == "/" ? FilePath(output) : FilePath(FileManager.default.currentDirectoryPath).appending(output)

                if !FileManager.default.fileExists(atPath: outputDir!.string) {
                    try FileManager.default.createDirectory(at: outputDir!.url, withIntermediateDirectories: true, attributes: nil)
                }
            }

            for pdf in foundPDFs.compactMap({ PDFDocument(url: $0.url) }) {
                print("Cropping \(pdf.documentURL!.path) to aspect ratio \(ratio!)", terminator: outputDir == nil ? "\n" : "")
                pdf.cropTo(aspectRatio: ratio)

                if let outputDir {
                    let output = outputDir.appending(pdf.documentURL!.lastPathComponent)
                    print(" -> saved to \(output.string)")
                    pdf.write(to: output.url)
                } else {
                    pdf.write(to: pdf.documentURL!)
                }
            }
        }
    }

    struct Crop: ParsableCommand {
        @Flag(name: .shortAndLong, help: "Whether to show or hide the floating result (the usual Clop UI)")
        var gui = false

        @Flag(name: .shortAndLong, help: "Don't print progress to stderr")
        var noProgress = false

        @Flag(name: .long, help: "Process files and items in the background")
        var async = false

        @Flag(name: .shortAndLong, help: "Optimise all files in subfolders (when using a folder as input)")
        var recursive = false

        @Flag(name: .shortAndLong, help: "Copy file to clipboard after optimisation")
        var copy = false

        @Flag(name: .shortAndLong, help: "Skips missing files and unreachable URLs\n")
        var skipErrors = false

        @Flag(
            name: .shortAndLong,
            help: "When the size is specified as a single number, it will crop the longer of width or height to that number.\nThe shorter edge will be calculated automatically while keeping the original aspect ratio.\n\nExample: `clop crop --long-edge --size 1920` will crop a landscape 2400x1350 image to 1920x1080, and a portrait 1350x2400 image to 1080x1920\n"
        )
        var longEdge = false

        @Option(
            help: "Downscales and crops the image, video or PDF to a specific size (e.g. 1200x630)\nExample: cropping an image from 100x120 to 50x50 will first downscale it to 50x60 and then crop it to 50x50\n\nUse 0 for width or height to have it calculated automatically while keeping the original aspect ratio. (e.g. `128x0` or `0x720`)\n"
        )
        var size: NSSize

        var urls: [URL] = []

        @Argument(help: "Images, videos, PDFs or URLs to crop (can be a folder)")
        var items: [String] = []

        mutating func validate() throws {
            urls = try validateItems(items, recursive: recursive, skipErrors: skipErrors)
        }

        mutating func run() throws {
            try sendRequest(urls: urls, showProgress: !noProgress, async: async, gui: gui, operation: "cropping") {
                OptimisationRequest(
                    id: String(Int.random(in: 1000 ... 100_000)),
                    urls: urls,
                    size: size.cropSize(longEdge: longEdge),
                    downscaleFactor: 0.9,
                    changePlaybackSpeedFactor: nil,
                    hideFloatingResult: !gui,
                    copyToClipboard: copy,
                    aggressiveOptimisation: false,
                    source: "cli"
                )
            }
        }
    }

    struct Downscale: ParsableCommand {
        @Flag(name: .shortAndLong, help: "Whether to show or hide the floating result (the usual Clop UI)")
        var gui = false

        @Flag(name: .shortAndLong, help: "Don't print progress to stderr")
        var noProgress = false

        @Flag(name: .long, help: "Process files and items in the background")
        var async = false

        @Flag(name: .shortAndLong, help: "Optimise all files in subfolders (when using a folder as input)")
        var recursive = false

        @Flag(name: .shortAndLong, help: "Copy file to clipboard after optimisation")
        var copy = false

        @Flag(name: .shortAndLong, help: "Skips missing files and unreachable URLs")
        var skipErrors = false

        @Option(help: "Makes the image or video smaller by a certain amount (1.0 means no resize, 0.5 means half the size)")
        var factor = 0.5

        var urls: [URL] = []

        @Argument(help: "Images, videos or URLs to downscale (can be a folder)")
        var items: [String] = []

        mutating func validate() throws {
            urls = try validateItems(items, recursive: recursive, skipErrors: skipErrors)
        }

        mutating func run() throws {
            try sendRequest(urls: urls, showProgress: !noProgress, async: async, gui: gui, operation: "downscaling") {
                OptimisationRequest(
                    id: String(Int.random(in: 1000 ... 100_000)),
                    urls: urls,
                    size: nil,
                    downscaleFactor: factor,
                    changePlaybackSpeedFactor: nil,
                    hideFloatingResult: !gui,
                    copyToClipboard: copy,
                    aggressiveOptimisation: false,
                    source: "cli"
                )
            }
        }
    }

    struct Optimise: ParsableCommand {
        @Flag(name: .shortAndLong, help: "Whether to show or hide the floating result (the usual Clop UI)")
        var gui = false

        @Flag(name: .shortAndLong, help: "Don't print progress to stderr")
        var noProgress = false

        @Flag(name: .long, help: "Process files and items in the background")
        var async = false

        @Flag(name: .shortAndLong, help: "Use aggressive optimisation")
        var aggressive = false

        @Flag(name: .shortAndLong, help: "Optimise all files in subfolders (when using a folder as input)")
        var recursive = false

        @Flag(name: .shortAndLong, help: "Copy file to clipboard after optimisation")
        var copy = false

        @Flag(name: .shortAndLong, help: "Skips missing files and unreachable URLs")
        var skipErrors = false

        @Option(help: "Speeds up the video by a certain amount (1 means no change, 2 means twice as fast, 0.5 means 2x slower)")
        var changePlaybackSpeedFactor: Double? = nil

        @Option(help: "Makes the image or video smaller by a certain amount (1.0 means no resize, 0.5 means half the size)")
        var downscaleFactor: Double? = nil

        @Option(help: "Downscales and crops the image, video or PDF to a specific size (e.g. 1200x630)\nExample: cropping an image from 100x120 to 50x50 will first downscale it to 50x60 and then crop it to 50x50")
        var crop: NSSize? = nil

        var urls: [URL] = []

        @Argument(help: "Images, videos, PDFs or URLs to optimise (can be a folder)")
        var items: [String] = []

        mutating func validate() throws {
            urls = try validateItems(items, recursive: recursive, skipErrors: skipErrors)
        }

        mutating func run() throws {
            try sendRequest(urls: urls, showProgress: !noProgress, async: async, gui: gui, operation: "optimisation") {
                OptimisationRequest(
                    id: String(Int.random(in: 1000 ... 100_000)),
                    urls: urls,
                    size: crop?.cropSize(),
                    downscaleFactor: downscaleFactor,
                    changePlaybackSpeedFactor: changePlaybackSpeedFactor,
                    hideFloatingResult: !gui,
                    copyToClipboard: copy,
                    aggressiveOptimisation: aggressive,
                    source: "cli"
                )
            }
        }
    }

    static let configuration = CommandConfiguration(
        abstract: "Clop",
        subcommands: [
            Optimise.self,
            Crop.self,
            Downscale.self,
            CropPdf.self,
        ]
    )
}

var progressPrinter: ProgressPrinter?

struct CLIResult: Codable {
    let done: [OptimisationResponse]
    let failed: [OptimisationResponseError]
}

actor ProgressPrinter {
    init(urls: [URL]) {
        urlsToProcess = urls
    }

    var urlsToProcess: [URL]

    var responses: [URL: OptimisationResponse] = [:]
    var errors: [URL: OptimisationResponseError] = [:]

    var progressFractionObserver: [URL: NSKeyValueObservation] = [:]
    var progressSubscribers: [URL: Any] = [:]
    var progressProxies: [URL: Progress] = [:]

    func markDone(response: OptimisationResponse) {
        log.debug("Got response \(response.jsonString) for \(response.forURL)")

        removeProgressSubscriber(url: response.forURL)
        responses[response.forURL] = response
    }

    func markError(response: OptimisationResponseError) {
        log.debug("Got error response \(response.error) for \(response.forURL)")

        removeProgressSubscriber(url: response.forURL)
        errors[response.forURL] = response
    }

    func addProgressSubscriber(url: URL, progress: Progress) {
        progressFractionObserver[url] = progress.observe(\.fractionCompleted) { _, change in
            Task.init { await self.printProgress() }
        }
        progressProxies[url] = progress
    }

    func removeProgressSubscriber(url: URL) {
        if let sub = progressSubscribers.removeValue(forKey: url) {
            Progress.removeSubscriber(sub)
        }
        progressProxies.removeValue(forKey: url)
        if let observer = progressFractionObserver[url] {
            observer.invalidate()
        }
        progressFractionObserver.removeValue(forKey: url)
        printProgress()
    }

    func startProgressListener(url: URL) {
        let sub = Progress.addSubscriber(forFileURL: url) { progress in
            Task.init { await self.addProgressSubscriber(url: url, progress: progress) }
            return {
                Task.init { await self.removeProgressSubscriber(url: url) }
            }
        }
        progressSubscribers[url] = sub
    }

    var lastPrintedLinesCount = 0

    func printProgress() {
        printerr([String](repeating: "\(LINE_UP)\(LINE_CLEAR)", count: lastPrintedLinesCount).joined(separator: ""), terminator: "")

        let done = responses.count
        let failed = errors.count
        let total = urlsToProcess.count

        lastPrintedLinesCount = progressProxies.count + 1
        printerr("Processed \(done + failed) of \(total) | Success: \(done) | Failed: \(failed)")

        for (url, progress) in progressProxies {
            let progressInt = Int(round(progress.fractionCompleted * 100))
            let progressBarStr = String(repeating: "█", count: Int(progress.fractionCompleted * 20)) + String(repeating: "░", count: 20 - Int(progress.fractionCompleted * 20))
            var itemStr = (url.isFileURL ? url.path : url.absoluteString)
            if itemStr.count > 50 {
                itemStr = "..." + itemStr.suffix(40)
            }
            if let desc = progress.localizedAdditionalDescription {
                printerr("\(itemStr): \(desc) \(progressBarStr) (\(progressInt)%)")
            } else {
                printerr("\(itemStr): \(progressBarStr) \(progressInt)%")
            }
        }
    }

    func waitUntilDone() async {
        while responses.count + errors.count < urlsToProcess.count {
            try! await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func printResults() {
        let result = CLIResult(done: responses.values.sorted { $0.forURL.path < $1.forURL.path }, failed: errors.values.sorted { $0.forURL.path < $1.forURL.path })
        print(result.jsonString)
    }

    func startResponsesThread() {
        responsesThread = Thread {
            OPTIMISATION_CLI_RESPONSE_PORT.listen { data in
                log.debug("Received optimisation response: \(data?.count ?? 0) bytes")

                guard let data else {
                    return nil
                }
                if let resp = OptimisationResponse.from(data) {
                    Task.init { await self.markDone(response: resp) }
                }
                if let resp = OptimisationResponseError.from(data) {
                    Task.init { await self.markError(response: resp) }
                }
                return nil
            }
            RunLoop.current.run()
        }
        responsesThread?.start()
    }
}

let LINE_UP = "\u{1B}[1A"
let LINE_CLEAR = "\u{1B}[2K"
var responsesThread: Thread?

enum CLIError: Error {
    case optimisationError
    case appNotRunning
}

func stopCurrentRequests(_ signal: Int32) {
    let req = StopOptimisationRequest(ids: currentRequestIDs, remove: false)
    try? OPTIMISATION_PORT.sendAndForget(data: req.jsonData)
    Clop.exit()
}

Clop.main()