import Combine
import Dispatch
import Foundation

extension Effect {
  /// Throttles an effect so that it only publishes one output per given interval.
  ///
  /// - Parameters:
  ///   - id: The effect's identifier.
  ///   - interval: The interval at which to find and emit the most recent element, expressed in
  ///     the time system of the scheduler.
  ///   - scheduler: The scheduler you want to deliver the throttled output to.
  ///   - latest: A boolean value that indicates whether to publish the most recent element. If
  ///     `false`, the publisher emits the first element received during the interval.
  /// - Returns: An effect that emits either the most-recent or first element received during the
  ///   specified interval.
  public func throttle<S: Scheduler>(
    id: AnyHashable,
    for interval: S.SchedulerTimeType.Stride,
    scheduler: S,
    latest: Bool
  ) -> Self {
    switch self.operation {
    case .none:
      return .none
    case .publisher, .run:
      return self.receive(on: scheduler)
        .flatMap { value -> AnyPublisher<Output, Failure> in
          throttleLock.lock()
          defer { throttleLock.unlock() }

          guard let throttleTime = throttleTimes[id] as! S.SchedulerTimeType? else {
            throttleTimes[id] = scheduler.now
            throttleValues[id] = nil
            return Just(value).setFailureType(to: Failure.self).eraseToAnyPublisher()
          }

          let value = latest ? value : (throttleValues[id] as! Output? ?? value)
          throttleValues[id] = value

          guard throttleTime.distance(to: scheduler.now) < interval else {
            throttleTimes[id] = scheduler.now
            throttleValues[id] = nil
            return Just(value).setFailureType(to: Failure.self).eraseToAnyPublisher()
          }

          return Just(value)
            .delay(
              for: scheduler.now.distance(to: throttleTime.advanced(by: interval)),
              scheduler: scheduler
            )
            .handleEvents(
              receiveOutput: { _ in
                throttleLock.sync {
                  throttleTimes[id] = scheduler.now
                  throttleValues[id] = nil
                }
              }
            )
            .setFailureType(to: Failure.self)
            .eraseToAnyPublisher()
        }
        .eraseToEffect()
        .cancellable(id: id, cancelInFlight: true)
    }
  }

  /// Throttles an effect so that it only publishes one output per given interval.
  ///
  /// A convenience for calling ``Effect/throttle(id:for:scheduler:latest:)-5jfpx`` with a static
  /// type as the effect's unique identifier.
  ///
  /// - Parameters:
  ///   - id: The effect's identifier.
  ///   - interval: The interval at which to find and emit the most recent element, expressed in
  ///     the time system of the scheduler.
  ///   - scheduler: The scheduler you want to deliver the throttled output to.
  ///   - latest: A boolean value that indicates whether to publish the most recent element. If
  ///     `false`, the publisher emits the first element received during the interval.
  /// - Returns: An effect that emits either the most-recent or first element received during the
  ///   specified interval.
  public func throttle<S: Scheduler>(
    id: Any.Type,
    for interval: S.SchedulerTimeType.Stride,
    scheduler: S,
    latest: Bool
  ) -> Self {
    self.throttle(id: ObjectIdentifier(id), for: interval, scheduler: scheduler, latest: latest)
  }
}

var throttleTimes: [AnyHashable: Any] = [:]
var throttleValues: [AnyHashable: Any] = [:]
let throttleLock = NSRecursiveLock()
