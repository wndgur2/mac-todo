import SwiftUI
import AppKit

// MARK: - Helpers

private let createdFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = "yyyy.MM.dd (E) HH:mm"
    return f
}()

/// 비고 문자열에서 URL을 찾아 클릭 가능한 링크로 변환
func linkified(_ text: String) -> AttributedString {
    var attr = AttributedString(text)
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return attr
    }
    let ns = NSRange(text.startIndex..., in: text)
    for match in detector.matches(in: text, range: ns) {
        guard let url = match.url,
              let r = Range(match.range, in: text),
              let ar = Range(r, in: attr) else { continue }
        attr[ar].link = url
        attr[ar].underlineStyle = .single
        attr[ar].foregroundColor = .accentColor
    }
    return attr
}

/// 링크는 항상 기본 브라우저로 연다
private let openInDefaultBrowser = OpenURLAction { url in
    NSWorkspace.shared.open(url)
    return .handled
}

/// 행 편집 중이면 ESC는 편집 취소에 쓰고 창을 닫지 않는다
enum EditState {
    static var isEditing = false
    /// 디버그용: `--show-actions` 로 실행하면 hover 없이도 액션 버튼 표시
    static let alwaysShowActions = CommandLine.arguments.contains("--show-actions")
}

/// 입력칸을 코드로 비운 뒤 남은 타이핑 실행 취소 기록을 지운다.
/// (이후 ⌘Z가 지워진 글자를 되살리지 않고 할 일 변경을 되돌리도록)
func clearTextUndo() {
    NSApp.keyWindow?.firstResponder?.undoManager?.removeAllActions()
    NSApp.keyWindow?.undoManager?.removeAllActions()
}

// MARK: - Add bar

struct AddBar: View {
    @ObservedObject var store = TodoStore.shared
    var compact: Bool = false

    @State private var title = ""
    @State private var note = ""
    @FocusState private var focus: Field?
    private enum Field { case title, note }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("할 일 추가", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: compact ? 14 : 15, weight: .semibold))
                .focused($focus, equals: .title)
                .onSubmit(add)
            TextField("비고", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...6)
                .focused($focus, equals: .note)
                .onSubmit(add)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .onAppear { focus = .title }
    }

    private func add() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            store.add(title: title, note: note)
        }
        title = ""
        note = ""
        focus = .title
        clearTextUndo()
    }
}

// MARK: - Row

struct TodoRow: View {
    let item: TodoItem
    @ObservedObject var store = TodoStore.shared
    var compact: Bool = false

    @State private var hovering = false
    @State private var editing = false
    @State private var editTitle = ""
    @State private var editNote = ""
    @FocusState private var editFocus: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Group {
                if editing {
                    editor
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if (hovering || EditState.alwaysShowActions) && !editing {
                actions
            }
        }
        .padding(.vertical, compact ? 4 : 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button(item.isDone ? "되돌리기" : "완료") { toggleDone() }
            if !item.isDone { Button("편집") { beginEdit() } }
            Divider()
            Button("삭제", role: .destructive) { store.delete(item.id) }
        }
    }

    /// hover 시 오른쪽에 뜨는 액션: [편집] [삭제] [완료]  /  완료 항목: [삭제] [되돌리기]
    private var actions: some View {
        HStack(spacing: 2) {
            if !item.isDone {
                ActionButton(symbol: "pencil", help: "편집") { beginEdit() }
            }
            ActionButton(symbol: "trash", help: "삭제") {
                withAnimation { store.delete(item.id) }
            }
            if item.isDone {
                ActionButton(symbol: "arrow.uturn.backward", help: "되돌리기") { toggleDone() }
            } else {
                ActionButton(symbol: "checkmark", help: "완료") { toggleDone() }
            }
        }
    }

