import Foundation

@Observable
final class BaselineManager {
    private(set) var hasBaseline: Bool

    private let fileURL: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appending(path: "baseline.json")
    }()

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appending(path: "baseline.json")
        hasBaseline = FileManager.default.fileExists(atPath: url.path())
    }

    func save(_ baseline: BaselineData) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(baseline)
        try data.write(to: fileURL, options: .atomic)
        hasBaseline = true
    }

    func load() -> BaselineData? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BaselineData.self, from: data)
    }

    func delete() throws {
        try FileManager.default.removeItem(at: fileURL)
        hasBaseline = false
    }
}
