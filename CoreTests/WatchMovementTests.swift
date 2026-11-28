import Foundation
import Testing
@testable import DailyFlowCore

@Suite("Watch movement")
struct WatchMovementTests {
    private let wheels = WatchMovement.allWheels

    private func near(_ value: Double, _ expected: Double, _ tolerance: Double = 1e-9) -> Bool {
        abs(value - expected) <= tolerance
    }

    private func wheel(_ id: Int) -> WatchWheel {
        guard let found = wheels.first(where: { $0.id == id }) else {
            Issue.record("No wheel with id \(id)")
            return wheels[0]
        }
        return found
    }

    /// Wheels that are driven by another wheel.
    private var driven: [WatchWheel] { wheels.filter { $0.meshesWith != nil } }

    // MARK: Inventory

    @Test func thereAreExactlyEightTaskSlotsInSizeOrder() {
        let slots = WatchMovement.taskWheels
        #expect(slots.count == WatchGeometry.taskGearSlots)
        #expect(slots.compactMap(\.taskSlot) == Array(0..<WatchGeometry.taskGearSlots))
        // Slot 0 is the largest and the sizes never grow with the slot number.
        for (bigger, smaller) in zip(slots, slots.dropFirst()) {
            #expect(bigger.tipRadius >= smaller.tipRadius)
        }
        #expect(near(slots[0].tipRadius, slots.map(\.tipRadius).max() ?? 0))
    }

    @Test func aboutTwentyWheelsAndOneBarrel() {
        #expect(WatchMovement.wheels.count == 20)
        #expect(WatchMovement.barrel.role == .barrel)
        #expect(Set(wheels.map(\.id)).count == wheels.count)
        #expect(WatchMovement.wheels.filter { $0.role == .keyless }.count >= 3)
    }

    @Test func everyWheelSitsInsideTheOpening() {
        for wheel in wheels {
            let reach = wheel.center.radius + wheel.tipRadius
            #expect(reach <= WatchMovement.openingRadius, "wheel \(wheel.id) reaches \(reach)")
        }
    }

    @Test func teethAreWellFormed() {
        for wheel in wheels {
            #expect(wheel.teeth >= 6)
            #expect(wheel.rootRadius < wheel.pitchRadius)
            #expect(wheel.pitchRadius < wheel.tipRadius)
        }
    }

    // MARK: Meshing

    @Test func meshingNeighboursSitAtTheSumOfTheirPitchRadii() {
        #expect(!driven.isEmpty)
        for wheel in driven {
            guard let driverID = wheel.meshesWith else { continue }
            let driver = self.wheel(driverID)
            let distance = wheel.center.distance(to: driver.center)
            #expect(near(distance, wheel.pitchRadius + driver.pitchRadius, 1e-9), "wheel \(wheel.id)")
            // Tip circles overlap, as meshing teeth do, but the roots never collide.
            #expect(distance < wheel.tipRadius + driver.tipRadius)
            #expect(distance > wheel.rootRadius + driver.rootRadius)
        }
    }

    @Test func meshingWheelsTurnOppositeWaysInInverseRatioToTheirTeeth() {
        for wheel in driven {
            guard let driverID = wheel.meshesWith else { continue }
            let driver = self.wheel(driverID)
            #expect(wheel.baseRate * driver.baseRate < 0, "wheel \(wheel.id) turns with its driver")
            // Pitch speed is shared: rate x teeth is equal and opposite.
            #expect(near(wheel.baseRate * Double(wheel.teeth), -driver.baseRate * Double(driver.teeth), 1e-9))
        }
    }

    @Test func teethInterleaveAtEveryMoment() {
        for wheel in driven {
            guard let driverID = wheel.meshesWith else { continue }
            let driver = self.wheel(driverID)
            let toward = atan2(
                wheel.center.y - driver.center.y,
                wheel.center.x - driver.center.x
            ) * 180 / .pi
            for seconds in [0.0, 1.7, 41.3, 5_000.9] {
                let driverAngle = driver.angle(atSeconds: seconds)
                let wheelAngle = wheel.angle(atSeconds: seconds)
                // Position of the contact point in tooth pitches, from a tooth centre on each wheel.
                let driverOffset = (toward - driverAngle) * Double(driver.teeth) / 360
                let wheelOffset = (toward + 180 - wheelAngle) * Double(wheel.teeth) / 360
                let sum = driverOffset + wheelOffset
                let fraction = sum - sum.rounded(.down)
                #expect(near(fraction, 0.5, 1e-6), "wheel \(wheel.id) at \(seconds)s: \(fraction)")
            }
        }
    }

    @Test func everyTrainHasARootAndEveryDriverExists() {
        let ids = Set(wheels.map(\.id))
        let roots = wheels.filter { $0.meshesWith == nil }
        #expect(roots.count == 2)
        for wheel in driven {
            guard let driverID = wheel.meshesWith else { continue }
            #expect(ids.contains(driverID), "wheel \(wheel.id) has no driver")
        }
    }

    // MARK: Collisions

