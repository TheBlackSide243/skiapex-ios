import CoreLocation
import Foundation
import HealthKit

enum HealthError: LocalizedError {
    case unavailable
    case refused(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            String(localized: "Salute non è disponibile su questo dispositivo.")
        case .refused(let why):
            String(localized: "Non sono riuscito a usare Salute. Con l'app installata da Feather può non essere disponibile: usa la versione di TestFlight. (\(why))")
        }
    }
}

/// A day in Apple Health: saved as a skiing or snowboarding workout with its route, and the heart
/// rate of those hours read back (from an Apple Watch, if one was worn).
enum HealthSync {
    private static let store = HKHealthStore()

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Saves the day in Health if it is not there yet, and reads its heart rate.
    @MainActor static func save(_ id: UUID) async throws {
        guard available else { throw HealthError.unavailable }
        guard let day = Shared.library.day(id) else { return }
        let distanceType = HKQuantityType(.distanceDownhillSnowSports)
        let heartType = HKQuantityType(.heartRate)
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), distanceType],
                                                 read: [heartType])
            var saved = day.inHealth == true
            if !saved {
                let configuration = HKWorkoutConfiguration()
                configuration.activityType = day.sport == .snowboard ? .snowboarding : .downhillSkiing
                configuration.locationType = .outdoor
                let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
                try await builder.beginCollection(at: day.start)
                if day.stats.runDistance > 0 {
                    let distance = HKQuantitySample(type: distanceType,
                                                    quantity: HKQuantity(unit: .meter(), doubleValue: day.stats.runDistance),
                                                    start: day.start, end: day.end)
                    try await builder.addSamples([distance])
                }
                try await builder.endCollection(at: day.end)
                if let workout = try await builder.finishWorkout() {
                    saved = true
                    // The route is extra: the workout stays even if it cannot be added.
                    try? await addRoute(of: day, to: workout)
                }
            }
            let heart = await heartRate(heartType, from: day.start, to: day.end)
            // Read again: the day may have changed in the meantime.
            guard var fresh = Shared.library.day(id) else { return }
            if saved { fresh.inHealth = true }
            if let heart {
                fresh.heartAvg = heart.average
                fresh.heartMax = heart.top
            }
            try Shared.library.save(fresh)
        } catch let error as HealthError {
            throw error
        } catch {
            throw HealthError.refused(error.localizedDescription)
        }
    }

    private static func addRoute(of day: SkiDay, to workout: HKWorkout) async throws {
        let route = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        let locations = day.points.map {
            CLLocation(coordinate: $0.coordinate, altitude: $0.alt, horizontalAccuracy: max(1, $0.hAcc), verticalAccuracy: 5,
                       course: -1, speed: max(0, $0.speed), timestamp: $0.t)
        }
        var i = 0
        while i < locations.count {
            let end = min(locations.count, i + 2000)
            try await route.insertRouteData(Array(locations[i..<end]))
            i = end
        }
        _ = try await route.finishRoute(with: workout, metadata: nil)
    }

    /// The average and the highest heart rate between two moments; nil when Health has none.
    private static func heartRate(_ type: HKQuantityType, from: Date, to: Date) async -> (average: Double, top: Double)? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: [.discreteAverage, .discreteMax]) { _, statistics, _ in
                let unit = HKUnit.count().unitDivided(by: .minute())
                if let average = statistics?.averageQuantity()?.doubleValue(for: unit),
                   let top = statistics?.maximumQuantity()?.doubleValue(for: unit) {
                    continuation.resume(returning: (average, top))
                } else {
                    continuation.resume(returning: nil)
                }
            }
            store.execute(query)
        }
    }
}
