//
//  JSONSpecificationTranslator.swift
//
//
//  Created by Jonas Bromö on 2024-05-09.
//

import Foundation
import struct SwiftStringCatalog.Language

@MainActor
struct JSONSpecificationTranslator: FileTranslator {

    // MARK: Internal

    let overwrite: Bool
    let skipConfirmations: Bool
    let targetLanguages: Set<Language>?
    let onlyFiles: [String]
    let service: TranslationService
    let verbose: Bool

    // MARK: Lifecycle

    init(
        with translator: any TranslationService,
        targetLanguages: Set<Language>?,
        onlyFiles: [String],
        overwrite: Bool,
        skipConfirmations: Bool,
        setNeedsReviewAfterTranslating: Bool,
        verbose: Bool,
        numberOfConcurrentTasks: Int
    ) {
        self.skipConfirmations = skipConfirmations
        self.targetLanguages = targetLanguages
        self.onlyFiles = onlyFiles
        self.overwrite = overwrite
        self.service = translator
        self.verbose = verbose
    }

    func translate(fileAt specFileURL: URL) async throws -> Int {
        let spec = try loadSpec(from: specFileURL)
        let specDirectoryURL = specFileURL.deletingLastPathComponent()
        try verify(spec, at: specDirectoryURL)

        guard let sourceLanguageCode = spec.sourceLocale.locale.language.languageCode?.identifier else {
            throw SwiftTranslateError.failedToParseLocale("Missing languageCode for locale \(spec.sourceLocale.locale.identifier)")
        }
        let sourceLanguage = Language(sourceLanguageCode)

        for file in spec.files {
            if !onlyFiles.isEmpty && !onlyFiles.contains(file.fileURL.lastPathComponent) {
                continue
            }

            let sourceFileURL = fileURL(file.fileURL, with: spec.sourceLocale.folderName, relativeTo: specDirectoryURL)
            let fileContents = try String(contentsOf: sourceFileURL, encoding: .utf8)
            Log.info(newline: verbose ? .before : .none, "Translating file \(sourceFileURL.lastPathComponent), locale: \(spec.sourceLocale.locale.identifier), contents `\(fileContents.truncatedRemovingNewlines(to: 64))` ")

            for locale in spec.locales {
                guard let targetLanguageCode = locale.locale.language.languageCode?.identifier else {
                    throw SwiftTranslateError.failedToParseLocale("Missing languageCode for locale \(locale.locale.identifier)")
                }
                // Skip if not included in the targetLanguages
                if let targetLanguages, !targetLanguages.contains(where: { $0.code == targetLanguageCode }) {
                    continue
                }

                let outputFileURL = fileURL(file.fileURL, with: locale.folderName, relativeTo: specDirectoryURL)
                guard !fileExists(outputFileURL) || overwrite else {
                    Log.info(newline: verbose ? .before : .none, "Skipping \(locale.locale.identifier) [Already translated]".dim)
                    continue
                }

                let targetLanguage = Language(targetLanguageCode)
                let translatedString: String
                if file.skipTranslation {
                    translatedString = fileContents
                } else {
                    translatedString = try await service.translate(
                        fileContents,
                        in: sourceLanguage,
                        to: targetLanguage,
                        comment: [spec.comment, file.comment].compactMap(\.self).joined(separator: " ")
                    )
                }

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
                    logTranslationResult(
                        to: targetLanguage,
                        result: translatedString.truncatedRemovingNewlines(to: 64),
                        copiedWithoutTranslation: file.skipTranslation
                    )
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
            let sourceFileURL = fileURL(file.fileURL, with: spec.sourceLocale.folderName, relativeTo: specDirectoryURL)
            guard fileExists(sourceFileURL) else {
                throw SwiftTranslateError.fileNotFound(sourceFileURL)
            }
        }
    }

    // MARK: Utilities

    private func fileURL(_ fileURL: URL, relativeTo relativeURL: URL) -> URL {
        relativeURL.appending(path: fileURL.path)
    }

    private func fileURL(_ fileURL: URL, with localeReplacement: String, relativeTo relativeURL: URL) -> URL {
        let path = fileURL.path.replacingOccurrences(of: "{locale}", with: localeReplacement)
        return relativeURL.appending(path: path)
    }

    private func fileExists(_ fileURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL.path)
    }

    private func logTranslationResult(to language: Language, result: String, copiedWithoutTranslation copied: Bool) {
        Log.structured(
            level: .info,
            .init(width: 8, language.rawValue + ":"),
            .init(result),
            .init(copied ? "[Copied without translation]".dim : "")
        )
    }
}

struct JSONSpecification: Codable {
    /// The locale of the source file, i.e. which language to translate from.
    let sourceLocale: FileLocale
    /// A comment to pass to the translation service. Optional.
    let comment: String?
    /// Locales to translate each file to.
    let locales: [FileLocale]
    /// One or more file specifications i.e. files to translate.
    let files: [FileSpecification]

    struct FileLocale: Codable {
        /// The locale to translate the file to.
        let locale: Locale
        /// Name of the folder where the file of this locale. Optional, defaults to the locale.
        let folderName: String
    }

    struct FileSpecification: Codable {
        let fileURL: URL
        /// A comment to pass to the translation service. Optional.
        let comment: String?
        /// Set this to `true` if you just want the file to be copied without being translated. Optional, defaults to `false`.
        let skipTranslation: Bool
    }
}

extension JSONSpecification {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceLocale = try container.decode(FileLocale.self, forKey: .sourceLocale)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        locales = try container.decode([FileLocale].self, forKey: .locales)
        files = try container.decode([FileSpecification].self, forKey: .files)
    }
}

extension JSONSpecification.FileSpecification {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        skipTranslation = try container.decodeIfPresent(Bool.self, forKey: .skipTranslation) ?? false
    }
}

extension JSONSpecification.FileLocale {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let localeIdentifier = try container.decode(String.self, forKey: .locale)
        locale = Locale(identifier: localeIdentifier)
        folderName = try container.decodeIfPresent(String.self, forKey: .folderName) ?? localeIdentifier
    }
}
