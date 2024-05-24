//
//  StringCatalogEvaluator.swift
//
//
//  Created by Jonas Bromö on 2024-05-17.
//

import Foundation
import SwiftStringCatalog
import Semaphore

@MainActor
struct StringCatalogEvaluator {
    let service: EvaluationService
    let languages: Set<Language>?
    let overwrite: Bool
    let skipConfirmations: Bool
    let verbose: Bool

    private let semaphore: AsyncSemaphore

    // MARK: Lifecycle

    init(
        with service: EvaluationService,
        languages: Set<Language>?,
        overwrite: Bool,
        skipConfirmations: Bool,
        verbose: Bool,
        numberOfConcurrentTasks: Int
    ) {
        self.service = service
        self.languages = languages
        self.overwrite = overwrite
        self.skipConfirmations = skipConfirmations
        self.verbose = verbose
        self.semaphore = AsyncSemaphore(value: numberOfConcurrentTasks)
    }

    func process(fileAt fileUrl: URL) async throws -> Int {
        let catalog = try loadStringCatalog(from: fileUrl)

        var targetUrl = fileUrl
        if !overwrite {
            targetUrl = targetUrl.deletingPathExtension().appendingPathExtension("loc.xcstrings")
        }

        let numberOfVerifiedStrings = try await evaluate(
            catalog: catalog,
            savingPeriodicallyTo: targetUrl
        )

        return numberOfVerifiedStrings
    }

    private func loadStringCatalog(from url: URL) throws -> StringCatalog {
        Log.info(newline: .before, "Loading catalog \(url.path) into memory...")
        let catalog = try StringCatalog(url: url)
        Log.info("Found \(catalog.allKeys.count) keys targeting \(catalog.targetLanguages.count) languages for a total of \(catalog.localizableStringsCount) localizable strings")
        return catalog
    }

    @discardableResult
    func evaluate(catalog: StringCatalog, savingPeriodicallyTo fileURL: URL? = nil) async throws -> Int {
        if catalog.allKeys.isEmpty {
            return 0
        }
        let reviewedStringsCount = try await withThrowingTaskGroup(of: Bool.self) { group in
            for task in try evaluationTasks(for: catalog, savingTo: fileURL) {
                group.addTask { await task.value }
            }

            var count = 0
            for try await result in group {
                count += result ? 1 : 0
            }
            return count
        }

        return reviewedStringsCount
    }

    private func evaluationTasks(
        for catalog: StringCatalog,
        savingTo fileURL: URL? = nil
    ) throws -> [Task<Bool, Never>] {
        var tasks: [Task<Bool, Never>] = []

        for key in catalog.allKeys {
            guard let localizableStringGroup = catalog.localizableStringGroups[key] else {
                continue
            }
            for localizableString in localizableStringGroup.strings {
                let isSource = catalog.sourceLanguage == localizableString.targetLanguage
                let language = localizableString.targetLanguage

                guard
                    languages == nil || languages?.contains(language) == true,
                    !isSource,
                    localizableString.state == .needsReview,
                    let translation = localizableString.translatedValue
                else {
                    continue
                }

                let task = Task {
                    await semaphore.wait()
                    let reviewed = await evaluate(
                        localizableString,
                        translation: translation,
                        in: language,
                        comment: localizableStringGroup.comment
                    )
                    semaphore.signal()

                    if let fileURL {
                        do {
                            try await MainActor.run {
                                try catalog.write(to: fileURL)
                            }
                        } catch {
                            Log.error("Failed to save string catalog: \(error)")
                        }
                    }

                    return reviewed
                }
                tasks.append(task)
            }
        }
        return tasks
    }

    private func evaluate(
        _ localizableString: LocalizableString,
        translation: String,
        in language: Language,
        comment: String?
    ) async -> Bool {
        let numberOfRetries = 1
        var failedAttempts = 0
        while failedAttempts <= numberOfRetries {
            do {
                let result = try await service.evaluateQuality(
                    localizableString.sourceValue,
                    translation: translation,
                    in: language,
                    comment: comment
                )

                await MainActor.run {
                    if verbose {
                        logResult(source: localizableString.sourceValue, result: result, translation: translation, in: language)
                    }

                    if result.quality == .good {
                        localizableString.setTranslated()
                    }
                }
                return true
            } catch {
                failedAttempts += 1

                await MainActor.run {
                    let message: String
                    if failedAttempts <= numberOfRetries {
                        message = "[Error: \(error.localizedDescription)] (retrying)"
                    } else {
                        message = "[Error: \(error.localizedDescription)]"
                    }
                    logError(language: language, message: message)
                }
            }
        }
        return false
    }

    // MARK: Utilities

    private func logResult(source: String, result: EvaluationResult, translation: String, in language: Language) {
        Log.structured(
            .init("Evaluated:"),
            .init("\"\(source.truncatedRemovingNewlines(to: 64))\"")
        )
        Log.structured(
            .init(width: 6, language.rawValue),
            .init(width: 10, result.quality.description + ":"),
            .init("\"\(translation.truncatedRemovingNewlines(to: 64))\"")
        )
        if result.quality != .good {
            Log.structured(
                .init(width: 6, "-"),
                .init(width: 10, "🤖 Reason:"),
                .init(result.explanation)
            )
        }
    }

    private func logError(language: Language, message: String) {
        Log.structured(
            .init(width: 6, language.rawValue),
            .init(message.red)
        )
    }

}
