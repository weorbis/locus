import Foundation

extension SwiftLocusPlugin {
  func appendLog(_ message: String, level: String) {
    if !shouldLog(level: level) {
      return
    }
    let existing = readLog()
    let entry = "\(Date().timeIntervalSince1970)|\(level)|\(message)"
    var next = existing.isEmpty ? entry : "\(existing)\n\(entry)"
    if configManager.logMaxDays > 0 {
      next = pruneLog(next, maxDays: configManager.logMaxDays)
    }
    UserDefaults.standard.setValue(next, forKey: "bg_log")
  }

  func readLog() -> String {
    return UserDefaults.standard.string(forKey: "bg_log") ?? ""
  }

  private func pruneLog(_ log: String, maxDays: Int) -> String {
    let cutoff = Date().timeIntervalSince1970 - Double(maxDays * 24 * 60 * 60)
    let lines = log.split(separator: "\n")
    var kept: [Substring] = []
    for line in lines {
      let parts = line.split(separator: "|", maxSplits: 2)
      if parts.count < 2 {
        continue
      }
      if let timestamp = Double(parts[0]), timestamp >= cutoff {
        kept.append(line)
      }
    }
    return kept.joined(separator: "\n")
  }

  private func shouldLog(level: String) -> Bool {
    return logLevelRank(level) <= logLevelRank(configManager.logLevel)
  }

  private func logLevelRank(_ level: String) -> Int {
    switch level {
    case "off":
      return 6
    case "error":
      return 0
    case "warning":
      return 1
    case "info":
      return 2
    case "debug":
      return 3
    case "verbose":
      return 4
    default:
      return 3
    }
  }
}
