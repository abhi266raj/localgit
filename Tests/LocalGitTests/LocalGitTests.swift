import XCTest
@testable import LocalGitCore

final class MockFMClient: FMClientProtocol {
    var isAvailableResult: Bool = true
    var planActionHandler: ((String, String, String?) async throws -> GitPlan)?
    var planRecoveryHandler: ((String, String, Int32, String, String) async throws -> GitPlan)?
    var synthesizeOutputHandler: ((String, String, Int32, String) async throws -> String)?

    var planActionCalls: Int = 0
    var planRecoveryCalls: Int = 0
    var synthesizeOutputCalls: Int = 0
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

    func synthesizeOutput(task: String, executedCommand: String, exitCode: Int32, rawTerminalOutput: String) async throws -> String {
        synthesizeOutputCalls += 1
        if let handler = synthesizeOutputHandler {
            return try await handler(task, executedCommand, exitCode, rawTerminalOutput)
        }
        return "Synthesized result for \(task): \(rawTerminalOutput)"
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

    func testEngineTwoStepExecutionAndOutputSynthesis() async {
        let mock = MockFMClient()
        mock.planActionHandler = { task, ctx, hist in
            return GitPlan(thought: "Analyzing repo", command: "echo 'branch updated'", explanation: "Update branch")
        }
        mock.synthesizeOutputHandler = { task, cmd, code, raw in
            return "Human-friendly summary: Successfully executed \(cmd)"
        }

        let engine = GitAgentEngine(
            fmClient: mock,
            maxRetries: 2,
            autoConfirm: true,
            withHistory: false
        )

        let success = await engine.executeTask("switch branch")
        XCTAssertTrue(success)
        // Step 1: planAction called
        XCTAssertEqual(mock.planActionCalls, 1)
        // Step 2: synthesizeOutput called to ask LLM what output to show to user
        XCTAssertEqual(mock.synthesizeOutputCalls, 1)
        XCTAssertTrue(engine.sessionHistory.isEmpty) // Default mode clears history
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
            withHistory: true
        )

        let firstSuccess = await engine.executeTask("first task")
        XCTAssertTrue(firstSuccess)
        XCTAssertEqual(engine.sessionHistory.count, 1)
        XCTAssertEqual(mock.synthesizeOutputCalls, 1)

        let secondSuccess = await engine.executeTask("second task")
        XCTAssertTrue(secondSuccess)
        XCTAssertEqual(engine.sessionHistory.count, 2)
        XCTAssertEqual(mock.synthesizeOutputCalls, 2)
        XCTAssertNotNil(mock.lastSessionHistoryPassed)
        XCTAssertTrue(mock.lastSessionHistoryPassed!.contains("first task"))
    }

    func testEngineErrorRecoveryAndTwoStepOutput() async {
        let mock = MockFMClient()
        // First command will fail
        mock.planActionHandler = { task, ctx, hist in
            return GitPlan(thought: "Initial attempt", command: "sh -c 'echo \"mock error: conflict\" >&2 && exit 1'", explanation: "Fail")
        }
        // Recovery command will succeed
        mock.planRecoveryHandler = { task, cmd, code, out, ctx in
            return GitPlan(thought: "Identified conflict cause, fixing", command: "echo 'conflict resolved'", explanation: "Fix")
        }
        mock.synthesizeOutputHandler = { task, cmd, code, raw in
            return "Conflict has been resolved successfully."
        }

        let engine = GitAgentEngine(
            fmClient: mock,
            maxRetries: 3,
            autoConfirm: true
        )

        let success = await engine.executeTask("resolve conflict")
        XCTAssertTrue(success)
        XCTAssertEqual(mock.planActionCalls, 1)
        XCTAssertEqual(mock.planRecoveryCalls, 1)
        XCTAssertEqual(mock.synthesizeOutputCalls, 1)
    }
}
