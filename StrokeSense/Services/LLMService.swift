import Foundation

struct LLMService {
    struct CheckMetrics: Encodable {
        let severity: String
        let flaggedCount: Int
        let faceSymmetry: MetricPair?
        let armCheckIncomplete: Bool
        let armDrift: MetricPair?
        let speechClarity: MetricPair?
    }

    struct MetricPair: Encodable {
        let baseline: Double
        let current: Double
        let dropPoints: Double
    }

    static func generateSummary(metrics: CheckMetrics) async -> String? {
        let systemPrompt = """
        You are a health assessment assistant for a stroke screening app. \
        The user just completed quick checks: face symmetry, arm drift (whether an arm sank or turned while held out), and speech clarity. \
        A missing metric was not measured. If arm_check_incomplete is true, say the arm check could not be completed \
        and never describe the results as normal or reassuring. \
        Each metric is scored 0-1 (higher is better) with a personal baseline and a current reading. \
        drop_points is how far the current reading fell below baseline on a 0-100 scale; \
        a drop of 25 points or more is flagged as significant. \
        A negative drop means the reading is better than baseline and is not a concern. \
        Produce a concise 2-3 sentence plain-language summary: \
        (1) state the overall assessment, \
        (2) call out any concerning areas by name, \
        (3) suggest a concrete next step (e.g. "rest and re-check in 10 minutes" or "call 911 immediately"). \
        Do NOT use medical jargon. Speak directly to the user ("your").
        """

        let metricsJSON: Data
        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            metricsJSON = try encoder.encode(metrics)
        } catch {
            return nil
        }

        guard let metricsString = String(data: metricsJSON, encoding: .utf8) else {
            return nil
        }

        let requestBody: [String: Any] = [
            "model": "gpt-4o",
            "max_tokens": 200,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": metricsString]
            ]
        ]

        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(APIKeys.openAI)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                return nil
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }

            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
