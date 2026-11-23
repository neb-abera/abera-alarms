import Foundation

/// Where a step stands in its ring: rung and not checked off, still to
/// ring, or checked off. On 2026-11-23 Neb asked for rung and coming steps
/// to look apart at a glance, by color or a status mark, after the time
/// text alone left him reading each line.
public enum StepStatus: String, Sendable {
    case rang = "Rang"
    case coming = "Coming"
    case done = "Done"

    public static func of(ringAt: Date, done: Bool, now: Date) -> StepStatus {
        if done { return .done }
        return ringAt > now ? .coming : .rang
    }
}
