import Foundation
import Combine

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var note: String
    var createdAt: Date
    var isDone: Bool = false
    var doneAt: Date?
}

/// 단일 저장소. 배열 순서 = 우선순위(위가 높음).
final class TodoStore: ObservableObject {
    static let shared = TodoStore()

    @Published private(set) var items: [TodoItem] = []
    /// 방금 추가된 항목 (목록이 그 위치로 스크롤)
    @Published private(set) var lastAddedID: UUID?

    var pending: [TodoItem] { items.filter { !$0.isDone } }
    var done: [TodoItem] {
        items.filter(\.isDone).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
    }

    private let fileURL: URL

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--data"), i + 1 < args.count {
            // 디버그/데모용: 다른 데이터 파일 사용
            fileURL = URL(fileURLWithPath: args[i + 1])
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            let dir = support.appendingPathComponent("Todo", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            fileURL = dir.appendingPathComponent("todos.json")
        }
        load()
    }

    // MARK: - Mutations

    func add(title: String, note: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let item = TodoItem(title: t, note: note.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: Date())
        // 미완료 목록의 맨 끝(완료 항목 앞)에 추가
        let insertAt = items.lastIndex(where: { !$0.isDone }).map { $0 + 1 } ?? 0
        items.insert(item, at: insertAt)
        lastAddedID = item.id
        save()
    }

    func toggleDone(_ id: UUID) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var item = items.remove(at: i)
        item.isDone.toggle()
        item.doneAt = item.isDone ? Date() : nil
        if item.isDone {
            items.append(item)
        } else {
            // 되돌리면 미완료 목록 맨 끝으로
            let insertAt = items.lastIndex(where: { !$0.isDone }).map { $0 + 1 } ?? 0
            items.insert(item, at: insertAt)
        }
        save()
    }

    func update(_ id: UUID, title: String, note: String) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        items[i].title = t
        items[i].note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    /// 미완료 목록 내에서의 드래그 재정렬
    func movePending(from source: IndexSet, to destination: Int) {
        var p = pending
        p.move(fromOffsets: source, toOffset: destination)
        items = p + items.filter(\.isDone)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let decoded = try decoder.decode([TodoItem].self, from: data)
            // 미완료를 앞쪽으로 정규화
            items = decoded.filter { !$0.isDone } + decoded.filter(\.isDone)
        } catch {
            // 읽기 실패 시 다음 저장으로 덮어쓰지 않도록 원본을 백업
            NSLog("Todo: failed to load todos.json: \(error)")
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("broken-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
