import Foundation
import FoundationModels

// Step 0 de-risk: confirm the on-device Apple Foundation Model is actually
// available on this machine before building anything on top of it.

if #available(macOS 26.0, *) {
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available:
        print("FM AVAILABLE")
    case .unavailable(let reason):
        print("FM UNAVAILABLE: \(String(describing: reason))")
    }
} else {
    print("FM UNAVAILABLE: requires macOS 26+")
}
