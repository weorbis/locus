import Foundation

extension SwiftLocusPlugin {
  func appendLog(_ message: String, level: String) {
    if !shouldLog(level: level) {
      return
    }
    let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
    storage.insertLog(timestampMs: timestampMs,
                      level: level,
                      message: message,
                      tag: "locus")
    if configManager.logMaxDays > 0 {
      storage.pruneLogs(maxDays: configManager.logMaxDays)
    }
  }

  func readLog() -> [[String: Any]] {
    return storage.readLogs()
  }

  private func shouldLog(level: String) -> Bool {
    if configManager.logLevel == "off" { return false }
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
