import Foundation

// A running agent session and the git checkout it works in. Codex sessions come from CodexSessions.

public struct AgentSession: Equatable, Sendable, Identifiable {
    /// One process can hold several threads (the app-server of the Codex app), so the thread id names a session.
    public var id: String { thread.isEmpty ? "pid:\(pid)" : thread }
    public var pid: Int32
    public var name: String
    public var cwd: String
    public var busy: Bool
    public var waiting: Bool
    public var git: GitInfo?
    public var thread: String
    public init(pid: Int32, name: String, cwd: String, busy: Bool, waiting: Bool, git: GitInfo?, thread: String = "") {
        self.pid = pid; self.name = name; self.cwd = cwd; self.busy = busy; self.waiting = waiting; self.git = git; self.thread = thread
    }
}

/// Where a session works: the repo, the branch, and whether it is a linked worktree.
public struct GitInfo: Equatable, Sendable {
    public var repo: String
    public var branch: String
    public var worktree: String?   // folder name of the linked worktree, nil in the main checkout
    public init(repo: String, branch: String, worktree: String?) { self.repo = repo; self.branch = branch; self.worktree = worktree }
}

public enum Git {
    /// Reads .git by hand (no `git` process every few seconds). cwd may be a subfolder of the repo.
    public static func info(cwd: String) -> GitInfo? {
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: cwd)
        for _ in 0..<12 {
            let dot = dir.appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dot.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    return GitInfo(repo: dir.lastPathComponent, branch: branch(gitDir: dot), worktree: nil)
                }
                // Linked worktree: ".git" is a file "gitdir: <repo>/.git/worktrees/<name>".
                guard let txt = try? String(contentsOf: dot, encoding: .utf8),
                      txt.hasPrefix("gitdir:") else { return nil }
                let gd = URL(fileURLWithPath: txt.dropFirst(7).trimmingCharacters(in: .whitespacesAndNewlines))
                let repo = gd.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                return GitInfo(repo: repo.lastPathComponent, branch: branch(gitDir: gd), worktree: dir.lastPathComponent)
            }
            let up = dir.deletingLastPathComponent()
            if up.path == dir.path { break }
            dir = up
        }
        return nil
    }

    static func branch(gitDir: URL) -> String {
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return "?" }
        if head.hasPrefix("ref: refs/heads/") { return String(head.dropFirst(16)) }
        return String(head.prefix(7))   // detached HEAD
    }
}
