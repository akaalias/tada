import SwiftUI

/// Container holding all injected service protocols for the app.
@Observable
@MainActor
final class AppServices {
    let knowledgeBase: KnowledgeBaseServiceProtocol
    let executiveAI: ExecutiveAIServiceProtocol
    let plannerAI: PlannerAIServiceProtocol

    init(
        knowledgeBase: KnowledgeBaseServiceProtocol?,
        executiveAI: ExecutiveAIServiceProtocol?,
        plannerAI: PlannerAIServiceProtocol?
    ) {
        self.knowledgeBase = knowledgeBase ?? KnowledgeBaseServiceAdapter()
        self.executiveAI = executiveAI ?? ExecutiveAIServiceAdapter()
        self.plannerAI = plannerAI ?? PlannerAIServiceAdapter()
    }
}

extension EnvironmentValues {
    /// Injected app-wide services. Set at the root of the app.
    private struct AppServicesKey: EnvironmentKey {
        static let defaultValue: AppServices? = nil
    }

    var appServices: AppServices? {
        get { self[AppServicesKey.self] }
        set { self[AppServicesKey.self] = newValue }
    }
}
