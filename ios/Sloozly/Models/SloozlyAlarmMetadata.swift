import AlarmKit
import Foundation

struct SloozlyAlarmMetadata: AlarmMetadata {
    let backendAlarmId: String
    let label: String?

    init(backendAlarmId: String, label: String? = nil) {
        self.backendAlarmId = backendAlarmId
        self.label = label
    }
}
