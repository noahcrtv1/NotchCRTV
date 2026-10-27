import Foundation
import FoundationModels

/// Quebra uma demanda grande em etapas usando o modelo on-device da Apple (Apple Intelligence).
/// Sem modelo disponível, cai numa heurística simples.
enum Breakdown {
    static var aiAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func subtasks(for title: String, notes: String) async -> [String] {
        if aiAvailable {
            do {
                let session = LanguageModelSession(instructions: """
                Você ajuda a planejar tarefas. Responda em português do Brasil.
                Quebre a tarefa em 3 a 7 etapas curtas, práticas e em ordem.
                Uma etapa por linha, sem numeração, sem marcadores, sem texto extra.
                """)
                let prompt = notes.isEmpty ? "Tarefa: \(title)" : "Tarefa: \(title)\nDetalhes: \(notes)"
                let r = try await session.respond(to: prompt)
                let lines = clean(r.content)
                if lines.count >= 2 { return lines }
            } catch {}
        }
        return heuristic(title)
    }

    static func clean(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { s in
                var s = Substring(s)
                while let c = s.first, "-•*0123456789.)".contains(c) || c == " " { s = s.dropFirst() }
                return String(s).trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .prefix(8).map { $0 }
    }

    static func heuristic(_ title: String) -> [String] {
        let parts = title.replacingOccurrences(of: " e ", with: ",").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if parts.count > 1 { return parts }
        return ["Reunir material de “\(title)”", "Fazer a primeira versão", "Revisar e ajustar", "Entregar / enviar"]
    }
}
