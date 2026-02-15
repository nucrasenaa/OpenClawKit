import Foundation

public struct CronJob: Sendable, Equatable {
    public let id: String
    public var intervalSeconds: Int
    public var enabled: Bool
    public var payload: String
    public var nextRunAt: Date

    public init(
        id: String,
        intervalSeconds: Int,
        enabled: Bool = true,
        payload: String,
        nextRunAt: Date
    ) {
        self.id = id
        self.intervalSeconds = max(1, intervalSeconds)
        self.enabled = enabled
        self.payload = payload
        self.nextRunAt = nextRunAt
    }
}

public struct CronRunResult: Sendable, Equatable {
    public let jobID: String
    public let payload: String
    public let ranAt: Date

    public init(jobID: String, payload: String, ranAt: Date) {
        self.jobID = jobID
        self.payload = payload
        self.ranAt = ranAt
    }
}

public actor CronScheduler {
    private var jobs: [String: CronJob] = [:]

    public init() {}

    public func addOrUpdate(_ job: CronJob) {
        self.jobs[job.id] = job
    }

    public func remove(id: String) {
        self.jobs.removeValue(forKey: id)
    }

    public func list() -> [CronJob] {
        self.jobs.values.sorted { $0.id < $1.id }
    }

    public func runDue(now: Date = Date()) -> [CronRunResult] {
        var results: [CronRunResult] = []
        for id in self.jobs.keys.sorted() {
            guard var job = self.jobs[id], job.enabled else { continue }
            if job.nextRunAt <= now {
                let result = CronRunResult(jobID: job.id, payload: job.payload, ranAt: now)
                results.append(result)
                job.nextRunAt = now.addingTimeInterval(TimeInterval(job.intervalSeconds))
                self.jobs[id] = job
            }
        }
        return results
    }
}

