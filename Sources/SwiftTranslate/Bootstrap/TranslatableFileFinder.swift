//
//  Copyright © 2024 Hidden Spectrum, LLC.
//

import Foundation


struct TranslatableFileFinder {
    
    // MARK: Internal
    
    enum FileType: String {
        case stringCatalog = "xcstrings"
        case jsonSpecification = "json"

        var translatorType: FileTranslator.Type {
            switch self {
            case .stringCatalog:
                return StringCatalogTranslator.self
            case .jsonSpecification:
                return JSONSpecificationTranslator.self
            }
        }
    }
    let type: FileType

    // MARK: Private
    
    private let fileManager = FileManager.default
    private let fileOrDirectoryURL: URL

    // MARK: Lifecycle

    init(fileOrDirectoryURL: URL, type: FileType) {
        self.fileOrDirectoryURL = fileOrDirectoryURL
        self.type = type
    }

    init(fileOrDirectoryURL: URL) throws {
        self.fileOrDirectoryURL = fileOrDirectoryURL
        if fileOrDirectoryURL.pathExtension == "" {
            self.type = .stringCatalog
        } else {
            guard let type = FileType(rawValue: fileOrDirectoryURL.pathExtension) else {
                throw SwiftTranslateError.unhandledFileType
            }
            self.type = type
        }
    }
    
    // MARK: Main
    
    func findTranslatableFiles() throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: fileOrDirectoryURL.path, isDirectory: &isDirectory) else {
            logNoFilesFound()
            return []
        }
        
        if isDirectory.boolValue {
            return try searchDirectory(at: fileOrDirectoryURL)
        } else if isTranslatable(fileOrDirectoryURL) {
            return [fileOrDirectoryURL]
        } else {
            logNoFilesFound()
            return []
        }
    }
    
    private func isTranslatable(_ fileUrl: URL) -> Bool {
        fileUrl.pathExtension == type.rawValue
    }
    
    private func searchDirectory(at directoryUrl: URL) throws -> [URL] {
        guard let fileEnumerator = fileManager.enumerator(at: directoryUrl, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) else {
            throw SwiftTranslateError.couldNotSearchDirectoryAt(directoryUrl)
        }
        
        var translatableUrls = [URL]()
        for case let fileURL as URL in fileEnumerator {
            if isTranslatable(fileURL) {
                translatableUrls.append(fileURL)
            }
        }
        if translatableUrls.isEmpty {
            logNoFilesFound()
            return []
        }
        return translatableUrls
    }
    
    private func logNoFilesFound() {
        Log.warning("No translatable files found at path \(fileOrDirectoryURL.path)")
    }
}
