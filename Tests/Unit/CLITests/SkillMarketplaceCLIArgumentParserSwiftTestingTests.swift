// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyCLILib

@Suite("CLIArgumentParser - skill marketplace")
struct SkillMarketplaceCLIArgumentParserSwiftTestingTests {

    @Test("skill source subcommands parse")
    func skillSourceSubcommandsParse() throws {
        #expect(try CLIArgumentParser.parse([
            "skill", "source", "add",
            "https://example.com/skills/local-review.git",
            "--name", "Local Review",
        ]) == .skillSourceAdd(
            url: "https://example.com/skills/local-review.git",
            displayName: "Local Review"
        ))

        #expect(try CLIArgumentParser.parse(["skill", "source", "list"]) == .skillSourceList)
    }

    @Test("skill install and uninstall parse")
    func skillInstallAndUninstallParse() throws {
        #expect(try CLIArgumentParser.parse([
            "skill", "install",
            "https://example.com/skills/local-review.git",
        ]) == .skillInstall(
            url: "https://example.com/skills/local-review.git",
            replaceExisting: false
        ))

        #expect(try CLIArgumentParser.parse([
            "skill", "install",
            "/tmp/local-review",
            "--replace",
        ]) == .skillInstall(url: "/tmp/local-review", replaceExisting: true))

        #expect(try CLIArgumentParser.parse(["skill", "uninstall", "local-review"]) == .skillUninstall(
            id: "local-review"
        ))
    }

    @Test("flat skill marketplace commands parse")
    func flatSkillMarketplaceCommandsParse() throws {
        #expect(try CLIArgumentParser.parse(["skill-source-list"]) == .skillSourceList)
        #expect(try CLIArgumentParser.parse([
            "skill-source-add",
            "https://example.com/skills/local-review.git",
        ]) == .skillSourceAdd(
            url: "https://example.com/skills/local-review.git",
            displayName: nil
        ))
        #expect(try CLIArgumentParser.parse([
            "skill-install",
            "/tmp/local-review",
            "--replace",
        ]) == .skillInstall(url: "/tmp/local-review", replaceExisting: true))
        #expect(try CLIArgumentParser.parse(["skill-uninstall", "local-review"]) == .skillUninstall(
            id: "local-review"
        ))
    }

    @Test("skill marketplace commands build socket requests")
    func commandRunnerBuildsSkillMarketplaceRequests() {
        let sourceRequest = CommandRunner().buildRequest(from: .skillSourceAdd(
            url: "https://example.com/skills/local-review.git",
            displayName: "Local Review"
        ))
        #expect(sourceRequest.command == "skill-source-add")
        #expect(sourceRequest.params?["url"] == "https://example.com/skills/local-review.git")
        #expect(sourceRequest.params?["name"] == "Local Review")

        let installRequest = CommandRunner().buildRequest(from: .skillInstall(
            url: "/tmp/local-review",
            replaceExisting: true
        ))
        #expect(installRequest.command == "skill-install")
        #expect(installRequest.params?["url"] == "/tmp/local-review")
        #expect(installRequest.params?["replace"] == "true")

        let uninstallRequest = CommandRunner().buildRequest(from: .skillUninstall(id: "local-review"))
        #expect(uninstallRequest.command == "skill-uninstall")
        #expect(uninstallRequest.params?["id"] == "local-review")
    }
}