    private func toggleDone() {
        withAnimation(.easeOut(duration: 0.2)) { store.toggleDone(item.id) }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.system(size: compact ? 13.5 : 14.5, weight: .semibold))
                .foregroundStyle(item.isDone ? Color.secondary : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !item.note.isEmpty {
                Text(linkified(item.note))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, openInDefaultBrowser)
            }
            Text(createdFormatter.string(from: item.createdAt))
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary.opacity(0.7))
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("제목", text: $editTitle)
                .textFieldStyle(.plain)
                .font(.system(size: compact ? 13.5 : 14.5, weight: .semibold))
                .focused($editFocus)
                .onSubmit(commitEdit)
            TextField("비고", text: $editNote, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(1...8)
                .onSubmit(commitEdit)
            HStack(spacing: 8) {
                Button("저장", action: commitEdit).keyboardShortcut(.defaultAction)
                Button("취소") { editing = false }.keyboardShortcut(.cancelAction)
            }
            .controlSize(.small)
            .padding(.top, 2)
        }
        .onExitCommand { editing = false }
        .onAppear { EditState.isEditing = true }
        .onDisappear { EditState.isEditing = false }
    }


    private func beginEdit() {
        editTitle = item.title
        editNote = item.note
        editing = true
        DispatchQueue.main.async { editFocus = true }
    }

    private func commitEdit() {
        store.update(item.id, title: editTitle, note: editNote)
        editing = false
        clearTextUndo()
    }
}

struct ActionButton: View {
    let symbol: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(hovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - List

/// 할 일 / 완료 두 섹션. 각각 접을 수 있고, 둘 다 펼치면 높이를 반반 나눠 각자 스크롤.
struct TodoListView: View {
    @ObservedObject var store = TodoStore.shared
    var compact: Bool = false
    @AppStorage("showPending") private var showPending = true
    @AppStorage("showDone") private var showDone = false

    var body: some View {
        let pending = store.pending
        let done = store.done

        VStack(spacing: 0) {
            SectionHeader(title: "할 일", count: pending.count, expanded: $showPending)
            if showPending {
                ScrollViewReader { proxy in
                    List {
                        if pending.isEmpty {
                            Text("할 일이 없습니다 🎉")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 16)
                                .moveDisabled(true)
                        } else {
                            ForEach(pending) { item in
                                TodoRow(item: item, compact: compact)
                                    .id(item.id)
                            }
                            .onMove { from, to in
                                withAnimation { store.movePending(from: from, to: to) }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .onChange(of: store.lastAddedID) { _, id in
                        guard let id else { return }
                        // 새 행의 실제 높이가 계산된 뒤 다시 맞추도록 두 번 스크롤
                        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .bottom) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .bottom) }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }

            Divider()

            SectionHeader(title: "완료", count: done.count, expanded: $showDone)
            if showDone {
                List {
                    if done.isEmpty {
                        Text("완료한 항목이 없습니다")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(done) { item in
                            TodoRow(item: item, compact: compact)
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)
            }

            if !showPending && !showDone {
                Spacer(minLength: 0)
            }
        }
        .onChange(of: store.lastAddedID) { _, _ in
            if !showPending { withAnimation(.easeOut(duration: 0.15)) { showPending = true } }
        }
    }
}

/// 섹션 헤더. 행 전체를 눌러 펼치기/접기
struct SectionHeader: View {
    let title: String
    let count: Int
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 10)
                Text("\(title) \(count)")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main window

struct MainView: View {
    var body: some View {
        VStack(spacing: 0) {
            AddBar()
                .padding([.horizontal, .top], 14)
                .padding(.bottom, 6)
            TodoListView()
        }
        .frame(minWidth: 340, minHeight: 360)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Menu bar popover

struct PopoverView: View {
    static let size = NSSize(width: 360, height: 480)
    var openWindow: () -> Void
    var quit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AddBar(compact: true)
                .padding([.horizontal, .top], 10)
                .padding(.bottom, 4)
            TodoListView(compact: true)
            Divider()
            HStack {
                Button {
                    openWindow()
                } label: {
                    Label("창 열기", systemImage: "macwindow")
                }
                Spacer()
                Button {
                    quit()
                } label: {
                    Label("종료", systemImage: "power")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}
