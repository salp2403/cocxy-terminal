// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyCLILib

@Suite("CLIArgumentParser - plugin marketplace")
struct PluginMarketplaceCLIArgumentParserSwiftTestingTests {

    @Test("plugin source subcommands parse")
    func pluginSourceSubcommandsParse() throws {
        #expect(try CLIArgumentParser.parse([
            "plugin", "source", "add",
            "https://github.com/example/cocxy-docker-helper.git",
            "--name", "Docker helpers",
        ]) == .pluginSourceAdd(
            url: "https://github.com/example/cocxy-docker-helper.git",
            displayName: "Docker helpers"
        ))

        #expect(try CLIArgumentParser.parse(["plugin", "source", "list"]) == .pluginSourceList)
    }

    @Test("plugin install and uninstall parse")
    func pluginInstallAndUninstallParse() throws {
        #expect(try CLIArgumentParser.parse([
            "plugin", "install",
            "https://github.com/example/cocxy-docker-helper.git",
        ]) == .pluginInstall(
            url: "https://github.com/example/cocxy-docker-helper.git",
            replaceExisting: false
        ))

        #expect(try CLIArgumentParser.parse([
            "plugin", "install",
            "https://github.com/example/cocxy-docker-helper.git",
            "--replace",
        ]) == .pluginInstall(
            url: "https://github.com/example/cocxy-docker-helper.git",
            replaceExisting: true
        ))

        #expect(try CLIArgumentParser.parse(["plugin", "uninstall", "cocxy-docker-helper"]) == .pluginUninstall(
            id: "cocxy-docker-helper"
        ))
    }

    @Test("flat plugin commands advertised in help parse")
    func flatPluginCommandsAdvertisedInHelpParse() throws {
        #expect(try CLIArgumentParser.parse(["plugin-list"]) == .pluginList)
        #expect(try CLIArgumentParser.parse(["plugin-enable", "sample"]) == .pluginEnable(id: "sample"))
        #expect(try CLIArgumentParser.parse(["plugin-disable", "sample"]) == .pluginDisable(id: "sample"))
        #expect(try CLIArgumentParser.parse(["plugin-source-list"]) == .pluginSourceList)
        #expect(try CLIArgumentParser.parse([
            "plugin-source-add",
            "https://github.com/example/cocxy-plugin.git",
        ]) == .pluginSourceAdd(
            url: "https://github.com/example/cocxy-plugin.git",
            displayName: nil
        ))
        #expect(try CLIArgumentParser.parse([
            "plugin-install",
            "/tmp/cocxy-plugin",
            "--replace",
        ]) == .pluginInstall(url: "/tmp/cocxy-plugin", replaceExisting: true))
        #expect(try CLIArgumentParser.parse(["plugin-uninstall", "sample"]) == .pluginUninstall(id: "sample"))
    }

    @Test("plugin marketplace commands build socket requests")
    func commandRunnerBuildsPluginMarketplaceRequests() {
        let sourceRequest = CommandRunner().buildRequest(from: .pluginSourceAdd(
            url: "https://github.com/example/cocxy-docker-helper.git",
            displayName: "Docker helpers"
        ))
        #expect(sourceRequest.command == "plugin-source-add")
        #expect(sourceRequest.params?["url"] == "https://github.com/example/cocxy-docker-helper.git")
        #expect(sourceRequest.params?["name"] == "Docker helpers")

        let installRequest = CommandRunner().buildRequest(from: .pluginInstall(
            url: "/tmp/cocxy-plugin",
            replaceExisting: true
        ))
        #expect(installRequest.command == "plugin-install")
        #expect(installRequest.params?["url"] == "/tmp/cocxy-plugin")
        #expect(installRequest.params?["replace"] == "true")

        let uninstallRequest = CommandRunner().buildRequest(from: .pluginUninstall(id: "sample"))
        #expect(uninstallRequest.command == "plugin-uninstall")
        #expect(uninstallRequest.params?["id"] == "sample")
    }
}
