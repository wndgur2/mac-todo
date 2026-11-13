import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var window: NSWindow!
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()
        setupWindow()
        setupStatusItem()
        showWindow()
        installEscapeToClose()
        installKeyShortcuts()
        handleSnapshotRequest()
    }

    /// ESC: 열려 있는 팝오버/창만 닫는다 (앱은 종료하지 않음)
    private func installEscapeToClose() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53 else { return event }
            // 한글 조합 중이거나 행 편집 중이면 기본 동작에 맡김
            if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.hasMarkedText() { return event }
            if EditState.isEditing { return event }
            if self.popover.isShown {
                self.popover.performClose(nil)
                return nil
            }
            if NSApp.keyWindow === self.window {
                self.window.performClose(nil)
                return nil
            }
            return event
        }
    }

    /// ⌘Z / ⇧⌘Z 실행 취소·복귀, 비고 칸 ⇧Enter 줄바꿈.
    /// 팝오버(Dock 없는 상태)에서도 동작하도록 메뉴 단축키 대신 이벤트 모니터로 처리한다.
    private func installKeyShortcuts() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let window = event.window ?? NSApp.keyWindow
            let textView = window?.firstResponder as? NSTextView
            if let tv = textView, tv.hasMarkedText() { return event }  // 한글 조합 중

            // ⌘Z / ⇧⌘Z
            if event.charactersIgnoringModifiers?.lowercased() == "z",
               mods == .command || mods == [.command, .shift] {
                self.performUndo(redo: mods.contains(.shift), in: window)
                return nil
            }

            // 비고(여러 줄 입력칸)에서 ⇧Enter → 커서 위치에 줄바꿈
            if event.keyCode == 36 || event.keyCode == 76, mods == .shift,
               let tv = textView, Self.isMultilineField(tv) {
                tv.insertNewlineIgnoringFieldEditor(nil)
                return nil
            }
            return event
        }
    }

    /// 입력 중인 텍스트가 있으면 텍스트 실행 취소, 아니면 할 일 변경(생성·완료·편집·삭제·이동) 실행 취소
    private func performUndo(redo: Bool, in window: NSWindow? = NSApp.keyWindow) {
        if let tv = window?.firstResponder as? NSTextView, let um = tv.undoManager {
            let textCan = redo ? um.canRedo : um.canUndo
            // 행 편집 중에는 텍스트만 되돌린다 (편집 중인 항목이 사라지는 것 방지)
            if EditState.isEditing || (textCan && !tv.string.isEmpty) {
                if textCan { redo ? um.redo() : um.undo() } else { NSSound.beep() }
                return
            }
        }
        redo ? TodoStore.shared.redo() : TodoStore.shared.undo()
    }

    @objc private func undoAction(_ sender: Any?) { performUndo(redo: false) }
    @objc private func redoAction(_ sender: Any?) { performUndo(redo: true) }

    /// SwiftUI `TextField(axis: .vertical)` 의 필드 편집기인지 (줄바꿈 허용 칸)
    private static func isMultilineField(_ tv: NSTextView) -> Bool {
        guard tv.isFieldEditor, let field = tv.delegate as? NSTextField else { return false }
        return !field.usesSingleLineMode && field.cell?.isScrollable == false
    }

    /// 디버그용: `--snapshot <dir>` 로 실행하면 메인 창/팝오버를 PNG로 저장 (화면 녹화 권한 불필요)
    private func handleSnapshotRequest() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1], isDirectory: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            Self.writePNG(of: self.window.contentView, to: dir.appendingPathComponent("main.png"))
            if let button = self.statusItem.button {
                self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Self.writePNG(of: self.popover.contentViewController?.view, to: dir.appendingPathComponent("popover.png"))
                self.popover.performClose(nil)
            }
        }
    }

    private static func writePNG(of view: NSView?, to url: URL) {
        guard let view, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    /// 창을 닫아도 앱은 계속 실행 (상태바에 남음)
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dock 아이콘 클릭 / Finder에서 재실행 시 창 다시 띄우기
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    // MARK: - Window

    private func setupWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Todo"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: MainView())
        window.center()
        window.setFrameAutosaveName("TodoMainWindow")
    }

    @objc func showWindow() {
        popover.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// x 버튼(또는 ⌘W): 창만 숨기고 Dock에서 제거, 상태바에는 유지
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "checklist", accessibilityDescription: "Todo")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        popover.animates = false
        // SwiftUI가 표시 이후 크기를 바꾸면 팝오버가 위로 밀려 상단이 잘리므로 크기를 고정
        let hosting = NSHostingController(
            rootView: PopoverView(
                openWindow: { [weak self] in self?.showWindow() },
                quit: { NSApp.terminate(nil) }
            )
        )
        hosting.sizingOptions = []
        hosting.view.frame = NSRect(origin: .zero, size: PopoverView.size)
        popover.contentViewController = hosting
        popover.contentSize = PopoverView.size

        TodoStore.shared.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                let count = items.filter { !$0.isDone }.count
                self?.statusItem.button?.title = count > 0 ? " \(count)" : ""
            }
            .store(in: &cancellables)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        if popover.isShown {
            popover.performClose(sender)
        } else if window.isVisible || window.isMiniaturized {
            // 창이 이미 열려 있으면 팝오버 대신 창을 앞으로
            if window.isMiniaturized { window.deminiaturize(nil) }
            showWindow()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "창 열기", action: #selector(showWindow), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Todo 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Main menu (⌘Q, 편집 단축키 등)

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Todo 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Todo 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Todo 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "편집")
        editMenu.addItem(withTitle: "실행 취소", action: #selector(undoAction(_:)), keyEquivalent: "z").target = self
        let redo = editMenu.addItem(withTitle: "실행 복귀", action: #selector(redoAction(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = self
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "전체 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "윈도우")
        windowMenu.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }
}
