//
//  Copyright © 2024 Hidden Spectrum, LLC.
//

import Foundation
import SwiftStringCatalog


@MainActor
protocol FileTranslator {
    var service: TranslationService { get }
    var targetLanguages: Set<Language>? { get }
    var overwrite: Bool { get }
    var skipConfirmations: Bool { get }
    var verbose: Bool { get }
    
    init(
        with translator: TranslationService,
        targetLanguages: Set<Language>?,
        onlyFiles: [String],
        overwrite: Bool,
        skipConfirmations: Bool,
        setNeedsReviewAfterTranslating: Bool,
        verbose: Bool,
        numberOfConcurrentTasks: Int
    )

    func translate(fileAt fileUrl: URL) async throws -> Int
}
