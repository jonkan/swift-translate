//
//  Copyright © 2024 Hidden Spectrum, LLC.
//

import Foundation
import SwiftStringCatalog


public protocol TranslationService {
    func translate(_ string: String, in sourcLanguage: Language, to targetLanguage: Language, comment: String?) async throws -> String
}
