import Foundation

actor AIAgent {
    struct RunResult {
        let proposals: [AISuggestion]
        let summary: String
        let stepsUsed: Int
        let model: AIModel
        let inputTokens: Int
        let outputTokens: Int
        let estimatedCostUSD: Double
    }

    private let cancellation = CancellationFlag()
    nonisolated func cancel() { cancellation.cancel() }

    func run(
        model: AIModel,
        initialContext: String,
        historyProvider: @escaping @Sendable () -> [HistorySnapshot],
        eventEmitter: @escaping @Sendable (AgentEvent) -> Void,
        maxSteps: Int = 25
    ) async throws -> RunResult {
        cancellation.reset()
        let ctx = AgentContext(historyProvider: historyProvider, eventEmitter: eventEmitter)

        let client: AIProviderClient
        do {
            client = try ProviderFactory.make(modelId: model.id)
        } catch {
            eventEmitter(.error(message: "프로바이더 생성 실패: \(error.localizedDescription)"))
            throw error
        }

        let tools = ToolRegistry.all.map {
            AITool(name: $0.name, description: $0.description, inputSchema: $0.inputSchema)
        }

        var response: AIProviderResponse
        do {
            response = try await client.start(
                systemPrompt: AgentPromptBuilder.systemPrompt,
                initialUserMessage: initialContext,
                tools: tools,
                maxTokens: 4096
            )
        } catch {
            eventEmitter(.error(message: "첫 호출 실패: \(error.localizedDescription)"))
            throw error
        }

        for step in 0..<maxSteps {
            if cancellation.isCancelled { throw CancellationError() }

            if !response.text.isEmpty {
                eventEmitter(.thinking(text: response.text))
            }

            if response.toolUses.isEmpty {
                if !ctx.finished {
                    ctx.finished = true
                    ctx.finalSummary = response.text.isEmpty ? "분석 종료" : String(response.text.prefix(240))
                    eventEmitter(.finished(summary: ctx.finalSummary))
                }
                return makeResult(model: model, client: client, ctx: ctx, step: step + 1)
            }

            var results: [AIToolResult] = []
            for use in response.toolUses {
                if cancellation.isCancelled { throw CancellationError() }
                let argsString = (try? String(data: JSONSerialization.data(withJSONObject: use.input), encoding: .utf8)) ?? "{}"
                eventEmitter(.toolCall(name: use.name, args: argsString))

                var resultJSON: Any = ["error": "unknown tool"]
                var isError = true
                do {
                    if let tool = ToolRegistry.find(use.name) {
                        resultJSON = try await tool.execute(input: use.input, context: ctx)
                        isError = false
                    }
                } catch {
                    resultJSON = ["error": error.localizedDescription]
                }

                let jsonString = jsonToString(resultJSON)
                eventEmitter(.toolResult(name: use.name, summary: summarize(jsonString), isError: isError))
                results.append(AIToolResult(id: use.id, content: jsonString, isError: isError))
            }

            if ctx.finished {
                return makeResult(model: model, client: client, ctx: ctx, step: step + 1)
            }

            do {
                response = try await client.continueConversation(toolResults: results, maxTokens: 4096)
            } catch {
                eventEmitter(.error(message: "API 호출 실패: \(error.localizedDescription)"))
                throw error
            }
        }

        eventEmitter(.error(message: "최대 스텝 \(maxSteps) 도달. 현재까지 제안 \(ctx.proposals.count)개."))
        return makeResult(model: model, client: client, ctx: ctx, step: maxSteps)
    }

    private func makeResult(model: AIModel, client: AIProviderClient, ctx: AgentContext, step: Int) -> RunResult {
        let cost = Double(client.inputTokensUsed) / 1_000_000 * model.inputCostPerMTok
                 + Double(client.outputTokensUsed) / 1_000_000 * model.outputCostPerMTok
        return RunResult(
            proposals: ctx.proposals,
            summary: ctx.finalSummary.isEmpty ? "분석 종료" : ctx.finalSummary,
            stepsUsed: step,
            model: model,
            inputTokens: client.inputTokensUsed,
            outputTokens: client.outputTokensUsed,
            estimatedCostUSD: cost
        )
    }

    private func jsonToString(_ value: Any) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: []),
           let s = String(data: data, encoding: .utf8) { return s }
        return "\(value)"
    }

    private func summarize(_ json: String) -> String {
        json.count > 200 ? String(json.prefix(200)) + "..." : json
    }
}
