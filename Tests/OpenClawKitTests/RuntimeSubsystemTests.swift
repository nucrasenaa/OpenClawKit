import Foundation
import Testing
@testable import OpenClawKit

@Suite("Runtime subsystems")
struct RuntimeSubsystemTests {
    @Test
    func memorySearchReturnsScoredResults() async {
        let memory = MemoryIndex()
        await memory.upsert(MemoryDocument(id: "1", source: .userMessage, text: "deploy release checklist"))
        await memory.upsert(MemoryDocument(id: "2", source: .systemNote, text: "buy groceries"))

        let results = await memory.search(query: "release deploy", maxResults: 5, minScore: 0.1)
        #expect(results.count == 1)
        #expect(results.first?.id == "1")
    }

    @Test
    func mediaPipelineClassifiesMimeTypes() async throws {
        let media = MediaPipeline(maxBytes: 1024)
        let kind = await media.kind(for: "image/png")
        #expect(kind == .image)

        let blob = MediaBlob(mimeType: "image/png", data: Data(repeating: 1, count: 100))
        let normalized = try await media.normalize(blob)
        #expect(normalized.mimeType == "image/png")
    }

    @Test
    func hookRegistryEmitsHandlers() async throws {
        let hooks = HookRegistry()
        await hooks.register(.gatewayStart) { context in
            HookResult(metadata: ["session": AnyCodable(context.sessionKey ?? "")])
        }

        let result = try await hooks.emit(.gatewayStart, context: HookContext(sessionKey: "main"))
        #expect(result.count == 1)
    }

    @Test
    func cronSchedulerRunsDueJobs() async {
        let scheduler = CronScheduler()
        await scheduler.addOrUpdate(
            CronJob(
                id: "job-a",
                intervalSeconds: 60,
                payload: "run report",
                nextRunAt: Date().addingTimeInterval(-5)
            )
        )

        let due = await scheduler.runDue()
        #expect(due.count == 1)
        #expect(due.first?.jobID == "job-a")
    }

    @Test
    func securityRuntimeTracksPairingAndApprovals() async {
        let security = SecurityRuntime()
        await security.approveDevice(deviceID: "device-1", role: "operator", token: "tok-1")
        await security.setExecApproval(command: "ls", approved: true)

        #expect(await security.pairedDevice("device-1")?.role == "operator")
        #expect(await security.isExecApproved(command: "ls") == true)
    }
}

