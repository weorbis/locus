import Foundation
import CoreLocation

protocol SchedulerDelegate: AnyObject {
    func onScheduleCheck(shouldBeEnabled: Bool)
}

class Scheduler {
    static let shared = Scheduler()
    
    weak var delegate: SchedulerDelegate?
    private let config = ConfigManager.shared
    private var scheduleTimer: Timer?
    
    func start() {
        guard config.scheduleEnabled, scheduleTimer == nil else { return }
        
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.applyScheduleState()
        }
        applyScheduleState()
    }
    
    func stop() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
    }
    
    func applyScheduleState() {
        guard config.scheduleEnabled, !config.schedule.isEmpty else { return }
        
        let shouldEnable = isWithinScheduleWindow()
        delegate?.onScheduleCheck(shouldBeEnabled: shouldEnable)
    }
    
    private func isWithinScheduleWindow() -> Bool {
        let now = Date()
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let nowMinutes = hour * 60 + minute
        
        for entry in config.schedule {
            let parts = entry.split(separator: "-").map { String($0) }
            if parts.count != 2 { continue }
            
            guard let start = parseMinutes(parts[0]),
                  let end = parseMinutes(parts[1]) else { continue }
            
            if end < start {
                // Crosses midnight
                if nowMinutes >= start || nowMinutes < end {
                    return true
                }
            } else {
                if nowMinutes >= start && nowMinutes < end {
                    return true
                }
            }
        }
        
        return false
    }
    
    private func parseMinutes(_ time: String) -> Int? {
        let parts = time.split(separator: ":").map { String($0) }
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]) else {
            return nil
        }
        return hours * 60 + minutes
    }
}
