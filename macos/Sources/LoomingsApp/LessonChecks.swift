import Foundation
import LoomingsTeaching

/// The exercise checks of the bundled lessons, from `lessons/checks.json`.
enum LessonChecks {
    private static let table: [String: [String]] = {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("lessons/checks.json"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return table
    }()

    static func checks(for file: String) -> [ExerciseCheck] {
        (table[file] ?? []).enumerated().compactMap { index, value in
            try? ExerciseCheck.parse(Directive(key: "check", value: value, line: index)).get()
        }
    }
}
