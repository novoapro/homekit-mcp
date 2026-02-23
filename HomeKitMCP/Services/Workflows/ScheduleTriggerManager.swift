import Foundation

/// Manages timer-based schedule triggers for workflows.
/// Registers active schedules and fires them via WorkflowEngine.
actor ScheduleTriggerManager {
    private var scheduledTasks: [UUID: [Task<Void, Never>]] = [:]
    private weak var engine: WorkflowEngine?
    private var storage: StorageService?

    func setEngine(_ engine: WorkflowEngine) {
        self.engine = engine
    }

    func setStorage(_ storage: StorageService) {
        self.storage = storage
    }

    /// Reload all schedules from the given workflows.
    func reloadSchedules(workflows: [Workflow]) {
        cancelAll()
        for workflow in workflows where workflow.isEnabled {
            registerSchedules(for: workflow)
        }
    }

    /// Register schedule triggers for a single workflow.
    func registerSchedules(for workflow: Workflow) {
        guard workflow.isEnabled else { return }
        var tasks: [Task<Void, Never>] = []

        for trigger in workflow.triggers {
            if case .schedule(let scheduleTrigger) = trigger {
                let task = createScheduleTask(
                    workflowId: workflow.id,
                    trigger: scheduleTrigger
                )
                tasks.append(task)
            }
            if case .sunEvent(let sunEventTrigger) = trigger {
                let task = createSunEventTask(
                    workflowId: workflow.id,
                    trigger: sunEventTrigger
                )
                tasks.append(task)
            }
        }

        if !tasks.isEmpty {
            scheduledTasks[workflow.id] = tasks
        }
    }

    /// Cancel schedules for a specific workflow.
    func cancelSchedules(for workflowId: UUID) {
        scheduledTasks[workflowId]?.forEach { $0.cancel() }
        scheduledTasks.removeValue(forKey: workflowId)
    }

    /// Cancel all scheduled tasks.
    func cancelAll() {
        for (_, tasks) in scheduledTasks {
            tasks.forEach { $0.cancel() }
        }
        scheduledTasks.removeAll()
    }

    // MARK: - Private

    private func createScheduleTask(workflowId: UUID, trigger: ScheduleTrigger) -> Task<Void, Never> {
        let policy = trigger.retriggerPolicy
        return Task { [weak self] in
            switch trigger.scheduleType {
            case .once(let date):
                await self?.scheduleOnce(workflowId: workflowId, trigger: trigger, date: date, policy: policy)
            case .daily(let time):
                await self?.scheduleRepeating(workflowId: workflowId, trigger: trigger, policy: policy) {
                    Self.nextDailyDate(hour: time.hour, minute: time.minute)
                }
            case .weekly(let time, let days):
                await self?.scheduleRepeating(workflowId: workflowId, trigger: trigger, policy: policy) {
                    Self.nextWeeklyDate(hour: time.hour, minute: time.minute, days: days)
                }
            case .interval(let seconds):
                await self?.scheduleInterval(workflowId: workflowId, trigger: trigger, seconds: seconds, policy: policy)
            }
        }
    }

    private func scheduleOnce(workflowId: UUID, trigger: ScheduleTrigger, date: Date, policy: ConcurrentExecutionPolicy?) async {
        let delay = date.timeIntervalSinceNow
        guard delay > 0 else { return }

        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await fireTrigger(workflowId: workflowId, trigger: trigger, policy: policy)
        } catch {
            // Task cancelled
        }
    }

    private func scheduleRepeating(workflowId: UUID, trigger: ScheduleTrigger, policy: ConcurrentExecutionPolicy?, nextDate: @Sendable () -> Date?) async {
        while !Task.isCancelled {
            guard let next = nextDate() else { return }
            let delay = next.timeIntervalSinceNow
            guard delay > 0 else {
                // If next date is in the past (edge case), wait a minute and recalculate
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                continue
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await fireTrigger(workflowId: workflowId, trigger: trigger, policy: policy)
                // Wait 61 seconds to avoid re-triggering in the same minute
                try await Task.sleep(nanoseconds: 61_000_000_000)
            } catch {
                return // Task cancelled
            }
        }
    }

    private func scheduleInterval(workflowId: UUID, trigger: ScheduleTrigger, seconds: TimeInterval, policy: ConcurrentExecutionPolicy?) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await fireTrigger(workflowId: workflowId, trigger: trigger, policy: policy)
            } catch {
                return // Task cancelled
            }
        }
    }

    private func fireTrigger(workflowId: UUID, trigger: ScheduleTrigger, policy: ConcurrentExecutionPolicy?) async {
        guard let engine else { return }
        guard storage?.readWorkflowsEnabled() == true else { return }
        let description = Self.triggerDescription(trigger)
        let event = TriggerEvent(
            deviceId: nil,
            deviceName: nil,
            serviceId: nil,
            characteristicType: nil,
            oldValue: nil,
            newValue: nil,
            triggerDescription: description
        )
        _ = await engine.scheduleTrigger(id: workflowId, triggerEvent: event, policy: policy)
    }

    // MARK: - Date Calculation

    private static func nextDailyDate(hour: Int, minute: Int) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        guard let candidate = calendar.date(from: components) else { return nil }
        if candidate > now {
            return candidate
        }
        return calendar.date(byAdding: .day, value: 1, to: candidate)
    }

    private static func nextWeeklyDate(hour: Int, minute: Int, days: Set<ScheduleWeekday>) -> Date? {
        guard !days.isEmpty else { return nil }
        let calendar = Calendar.current
        let now = Date()

        for dayOffset in 0...7 {
            guard let candidateDay = calendar.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: candidateDay)
            guard let scheduleWeekday = ScheduleWeekday(rawValue: weekday), days.contains(scheduleWeekday) else { continue }

            var components = calendar.dateComponents([.year, .month, .day], from: candidateDay)
            components.hour = hour
            components.minute = minute
            components.second = 0

            guard let candidate = calendar.date(from: components) else { continue }
            if candidate > now {
                return candidate
            }
        }
        return nil
    }

    private static func triggerDescription(_ trigger: ScheduleTrigger) -> String {
        switch trigger.scheduleType {
        case .once(let date):
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            return "Schedule: Once at \(f.string(from: date))"
        case .daily(let time):
            return "Schedule: Daily at \(String(format: "%02d:%02d", time.hour, time.minute))"
        case .weekly(let time, let days):
            let dayNames = days.sorted().map(\.displayName).joined(separator: ", ")
            return "Schedule: \(dayNames) at \(String(format: "%02d:%02d", time.hour, time.minute))"
        case .interval(let seconds):
            if seconds >= 3600 {
                return "Schedule: Every \(Int(seconds / 3600))h"
            } else {
                return "Schedule: Every \(Int(seconds / 60))m"
            }
        }
    }

    // MARK: - Sun Event Triggers

    private func createSunEventTask(workflowId: UUID, trigger: SunEventTrigger) -> Task<Void, Never> {
        let policy = trigger.retriggerPolicy
        return Task { [weak self] in
            await self?.scheduleSunEventRepeating(workflowId: workflowId, trigger: trigger, policy: policy)
        }
    }

    private func scheduleSunEventRepeating(workflowId: UUID, trigger: SunEventTrigger, policy: ConcurrentExecutionPolicy?) async {
        while !Task.isCancelled {
            let latitude = storage?.readSunEventLatitude() ?? 0
            let longitude = storage?.readSunEventLongitude() ?? 0

            guard latitude != 0 || longitude != 0 else {
                AppLogger.workflow.warning("Sun event trigger: location not configured, retrying in 5 minutes")
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                continue
            }

            let now = Date()
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: now)
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else {
                try? await Task.sleep(nanoseconds: 3600_000_000_000)
                continue
            }

            let todayTimes = SolarCalculator.sunTimes(for: today, latitude: latitude, longitude: longitude)
            let tomorrowTimes = SolarCalculator.sunTimes(for: tomorrow, latitude: latitude, longitude: longitude)

            let nextFireDate: Date? = {
                let todayBase = trigger.event == .sunrise ? todayTimes.sunrise : todayTimes.sunset
                let tomorrowBase = trigger.event == .sunrise ? tomorrowTimes.sunrise : tomorrowTimes.sunset

                let todayTarget = todayBase.flatMap { calendar.date(byAdding: .minute, value: trigger.offsetMinutes, to: $0) }
                let tomorrowTarget = tomorrowBase.flatMap { calendar.date(byAdding: .minute, value: trigger.offsetMinutes, to: $0) }

                if let todayTarget, todayTarget > now { return todayTarget }
                return tomorrowTarget
            }()

            guard let fireDate = nextFireDate else {
                AppLogger.workflow.warning("Sun event trigger: could not compute next \(trigger.event.displayName) time (polar region?)")
                try? await Task.sleep(nanoseconds: 3600_000_000_000)
                continue
            }

            let delay = fireDate.timeIntervalSinceNow
            guard delay > 0 else {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                continue
            }

            let formatter = DateFormatter()
            formatter.dateStyle = .none
            formatter.timeStyle = .short
            AppLogger.workflow.info("Sun event trigger: next \(trigger.event.displayName) at \(formatter.string(from: fireDate)) (in \(Int(delay))s)")

            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await fireSunEventTrigger(workflowId: workflowId, trigger: trigger, policy: policy)
                // Wait 61 seconds to avoid re-triggering in the same minute
                try await Task.sleep(nanoseconds: 61_000_000_000)
            } catch {
                return // Cancelled
            }
        }
    }

    private func fireSunEventTrigger(workflowId: UUID, trigger: SunEventTrigger, policy: ConcurrentExecutionPolicy?) async {
        guard let engine else { return }
        guard storage?.readWorkflowsEnabled() == true else { return }
        let description = Self.sunEventDescription(trigger)
        let event = TriggerEvent(
            deviceId: nil,
            deviceName: nil,
            serviceId: nil,
            characteristicType: nil,
            oldValue: nil,
            newValue: nil,
            triggerDescription: description
        )
        _ = await engine.scheduleTrigger(id: workflowId, triggerEvent: event, policy: policy)
    }

    private static func sunEventDescription(_ trigger: SunEventTrigger) -> String {
        let offsetDesc: String
        if trigger.offsetMinutes == 0 {
            offsetDesc = ""
        } else if trigger.offsetMinutes > 0 {
            offsetDesc = " +\(trigger.offsetMinutes)min"
        } else {
            offsetDesc = " \(trigger.offsetMinutes)min"
        }
        return "Sun Event: \(trigger.event.displayName)\(offsetDesc)"
    }
}
