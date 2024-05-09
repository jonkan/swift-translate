//
//  JSONSpecificationTranslator.swift
//
//
//  Created by Jonas Bromö on 2024-05-09.
//

import Foundation
import struct SwiftStringCatalog.Language

struct JSONSpecificationTranslator: FileTranslator {
    
    // MARK: Internal

    let overwrite: Bool
    let skipConfirmations: Bool
    let targetLanguages: Set<Language>?
    let service: TranslationService
    let verbose: Bool

    // MARK: Lifecycle

    init(with translator: TranslationService, targetLanguages: Set<Language>?, overwrite: Bool, skipConfirmations: Bool, verbose: Bool) {
        self.skipConfirmations = skipConfirmations
        self.overwrite = overwrite
        self.targetLanguages = targetLanguages
        self.service = translator
        self.verbose = verbose
    }

    func translate(fileAt specFileURL: URL) async throws -> Int {
        let spec = try loadSpec(from: specFileURL)
        let specDirectoryURL = specFileURL.deletingLastPathComponent()
        try verify(spec, at: specDirectoryURL)

        for file in spec.files {
            let sourceFileURL = fileURL(file.sourceFileURL, relativeTo: specDirectoryURL)
            let fileContents = try String(contentsOf: sourceFileURL, encoding: .utf8)
            Log.info(newline: verbose ? .before : .none, "Translating file \(sourceFileURL.lastPathComponent), locale: \(file.sourceLocale.identifier), contents `\(fileContents.truncatedRemovingNewlines(to: 64))` " + "[Comment: \(file.comment ?? "n/a")]".dim)

            for output in file.outputs {
                let outputFileURL = fileURL(output.fileURL, relativeTo: specDirectoryURL)
                guard !fileExists(outputFileURL) || overwrite else {
                    Log.info(newline: verbose ? .before : .none, "Skipping \(output.locale.identifier) [Already translated]".dim)
                    continue
                }

                guard let targetLanguageCode = output.locale.language.languageCode?.identifier else {
                    throw SwiftTranslateError.failedToParseLocale("Missing languageCode for locale \(output.locale.identifier)")
                }
                let targetLanguage = Language(targetLanguageCode)
                let translatedString = try await service.translate(
                    fileContents,
                    to: targetLanguage,
                    comment: file.comment
                )

                // Write the output file
                guard let outputData = translatedString.data(using: .utf8) else {
                    throw SwiftTranslateError.failedToSaveTranslation("Failed to convert translated string to UTF-8")
                }
                try FileManager.default.createDirectory(
                    at: outputFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try outputData.write(to: outputFileURL)

                if verbose {
                    logTranslationResult(to: targetLanguage, result: translatedString.truncatedRemovingNewlines(to: 64))
                }
            }
        }

        return 0
    }

    private func loadSpec(from fileURL: URL) throws -> JSONSpecification {
        Log.info(newline: .before, "Loading json Specification \(fileURL.path) into memory...")
        let data = try Data(contentsOf: fileURL)
        let spec = try JSONDecoder().decode(JSONSpecification.self, from: data)
        Log.info("Found json specification containing \(spec.files.count) files to translate")
        return spec
    }

    private func verify(_ spec: JSONSpecification, at specDirectoryURL: URL) throws {
        for file in spec.files {
            let sourceFileURL = fileURL(file.sourceFileURL, relativeTo: specDirectoryURL)
            guard fileExists(sourceFileURL) else {
                throw SwiftTranslateError.fileNotFound(sourceFileURL)
            }
        }
    }

    // MARK: Utilities

    private func fileURL(_ fileURL: URL, relativeTo relativeURL: URL) -> URL {
        relativeURL.appending(path: fileURL.path)
    }

    private func fileExists(_ fileURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    private func logTranslationResult(to language: Language, result: String) {
        Log.structured(
            level: .info,
            .init(width: 8, language.rawValue + ":"),
            .init(result)
        )
    }
}



struct JSONSpecification: Codable {

    /// Each entry represents a file to translate
    let files: [FileSpecification]

    struct FileSpecification: Codable {
        /// The locale of the source file, i.e. which language to translate from.
        let sourceLocale: Locale
        /// File URL to the source file, relative to where the json specification is located.
        let sourceFileURL: URL
        /// A comment to pass to the translation service (Optional).
        let comment: String?
        /// One or more outputs, i.e. languages to translate to.
        let outputs: [Output]

        struct Output: Codable {
            let locale: Locale
            let fileURL: URL
            /// Set this to `true` if you  want the file to be copied without being translated. (Optional)
            let skipTranslation: Bool
        }
    }

}

extension JSONSpecification.FileSpecification {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let localeIdentifier = try container.decode(String.self, forKey: .sourceLocale)
        sourceLocale = Locale(identifier: localeIdentifier)
        sourceFileURL = try container.decode(URL.self, forKey: .sourceFileURL)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        outputs = try container.decode([Output].self, forKey: .outputs)
    }
}

extension JSONSpecification.FileSpecification.Output {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let localeIdentifier = try container.decode(String.self, forKey: .locale)
        locale = Locale(identifier: localeIdentifier)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        skipTranslation = try container.decodeIfPresent(Bool.self, forKey: .skipTranslation) ?? false
    }
}
