import Foundation

func parseDuration(_ durationStr: String) -> TimeInterval? {
    let components = durationStr.split(separator: " ")
    var totalDuration: TimeInterval = 0

    for component in components {
        if component.hasSuffix("h") {
            if let hours = Double(component.dropLast()) {
                totalDuration += hours * 3600
            }
        } else if component.hasSuffix("min") {
            if let minutes = Double(component.dropLast(3)) {
                totalDuration += minutes * 60
            }
        } else if component.hasSuffix("s") {
            if let seconds = Double(component.dropLast()) {
                totalDuration += seconds
            }
        }
    }
    return totalDuration
}
