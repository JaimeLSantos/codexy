import AppKit
import CodexyCore

/// "Export history…": the user picks a folder, two CSV files go in it, and Finder shows them. Nothing leaves the Mac.
enum Exporter {
    @MainActor static func run(model: AppModel) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true
        panel.prompt = L.t("export.prompt")
        panel.message = L.t("export.message")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        let history = model.history, known = model.projects
        Task.detached {
            // No project scanner yet: the projects file only when there is something in it.
            let files = [("codexy-limits.csv", Export.limits(history))] + (known.map { [("codexy-projects.csv", Export.projects($0))] } ?? [])
            var written: [URL] = []
            for (name, text) in files {
                let url = dir.appendingPathComponent(name)
                if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil { written.append(url) }
            }
            await MainActor.run { if !written.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(written) } }
        }
    }
}
