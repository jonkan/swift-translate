//
//  Copyright © 2024 Hidden Spectrum, LLC.
//

import Foundation


enum SwiftTranslateError: Error {
    case couldNotSearchDirectoryAt(URL)
    case noTranslationReturned
    case unhandledFileType
    case fileNotFound(URL)
    case fileAlreadyExists(URL)
    case failedToParseLocale(String)
    case failedToSaveTranslation(String)
}
