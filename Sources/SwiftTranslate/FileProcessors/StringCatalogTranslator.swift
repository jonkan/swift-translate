//
//  Copyright © 2024 Hidden Spectrum, LLC.
//

import Foundation
import SwiftStringCatalog
import Semaphore

@MainActor
struct StringCatalogTranslator: FileTranslator {
    
    // MARK: Internal
    
    let overwrite: Bool
    let skipConfirmations: Bool
    let setNeedsReviewAfterTranslating: Bool
    let targetLanguages: Set<Language>?
    let service: TranslationService
    let verbose: Bool

    private let semaphore: AsyncSemaphore
    private let linter: StringCatalogLinter

    // MARK: Lifecycle
    
    init(
        with translator: TranslationService,
        targetLanguages: Set<Language>?,
        overwrite: Bool,
        skipConfirmations: Bool,
        setNeedsReviewAfterTranslating: Bool,
        verbose: Bool,
        numberOfConcurrentTasks: Int
    ) {
        self.skipConfirmations = skipConfirmations
        self.overwrite = overwrite
        self.targetLanguages = targetLanguages
        self.service = translator
        self.setNeedsReviewAfterTranslating = setNeedsReviewAfterTranslating
        self.verbose = verbose
        self.semaphore = AsyncSemaphore(value: numberOfConcurrentTasks)
        self.linter = StringCatalogLinter(verbose: false)
    }
    
    func translate(fileAt fileUrl: URL) async throws -> Int {
        let catalog = try loadStringCatalog(from: fileUrl)
        
        if !skipConfirmations {
            verifyLargeTranslation(of: catalog.allKeys.count, to: catalog.targetLanguages.count)
        }
        
        if catalog.allKeys.isEmpty {
            return 0
        }

        var targetUrl = fileUrl
        if !overwrite {
            targetUrl = targetUrl.deletingPathExtension().appendingPathExtension("loc.xcstrings")
        }

        let translatedStringsCount = try await withThrowingTaskGroup(of: Bool.self) { group in
            for task in try translationTasks(for: catalog, savingTo: targetUrl) {
                group.addTask { await task.value }
            }

            var count = 0
            for try await result in group {
                count += result ? 1 : 0
            }
            return count
        }

        return translatedStringsCount
    }
    
    private func loadStringCatalog(from url: URL) throws -> StringCatalog {
        Log.info(newline: .before, "Loading catalog \(url.path) into memory...")
        let catalog = try StringCatalog(url: url, configureWith: targetLanguages)
        Log.info("Found \(catalog.allKeys.count) keys targeting \(catalog.targetLanguages.count) languages for a total of \(catalog.localizableStringsCount) localizable strings")
        return catalog
    }

    private func translationTasks(
        for catalog: StringCatalog,
        savingTo fileURL: URL? = nil
    ) throws -> [Task<Bool, Never>] {
        catalog.localizableStringGroups.flatMap { key, group in
            group.strings.compactMap { localizableString -> Task<Bool, Never>? in
                let isSource = catalog.sourceLanguage == localizableString.targetLanguage
                if localizableString.state == .translated || isSource {
                    return nil
                }
                return Task {
                    await semaphore.wait()
                    let translation = await translate(
                        localizableString.sourceValue,
                        in: catalog.sourceLanguage,
                        to: localizableString.targetLanguage,
                        comment: group.comment
                    )
                    semaphore.signal()

                    if let translation {
                        do {
                            try await MainActor.run {
                                localizableString.setTranslation(translation)
                                if setNeedsReviewAfterTranslating {
                                    localizableString.setNeedsReview()
                                }

                                if let fileURL {
                                    try catalog.write(to: fileURL)
                                }
                            }
                        } catch {
                            Log.error("Failed to save string catalog: \(error)")
                        }
                        return true
                    }
                    return false
                }
            }
        }
    }

    private func translate(
        _ sourceValue: String,
        in sourceLanguage: Language,
        to targetLanguage: Language,
        comment: String?
    ) async -> String? {
        let numberOfRetries = 1
        var failedAttempts = 0
        while failedAttempts <= numberOfRetries {
            do {
                let translatedString = try await service.translate(
                    sourceValue,
                    to: targetLanguage,
                    comment: comment
                )
                let lintingPassed = linter.lint(
                    source: sourceValue,
                    sourceLanguage: sourceLanguage,
                    translation: translatedString,
                    language: targetLanguage
                )
                if !lintingPassed {
                    throw SwiftTranslateError.translationFailedLinting
                } else if verbose {
                    logTranslationResult(sourceValue, to: targetLanguage, translation: translatedString, comment: comment)
                }
                return translatedString
            } catch {
                failedAttempts += 1
                let message: String
                if failedAttempts <= numberOfRetries {
                    message = "[Error: \(error.localizedDescription)] (retrying)".red
                } else {
                    message = "[Error: \(error.localizedDescription)]".red
                }
                logError(language: targetLanguage, message: message)
            }
        }
        return nil
    }

    // MARK: Utilities
    
    private func verifyLargeTranslation(of stringsCount: Int, to languageCount: Int) {
        guard stringsCount * languageCount > 200 else {
            return
        }
        print("\n?".yellow, "Are you sure you wish to translate \(stringsCount) keys into \(languageCount) languages? Y/n")
        let yesNo = readLine()
        guard yesNo?.lowercased() == "y" || yesNo == "" else {
            print("Translation canceled 🫡".yellow)
            exit(0)
        }
    }
    
    private func logTranslationResult(_ source: String, to language: Language, translation: String, comment: String?) {
        Log.structured(
            .init("Translated:"),
            .init("\"\(source.truncatedRemovingNewlines(to: 64))\""),
            .init("[Comment: \(comment?.truncatedRemovingNewlines(to: 64) ?? "n/a")]".dim)
        )
        Log.structured(
            level: .info,
            .init(width: 8, language.rawValue + ":"),
            .init("\"\(translation.truncatedRemovingNewlines(to: 64))\"")
        )
    }

    private func logError(language: Language, message: String) {
        Log.structured(
            .init(width: 6, language.rawValue),
            .init(message.red)
        )
    }

}