    @Test func nonMeshingWheelsNeverOverlapOnTheSameLayer() {
        for first in wheels {
            for second in wheels where second.id > first.id && second.layer == first.layer {
                let meshes = first.meshesWith == second.id || second.meshesWith == first.id
                guard !meshes else { continue }
                let distance = first.center.distance(to: second.center)
                #expect(
                    distance >= first.tipRadius + second.tipRadius,
                    "wheels \(first.id) and \(second.id) overlap"
                )
            }
        }
    }

    // MARK: Escapement, crown, bridges

    @Test func balanceAndForkStayInsideAndClearOfTheTrain() {
        let balance = WatchMovement.balance
        #expect(balance.center.radius + balance.radius <= WatchMovement.openingRadius)
        for wheel in wheels {
            #expect(
                wheel.center.distance(to: balance.center) >= wheel.tipRadius + balance.radius,
                "wheel \(wheel.id) touches the balance"
            )
        }
        let fork = WatchMovement.fork
        #expect(fork.pivot.radius + fork.tailLength <= WatchMovement.openingRadius)
        #expect(fork.pivot.radius + fork.armLength <= WatchMovement.openingRadius)
        #expect(wheel(fork.escapeWheel).center.distance(to: fork.pivot) < 0.3)
    }

    @Test func balanceAndForkSwingWithinTheirAmplitude() {
        for seconds in stride(from: 0.0, through: 3.0, by: 0.037) {
            #expect(abs(WatchMovement.balanceAngle(atSeconds: seconds)) <= WatchMovement.balance.swingDegrees + 1e-9)
            #expect(abs(WatchMovement.forkAngle(atSeconds: seconds)) <= WatchMovement.fork.swingDegrees + 1e-9)
        }
        // One beat period later the balance is back where it was.
        let period = 1 / WatchMovement.beatFrequency
        #expect(near(
            WatchMovement.balanceAngle(atSeconds: 0.31),
            WatchMovement.balanceAngle(atSeconds: 0.31 + period * 7),
            1e-6
        ))
    }

    @Test func crownSitsOutsideTheOpeningAndItsStemReachesTheKeylessWorks() {
        let crown = WatchMovement.crown
        #expect(crown.center.radius > WatchMovement.openingRadius)
        #expect(wheel(crown.windingWheel).role == .keyless)
        #expect(crown.stemEnd == wheel(crown.windingWheel).center)
    }

    @Test func bridgeArmsNeverCoverAToothContact() {
        for bridge in WatchMovement.bridges where bridge.hubs.count >= 2 && bridge.layer < 2 {
            for wheel in driven {
                guard let driverID = wheel.meshesWith else { continue }
                let driver = self.wheel(driverID)
                // The point where the two pitch circles touch.
                let along = driver.pitchRadius / (driver.pitchRadius + wheel.pitchRadius)
                let contact = WatchPoint(
                    x: driver.center.x + (wheel.center.x - driver.center.x) * along,
                    y: driver.center.y + (wheel.center.y - driver.center.y) * along
                )
                for (from, to) in zip(bridge.hubs, bridge.hubs.dropFirst()) {
                    let gap = distance(from: contact, toSegment: from, to)
                    #expect(gap > 8.0 / 122.0, "an arm covers the contact of wheels \(driver.id) and \(wheel.id)")
                }
            }
        }
    }

    /// Distance from a point to a line segment.
    private func distance(from point: WatchPoint, toSegment start: WatchPoint, _ end: WatchPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let along = ((point.x - start.x) * dx + (point.y - start.y) * dy) / (dx * dx + dy * dy)
        let t = min(max(along, 0), 1)
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }

    @Test func bridgesAreClosedOutlinesInsideTheOpeningCarryingRealHubs() {
        let pivots = Set(WatchMovement.allWheels.map(\.center))
        #expect(WatchMovement.bridges.count >= 6)
        #expect(WatchMovement.bridges.contains { $0.hubs.count >= 3 }, "there are long arms as well as caps")
        for bridge in WatchMovement.bridges {
            #expect(bridge.outline.count >= 12)
            #expect(bridge.hubs.count >= 1)
            for point in bridge.outline {
                #expect(point.radius <= WatchMovement.openingRadius, "bridge \(bridge.id) leaves the opening")
            }
            // Every arm but the balance cock ends on a wheel's pivot.
            if bridge.id < WatchMovement.bridges.count - 1 {
                for hub in bridge.hubs {
                    #expect(pivots.contains(hub), "bridge \(bridge.id) hub is not a pivot")
                }
            }
        }
    }

    @Test func everyWheelPivotIsCarriedByABridge() {
        let carried = WatchMovement.bridges.flatMap(\.hubs)
        for wheel in wheels {
            #expect(carried.contains(wheel.center), "wheel \(wheel.id) has no bridge")
        }
        #expect(carried.contains(WatchMovement.barrel.center))
    }

    // MARK: Angles

    @Test func wheelAnglesAreWrappedAndScaleWithRate() {
        for wheel in wheels {
            let angle = wheel.angle(atSeconds: 123_456.7)
            #expect(angle >= 0 && angle < 360)
        }
        let centre = wheel(1)
        let slow = centre.angle(atSeconds: 10)
        let fast = centre.angle(atSeconds: 10, rateScale: WatchGeometry.liveSpinRate)
        let expectedSlow = WatchGeometry.wrap(centre.phase + centre.baseRate * 10, 360)
        let expectedFast = WatchGeometry.wrap(centre.phase + centre.baseRate * 10 * WatchGeometry.liveSpinRate, 360)
        #expect(near(slow, expectedSlow, 1e-9))
        #expect(near(fast, expectedFast, 1e-9))
    }
}
