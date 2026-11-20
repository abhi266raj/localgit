import XCTest
@testable import LocalGitCore

final class MockFMClient: FMClientProtocol {
    var isAvailableResult: Bool = true
    var planActionHandler: ((String, String, String?) async throws -> GitPlan)?
    var planRecoveryHandler: ((String, String, Int32, String, String) async throws -> GitPlan)?

    var planActionCalls: Int = 0
    var planRecoveryCalls: Int = 0
    var lastSessionHistoryPassed: String? = nil

    func isAvailable() -> Bool {
        return isAvailableResult
    }

    func planAction(task: String, gitContext: String, sessionHistory: String?) async throws -> GitPlan {
        planActionCalls += 1
        lastSessionHistoryPassed = sessionHistory
        if let handler = planActionHandler {
            return try await handler(task, gitContext, sessionHistory)
        }
        return GitPlan(thought: "Mock thought", command: "echo 'mock success'", explanation: "Mock explanation")
    }

    func planRecovery(task: String, failedCommand: String, exitCode: Int32, output: String, gitContext: String) async throws -> GitPlan {
        planRecoveryCalls += 1
        if let handler = planRecoveryHandler {
            return try await handler(task, failedCommand, exitCode, output, gitContext)
        }
        return GitPlan(thought: "Fix thought", command: "echo 'fixed'", explanation: "Fix explanation")
    }
}

final class LocalGitTests: XCTestCase {
    func testGitStateContext() {
        let state = GitState(
            isRepo: true,
            branch: "main",
            statusSummary: " M Package.swift",
            recentLogs: "abc1234 initial commit",
            remotes: "origin git@github.com:user/repo.git (fetch)"
        )
        let context = state.toPromptContext()
        XCTAssertTrue(context.contains("Current Branch: main"))
        XCTAssertTrue(context.contains("M Package.swift"))
        XCTAssertTrue(context.contains("abc1234 initial commit"))
    }

    func testExecutorSafety() {
        XCTAssertTrue(CommandExecutor.isGitCommandSafe("git status"))
        XCTAssertTrue(CommandExecutor.isGitCommandSafe("git add . && git commit -m 'feat'"))
        XCTAssertFalse(CommandExecutor.isGitCommandSafe("rm -rf /"))
        XCTAssertFalse(CommandExecutor.isGitCommandSafe(""))
    }

    func testExecutorEcho() {
        let res = CommandExecutor.execute(command: "echo 'hello swift localgit'")
        XCTAssertTrue(res.isSuccess)
        XCTAssertEqual(res.stdout, "hello swift localgit")
    }

    func testFMResponseParsing() {
        let client = AppleFMClient()
        let raw = """
        ```json
        {
          "thought": "Create new branch",
          "command": "git checkout -b feature-test",
          "explanation": "Create and switch branch"
        }
        ```
        """
        let plan = client.parseResponse(raw)
        XCTAssertEqual(plan.thought, "Create new branch")
        XCTAssertEqual(plan.command, "git checkout -b feature-test")
        XCTAssertEqual(plan.explanation, "Create and switch branch")
    }

    func testEngineAutonomousSuccessWithoutHistoryByDefault() async {
        let mock = MockFMClient()
        mock.planActionHandler = { task, ctx, hist in
            return GitPlan(thought: "Run status", command: "echo 'mock git status'", explanation: "Status test")
        }

        let engine = GitAgentEngine(
            fmClient: mock,
            maxRetries: 2,
            autoConfirm: true, // without permission
            withHistory: false // Default mode: history cleared once task completes
        )

        let success = await engine.executeTask("check status")
        XCTAssertTrue(success)
        XCTAssertEqual(mock.planActionCalls, 1)
        XCTAssertNil(mock.lastSessionHistoryPassed)
        // Default mode verifies history is cleared
        XCTAssertTrue(engine.sessionHistory.isEmpty)
    }

    func testEngineRetainsHistoryWhenFlagEnabled() async {
        let mock = MockFMClient()
        mock.planActionHandler = { task, ctx, hist in
            return GitPlan(thought: "Task step", command: "echo 'task step'", explanation: "Step")
        }

        let engine = GitAgentEngine(
            fmClient: mock,
            maxRetries: 2,
            autoConfirm: true,
            withHistory: true // Explicitly enabled with -H / --with-history
        )

        let firstSuccess = await engine.executeTask("first task")
        XCTAssertTrue(firstSuccess)
        XCTAssertEqual(engine.sessionHistory.count, 1)
        XCTAssertEqual(engine.sessionHistory.first?.task, "first task")

        let secondSuccess = await engine.executeTask("second task")
        XCTAssertTrue(secondSuccess)
        XCTAssertEqual(engine.sessionHistory.count, 2)
        XCTAssertNotNil(mock.lastSessionHistoryPassed)
        XCTAssertTrue(mock.lastSessionHistoryPassed!.contains("first task"))
    }

    func testEngineErrorRecovery() async {
        let mock = MockFMClient()
        // First command will fail
        mock.planActionHandler = { task, ctx, hist in
            return GitPlan(thought: "Failing attempt", command: "sh -c 'echo \"mock fatal\" >&2 && exit 1'", explanation: "Fail")
        }
        // Recovery command will succeed
        mock.planRecoveryHandler = { task, cmd, code, out, ctx in
            return GitPlan(thought: "Recovery fix", command: "echo 'recovery passed'", explanation: "Fix")
        }

        let engine = GitAgentEngine(
            fmClient: mock,
            maxRetries: 3,
            autoConfirm: true
        )

        let success = await engine.executeTask("resolve error")
        XCTAssertTrue(success)
        XCTAssertEqual(mock.planActionCalls, 1)
        XCTAssertEqual(mock.planRecoveryCalls, 1)
    }
}
