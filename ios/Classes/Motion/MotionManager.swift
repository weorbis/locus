import Foundation
import CoreMotion
import CoreLocation

protocol MotionManagerDelegate: AnyObject {
    func onActivityChange(type: String, confidence: Int)
    func onMotionStateChange(isMoving: Bool)
}

class MotionManager {
    static let shared = MotionManager()
    
    weak var delegate: MotionManagerDelegate?
    private let motionManager = CMMotionActivityManager()
    private let config = ConfigManager.shared
    
    private(set) var lastActivityType = "unknown"
    private(set) var lastActivityConfidence = 0
    private(set) var isMoving = false
    
    private var stopTimeoutTimer: Timer?
    private var motionTriggerTimer: Timer?
    
    func start() {
        guard CMMotionActivityManager.isActivityAvailable(), !config.disableMotionActivityUpdates else { return }
        
        motionManager.startActivityUpdates(to: OperationQueue.main) { [weak self] activity in
            guard let self = self, let activity = activity else { return }
            self.handleActivity(activity)
        }
    }
    
    func stop() {
        motionManager.stopActivityUpdates()
        cancelStopTimeout()
        cancelMotionTrigger()
    }
    
    func setMovingManually(_ moving: Bool) {
        setMovingState(moving)
    }
    
    private func handleActivity(_ activity: CMMotionActivity) {
        let type = motionType(from: activity)
        let confidence = motionConfidence(activity.confidence)
        
        // Filter out low-confidence activities (parity with Android)
        if confidence < config.minimumActivityRecognitionConfidence {
            return
        }
        
        let changed = type != lastActivityType || confidence != lastActivityConfidence
        lastActivityType = type
        lastActivityConfidence = confidence
        
        if changed {
            delegate?.onActivityChange(type: type, confidence: confidence)
        }
        
        var moving = type != "still" && type != "unknown"
        if !config.triggerActivities.isEmpty {
            moving = config.triggerActivities.contains(type)
        }
        
        if moving {
            scheduleMotionTrigger()
        } else if !config.disableStopDetection {
            scheduleStopTimeout()
        }
    }
    
    private func scheduleMotionTrigger() {
        cancelStopTimeout()
        if isMoving { return }
        
        if config.motionTriggerDelayMs > 0 {
            if motionTriggerTimer != nil { return }
            motionTriggerTimer = Timer.scheduledTimer(withTimeInterval: Double(config.motionTriggerDelayMs) / 1000.0, repeats: false) { [weak self] _ in
                self?.setMovingState(true)
            }
        } else {
            setMovingState(true)
        }
    }
    
    private func scheduleStopTimeout() {
        cancelMotionTrigger()
        if !isMoving { return }
        
        if config.stopTimeoutMinutes > 0 {
            if stopTimeoutTimer != nil { return }
            stopTimeoutTimer = Timer.scheduledTimer(withTimeInterval: Double(config.stopTimeoutMinutes * 60), repeats: false) { [weak self] _ in
                self?.setMovingState(false)
            }
        } else {
            setMovingState(false)
        }
    }
    
    private func cancelStopTimeout() {
        stopTimeoutTimer?.invalidate()
        stopTimeoutTimer = nil
    }
    
    private func cancelMotionTrigger() {
        motionTriggerTimer?.invalidate()
        motionTriggerTimer = nil
    }
    
    private func setMovingState(_ moving: Bool) {
        if isMoving == moving { return }
        isMoving = moving
        delegate?.onMotionStateChange(isMoving: moving)
    }
    
    private func motionType(from activity: CMMotionActivity) -> String {
        if activity.stationary { return "still" }
        if activity.walking { return "walking" }
        if activity.running { return "running" }
        if activity.automotive { return "inVehicle" }
        if activity.cycling { return "onBicycle" }
        return "unknown"
    }
    
    private func motionConfidence(_ confidence: CMMotionActivityConfidence) -> Int {
        switch confidence {
        case .low: return 10
        case .medium: return 50
        case .high: return 100
        @unknown default: return 0
        }
    }
}
