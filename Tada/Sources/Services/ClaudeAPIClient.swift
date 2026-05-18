import Foundation
import os.log

private let logger = Logger(subsystem: "com.tada.app", category: "API")

actor ClaudeAPIClient {
    private let apiKey: String
    private let role: AIRole
    /// Task phase used for requests that don't specify one explicitly.
    private let defaultPhase: APIRequestPhase
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let model: String

    init(apiKey: String, role: AIRole, phase: APIRequestPhase) {
        self.apiKey = apiKey
        self.role = role
        self.defaultPhase = phase
        self.model = ModelPreference.selectedModel
    }

    /// Sends a request via URLSession while recording it in `APILog` for the Console view.
    private func performLoggedRequest(_ request: URLRequest, phase: APIRequestPhase, taskTitle: String?) async throws -> (Data, HTTPURLResponse) {
        let entryID = await APILog.shared.logRequest(request, role: role, phase: phase, taskTitle: taskTitle)
        let start = Date()
        func elapsedMS() -> Int { Int(Date().timeIntervalSince(start) * 1000) }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClaudeAPIError.invalidResponse
            }
            let headers = httpResponse.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                if let key = pair.key as? String { result[key] = String(describing: pair.value) }
            }
            await APILog.shared.logResponse(
                id: entryID,
                statusCode: httpResponse.statusCode,
                headers: headers,
                body: data,
                durationMS: elapsedMS()
            )
            return (data, httpResponse)
        } catch {
            await APILog.shared.logFailure(id: entryID, error: error.localizedDescription, durationMS: elapsedMS())
            throw error
        }
    }

    func sendMessage(
        systemPrompt: String,
        userMessage: String,
        maxTokens: Int = 2048,
        phase: APIRequestPhase? = nil,
        taskTitle: String? = nil
    ) async throws -> String {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = AppConstants.requestTimeout

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userMessage]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await performLoggedRequest(request, phase: phase ?? defaultPhase, taskTitle: taskTitle)

        guard httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorBody["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ClaudeAPIError.apiError(message)
            }
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw ClaudeAPIError.invalidResponse
        }

        return text
    }

    func sendStructuredMessage<T: Decodable>(
        systemPrompt: String,
        userMessage: String,
        responseType: T.Type,
        maxTokens: Int = 2048,
        attachedImages: [Data] = [],
        phase: APIRequestPhase? = nil,
        taskTitle: String? = nil
    ) async throws -> T {
        // Use tool_use for guaranteed structured output
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = AppConstants.requestTimeout

        // Define the tool schema based on the response type name
        let toolSchema = getToolSchema(for: String(describing: responseType))

        // Build user message content: images first, then text. If no images, send as a plain string.
        let userContent: Any
        if attachedImages.isEmpty {
            userContent = userMessage
        } else {
            var blocks: [[String: Any]] = attachedImages.map { data in
                [
                    "type": "image",
                    "source": [
                        "type": "base64",
                        "media_type": "image/png",
                        "data": data.base64EncodedString()
                    ]
                ]
            }
            blocks.append(["type": "text", "text": userMessage])
            userContent = blocks
        }

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "tools": [toolSchema],
            "tool_choice": ["type": "tool", "name": toolSchema["name"] as Any],
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await performLoggedRequest(request, phase: phase ?? defaultPhase, taskTitle: taskTitle)

        // Check for API errors in the response body (works for any status code)
        if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let errorType = errorBody["type"] as? String, errorType == "error",
           let error = errorBody["error"] as? [String: Any],
           let message = error["message"] as? String {
            throw ClaudeAPIError.apiError(message)
        }

        guard httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorBody["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ClaudeAPIError.apiError(message)
            }
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }

        // Parse tool use response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("Could not parse API response as JSON")
            if let rawString = String(data: data, encoding: .utf8) {
                logger.error("Raw response: \(rawString)")
            }
            throw ClaudeAPIError.invalidResponse
        }

        guard let content = json["content"] as? [[String: Any]] else {
            // Check if this is actually an error response
            if let errorType = json["type"] as? String, errorType == "error",
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ClaudeAPIError.apiError(message)
            }
            logger.error("No content in response: \(String(describing: json))")
            throw ClaudeAPIError.invalidResponse
        }

        guard let toolUse = content.first(where: { $0["type"] as? String == "tool_use" }) else {
            // Check if there's a text response instead (error message)
            if let textContent = content.first(where: { $0["type"] as? String == "text" }),
               let text = textContent["text"] as? String {
                logger.error("Got text instead of tool_use: \(text)")
            }
            logger.error("No tool_use in content: \(String(describing: content))")
            throw ClaudeAPIError.invalidResponse
        }

        guard let input = toolUse["input"] else {
            logger.error("No input in tool_use: \(String(describing: toolUse))")
            throw ClaudeAPIError.invalidResponse
        }

        let inputData = try JSONSerialization.data(withJSONObject: input)

        do {
            return try JSONDecoder().decode(T.self, from: inputData)
        } catch {
            logger.error("Failed to decode input: \(error)")
            if let inputStr = String(data: inputData, encoding: .utf8) {
                logger.error("Input JSON: \(inputStr)")
            }
            throw ClaudeAPIError.jsonParsingError(error)
        }
    }

    private func getToolSchema(for typeName: String) -> [String: Any] {
        switch typeName {
        case "ActionSchema":
            return [
                "name": "generate_action_ui",
                "description": "Generate a UI schema for user interaction. IMPORTANT: field type must be exactly one of: text, number, multiSelect, singleSelect, yesNo, date, textarea, drawing, slider, rangeSlider, countSelector, itemTable, orderedList, hierarchicalList. For yes/no questions use yesNo not radio.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "type": ["type": "string", "enum": ["form"]],
                        "title": ["type": "string", "description": "Clear question or prompt for the user"],
                        "description": ["type": "string", "description": "Optional helpful context"],
                        "submitLabel": ["type": "string", "description": "Button label like Continue, Submit, Next"],
                        "requiresExternalAction": [
                            "type": "boolean",
                            "description": "True if this step requires real-world action outside the app (making calls, sending emails, adding to calendar, traveling). False for in-app data entry only."
                        ],
                        "fields": [
                            "type": "array",
                            "maxItems": 1,
                            "items": [
                                "type": "object",
                                "properties": [
                                    "id": ["type": "string", "description": "Unique field identifier"],
                                    "type": [
                                        "type": "string",
                                        "enum": ["text", "number", "multiSelect", "singleSelect", "yesNo", "date", "textarea", "drawing", "slider", "rangeSlider", "countSelector", "itemTable", "orderedList", "hierarchicalList"],
                                        "description": "Field type. Use yesNo for yes/no questions, singleSelect for picking one option, multiSelect for multiple options, textarea for long text, drawing for sketches, slider for a single numeric value, rangeSlider for a min-max range (use for all budget/price questions), countSelector for small whole-number counts 1-5+ (passengers, tickets, rooms), itemTable for tables with custom columns (define columns via options: each option is a column with id, label, and description for type - use 'currency' for amounts or 'select:Choice1,Choice2' for dropdowns), orderedList for drag-and-drop reorderable lists (provide the items to be reordered via options - each option's label becomes a draggable row), hierarchicalList for drag-and-drop trees where users can nest items as children (seed via prefillRows with each row holding 'item' label and 'depth' as a string number: '0' root, '1' child, '2' grandchild)"
                                    ],
                                    "label": ["type": "string", "description": "Field label shown to user"],
                                    "placeholder": ["type": "string", "description": "Placeholder text"],
                                    "required": ["type": "boolean", "default": true],
                                    "options": [
                                        "type": "array",
                                        "description": "Required for singleSelect and multiSelect. Each option needs id and label.",
                                        "items": [
                                            "type": "object",
                                            "properties": [
                                                "id": ["type": "string"],
                                                "label": ["type": "string"],
                                                "description": ["type": "string"]
                                            ],
                                            "required": ["id", "label"]
                                        ]
                                    ],
                                    "validation": [
                                        "type": "object",
                                        "description": "For slider: set minValue and maxValue",
                                        "properties": [
                                            "minValue": ["type": "number"],
                                            "maxValue": ["type": "number"]
                                        ]
                                    ],
                                    "defaultValue": [
                                        "type": "string",
                                        "description": "Pre-filled value for text/textarea fields based on previous responses"
                                    ],
                                    "prefillRows": [
                                        "type": "array",
                                        "description": "Pre-filled rows for itemTable based on previous responses. Each row is an object with column id keys.",
                                        "items": ["type": "object"]
                                    ]
                                ],
                                "required": ["id", "type", "label"]
                            ]
                        ]
                    ],
                    "required": ["type", "title", "submitLabel", "requiresExternalAction", "fields"]
                ]
            ]
        case "TaskPlan":
            return [
                "name": "create_task_plan",
                "description": "Create a structured task plan",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Short, specific name for the USER'S task - what they want to accomplish, in their own terms. Never a generic label like 'Clarifying Questions' or 'Task Discovery'."],
                        "description": ["type": "string", "description": "One plain sentence summarising the task itself."],
                        "subTasks": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "title": ["type": "string"],
                                    "description": ["type": "string"],
                                    "requiresExternalAction": [
                                        "type": "boolean",
                                        "description": "True if step requires real-world action outside app (calls, emails, calendar, travel). False for in-app data entry."
                                    ]
                                ],
                                "required": ["title", "description", "requiresExternalAction"]
                            ]
                        ]
                    ],
                    "required": ["title", "description", "subTasks"]
                ]
            ]
        case "PlanRevision":
            return [
                "name": "revise_plan",
                "description": "Decide whether to revise the plan",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "revised": ["type": "boolean"],
                        "reason": ["type": "string"],
                        "subTasks": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "title": ["type": "string"],
                                    "description": ["type": "string"],
                                    "requiresExternalAction": [
                                        "type": "boolean",
                                        "description": "True if step requires real-world action outside app (calls, emails, calendar, travel). False for in-app data entry."
                                    ]
                                ],
                                "required": ["title", "description", "requiresExternalAction"]
                            ]
                        ]
                    ],
                    "required": ["revised"]
                ]
            ]
        case "NoteLinkSuggestions":
            return [
                "name": "save_related_notes",
                "description": "Save the list of existing notes that belong in the new note's Related section.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "links": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "targetPath": ["type": "string", "description": "Verbatim path of an existing note from the input list."],
                                    "targetTitle": ["type": "string", "description": "Title to display for the link to the target."],
                                    "reason": ["type": "string", "description": "One-sentence justification."]
                                ],
                                "required": ["targetPath", "targetTitle", "reason"]
                            ]
                        ]
                    ],
                    "required": ["links"]
                ]
            ]
        case "GeneratedKnowledgeNote":
            return [
                "name": "save_atomic_note",
                "description": "Save one atomic markdown note with a short noun-phrase title and a concise body.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "title": [
                            "type": "string",
                            "description": "Short noun-phrase title (3-8 words)."
                        ],
                        "body": [
                            "type": "string",
                            "description": "1-3 short paragraphs of concise markdown. First person, no emojis."
                        ]
                    ],
                    "required": ["title", "body"]
                ]
            ]
        case "EntityExtractionResult":
            return [
                "name": "extract_entities_and_link",
                "description": "Rewrite the note body with Obsidian wikilinks around high-signal entities and emit any new atomic entity notes.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "linkedBody": [
                            "type": "string",
                            "description": "The note body with first-occurrence wikilinks of the form [[<slug>.md|<Display Name>]] around each entity (existing or new). All other text preserved verbatim."
                        ],
                        "newEntities": [
                            "type": "array",
                            "description": "Entities not already in the existing list. Empty array if no new entities.",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "slug": [
                                        "type": "string",
                                        "description": "Lowercase kebab-case slug (alphanumerics and hyphens only, max 48 chars)."
                                    ],
                                    "displayName": [
                                        "type": "string",
                                        "description": "Human-friendly display name for the entity."
                                    ],
                                    "body": [
                                        "type": "string",
                                        "description": "1-2 short sentences distilling the entity. First person, no emojis, no wikilinks."
                                    ]
                                ],
                                "required": ["slug", "displayName", "body"]
                            ]
                        ]
                    ],
                    "required": ["linkedBody", "newEntities"]
                ]
            ]
        case "MicroStepsResponse":
            return [
                "name": "break_down_step",
                "description": "Break down an overwhelming step into smaller micro-steps",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "microSteps": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "title": ["type": "string"],
                                    "description": ["type": "string"],
                                    "requiresExternalAction": [
                                        "type": "boolean",
                                        "description": "True if step requires real-world action outside app (calls, emails, calendar, travel). False for in-app data entry."
                                    ]
                                ],
                                "required": ["title", "description", "requiresExternalAction"]
                            ]
                        ]
                    ],
                    "required": ["microSteps"]
                ]
            ]
        default:
            return [
                "name": "generate_response",
                "description": "Generate structured response",
                "input_schema": [
                    "type": "object",
                    "properties": [:],
                    "required": []
                ]
            ]
        }
    }

    /// Sends a request body and returns the raw JSON response. Used by CoachService.
    func sendRequest(body: [String: Any], phase: APIRequestPhase, taskTitle: String?) async throws -> [String: Any] {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = AppConstants.requestTimeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await performLoggedRequest(request, phase: phase, taskTitle: taskTitle)

        guard httpResponse.statusCode == 200 else {
            if let errorBody = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorBody["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw ClaudeAPIError.apiError(message)
            }
            throw ClaudeAPIError.httpError(httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeAPIError.invalidResponse
        }

        return json
    }
}

enum ClaudeAPIError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case jsonParsingError(Error)
    case missingAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI service"
        case .httpError(let code):
            return "Connection error (HTTP \(code))"
        case .apiError(let message):
            // Show the actual API error message directly - it's usually clear
            return message
        case .jsonParsingError:
            return "Failed to understand AI response. Please try again."
        case .missingAPIKey:
            return "API key not configured. Go to Settings to add your Claude API key."
        }
    }
}
