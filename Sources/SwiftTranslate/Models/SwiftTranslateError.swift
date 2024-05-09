//
//  Copyright © 2024 Hidden Spectrum, LLC.
//

import Foundation


enum SwiftTranslateError: LocalizedError {
    case couldNotSearchDirectoryAt(URL)
    case noTranslationReturned
    case unexpectedTranslationResponse
    case failedToParseTranslationResponse(String)
    case translationFailed
    case evaluationIsNotSupported
    case translationFailedLinting
    case unhandledFileType
    case fileNotFound(URL)
    case fileAlreadyExists(URL)
    case failedToParseLocale(String)
    case failedToSaveTranslation(String)

    var errorDescription: String? {
        switch self {
        case .couldNotSearchDirectoryAt(let url):
            "Could not search directory at: \(url)"
        case .noTranslationReturned:
            "No translation returned"
        case .unexpectedTranslationResponse:
            "Unexpected translation response"
        case .failedToParseTranslationResponse(let message):
            "Failed to parse translation response: \(message)"
        case .translationFailed:
            "Translation failed"
        case .evaluationIsNotSupported:
            "Evaluation is not supported"
        case .translationFailedLinting:
            "Translation failed linting"
        case .unhandledFileType:
            "Unhandled file type"
        case .fileNotFound(let url):
            "File not found: \(url)"
        case .fileAlreadyExists(let url):
            "File already exists: \(url)"
        case .failedToParseLocale(let string):
            "Failed to parse locale: \(string)"
        case .failedToSaveTranslation(let string):
            "Failed to save translation: \(string)"
        }
    }

}
