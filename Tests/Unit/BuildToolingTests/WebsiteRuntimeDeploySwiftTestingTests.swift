// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// WebsiteRuntimeDeploySwiftTestingTests.swift - Website deploy and server runtime drift checks.

import Foundation
import Testing

@Suite("Website runtime deploy")
struct WebsiteRuntimeDeploySwiftTestingTests {

    @Test("manual website deploy workflow validates static site and restarts server runtime")
    func manualWebsiteDeployWorkflowValidatesStaticSiteAndRestartsServerRuntime() throws {
        let root = repositoryRoot()
        let workflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/deploy-website.yml"),
            encoding: .utf8
        )
        let runtimeScript = try String(
            contentsOf: root.appendingPathComponent("web/scripts/restart-production-runtime.sh"),
            encoding: .utf8
        )
        let serverScript = try String(
            contentsOf: root.appendingPathComponent("web/server.js"),
            encoding: .utf8
        )

        #expect(workflow.contains("workflow_dispatch:"))
        #expect(workflow.contains("environment: production"))
        #expect(workflow.contains("npm run smoke"))
        #expect(workflow.contains("npm audit --audit-level=high"))
        #expect(workflow.contains("npm audit signatures"))
        #expect(workflow.contains("npm run smoke:visual"))
        #expect(workflow.contains("npm run audit:quality:full"))
        #expect(workflow.contains("node scripts/generate-releases-page.mjs"))
        #expect(workflow.contains("tar -czf /tmp/${BACKUP_NAME} -C ${DEPLOY_PATH} ."))
        #expect(workflow.contains("web/public/css/* ${DEPLOY_TARGET}:${DEPLOY_PATH}css/"))
        #expect(workflow.contains("web/public/js/* ${DEPLOY_TARGET}:${DEPLOY_PATH}js/"))
        #expect(workflow.contains("build/releases.html ${DEPLOY_TARGET}:${DEPLOY_PATH}releases.html"))
        #expect(workflow.contains("build/es/releases.html ${DEPLOY_TARGET}:${DEPLOY_PATH}es/releases.html"))
        #expect(workflow.contains("web/server.js web/package.json web/package-lock.json web/ecosystem.config.js"))
        #expect(workflow.contains("web/scripts/restart-production-runtime.sh"))
        #expect(workflow.contains("npm ci --omit=dev --ignore-scripts --no-audit --no-fund"))
        #expect(workflow.contains("main.js?v=${ASSET_VERSION}"))
        #expect(workflow.contains("theme-switcher.js?v=${ASSET_VERSION}"))
        #expect(workflow.contains("cocxy-preview.png?v=${ASSET_VERSION}"))
        #expect(workflow.contains(#"export PATH=\"\$HOME/.npm-global/bin:\$HOME/.npm/bin:\$HOME/.local/bin:\$HOME/.nvm/current/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:\$PATH\""#))
        #expect(workflow.contains(#"if [ -s \"\$HOME/.nvm/nvm.sh\" ]; then . \"\$HOME/.nvm/nvm.sh\""#))
        #expect(workflow.contains("chmod +x restart-production-runtime.sh"))
        #expect(workflow.contains("./restart-production-runtime.sh"))
        #expect(runtimeScript.contains("node not found in deploy environment and pm2 is unavailable"))
        #expect(runtimeScript.contains("cocxy-web failed to stay running after fallback start"))
        #expect(runtimeScript.contains("cocxy-web did not pass local health check"))
        #expect(runtimeScript.contains("port_listener_pids | tr"))
        #expect(serverScript.contains("PUBLIC_ROOT"))
        #expect(serverScript.contains("isPublicRequestPath"))
        #expect(serverScript.contains(#"dotfiles: "ignore""#))
        #expect(serverScript.contains("no-cache, no-transform, max-age=0, must-revalidate"))
        #expect(workflow.contains("https://cocxy.dev/getting-started.html"))
        #expect(workflow.contains(#"test "$REDIRECT_STATUS" = "301""#))
        #expect(workflow.contains(#"SMOKE_DIR="$(mktemp -d)""#))
        #expect(workflow.contains(#"curl -fsSL https://cocxy.dev/ -o "$SMOKE_DIR/home.html""#))
        #expect(workflow.contains(#"grep -qi "cache-control: .*no-transform" "$SMOKE_DIR/home.headers""#))
        #expect(workflow.contains(#"grep -q "style.css?v=${ASSET_VERSION}" "$SMOKE_DIR/home.html""#))
        #expect(workflow.contains(#"grep -q "main.js?v=${ASSET_VERSION}" "$SMOKE_DIR/home.html""#))
        #expect(workflow.contains(#"grep -q "theme-switcher.js?v=${ASSET_VERSION}" "$SMOKE_DIR/home.html""#))
        #expect(workflow.contains(#"grep -qi "^permissions-policy:" "$SMOKE_DIR/home.headers""#))
        #expect(workflow.contains(#"curl -fsSL https://cocxy.dev/appcast.xml -o "$SMOKE_DIR/appcast.xml""#))
        #expect(workflow.contains(#"grep -q "sparkle:edSignature=" "$SMOKE_DIR/appcast.xml""#))
        #expect(workflow.contains(#"curl -fsSL "https://cocxy.dev/service-worker.js?deploy=${GITHUB_RUN_ID}" -o "$SMOKE_DIR/service-worker.js""#))
        #expect(workflow.contains(#"echo "runtime_backup=${RUNTIME_BACKUP}" >> "$GITHUB_STEP_SUMMARY""#))
        #expect(workflow.contains("for private_path in server.js package.json package-lock.json ecosystem.config.js restart-production-runtime.sh cocxy-web.log cocxy-web.err.log node_modules/express/package.json; do"))
        #expect(workflow.contains(#"test "$(curl -sS -o /dev/null -w '%{http_code}' "https://cocxy.dev/${private_path}?deploy=${GITHUB_RUN_ID}")" = "404""#))
        #expect(!workflow.contains("curl -fsSL https://cocxy.dev/ | grep -q"))
        #expect(!workflow.contains("|| true"))
    }

    @Test("website deploys install the server runtime beside the public root, never inside it")
    func websiteDeploysInstallServerRuntimeBesidePublicRoot() throws {
        let root = repositoryRoot()
        let runtimeScript = try String(
            contentsOf: root.appendingPathComponent("web/scripts/restart-production-runtime.sh"),
            encoding: .utf8
        )
        let ecosystem = try String(
            contentsOf: root.appendingPathComponent("web/ecosystem.config.js"),
            encoding: .utf8
        )

        let serverScript = try String(
            contentsOf: root.appendingPathComponent("web/server.js"),
            encoding: .utf8
        )

        for workflowName in ["deploy-website.yml", "release.yml"] {
            let workflow = try String(
                contentsOf: root.appendingPathComponent(".github/workflows/\(workflowName)"),
                encoding: .utf8
            )
            let deployStep = try #require(workflow.range(of: "- name: Deploy website"))
            let runtimeResolution = try #require(workflow.range(of: #"public_root=\$(readlink -f ${DEPLOY_PATH}); \"#))
            let firstStaticCopy = try #require(workflow.range(of: "web/public/*.html ${DEPLOY_TARGET}:${DEPLOY_PATH}"))
            let runtimeBackup = try #require(workflow.range(of: "then tar -czf ${RUNTIME_BACKUP} \\$existing; fi"))
            let runtimeCopy = try #require(workflow.range(of: "${DEPLOY_TARGET}:${RUNTIME_PATH}/"))
            #expect(deployStep.lowerBound < runtimeResolution.lowerBound, "\(workflowName)")
            #expect(runtimeResolution.lowerBound < firstStaticCopy.lowerBound, "\(workflowName) resolves the runtime after copying pages")
            #expect(runtimeBackup.lowerBound < runtimeCopy.lowerBound, "\(workflowName) overwrites the runtime before backing it up")
            #expect(workflow.contains(#"test \"\$(basename \"\$public_root\")\" = public; \"#), "\(workflowName)")
            #expect(workflow.contains(#"test -f \"\$(dirname \"\$public_root\")/server.js\"; \"#), "\(workflowName)")
            #expect(workflow.contains(#"export PATH=\"\$PATH:/opt/bitnami/node/bin\"; \"#), "\(workflowName)")
            #expect(workflow.contains("web/scripts/restart-production-runtime.sh \\\n            ${DEPLOY_TARGET}:${RUNTIME_PATH}/"), "\(workflowName)")
            #expect(workflow.contains("cd ${RUNTIME_PATH}; \\"), "\(workflowName)")
            #expect(!workflow.contains("cd ${DEPLOY_PATH}; \\"), "\(workflowName) installs the runtime into the public root")
            #expect(workflow.contains("for artifact in server.js package.json package-lock.json ecosystem.config.js restart-production-runtime.sh cocxy-web.log cocxy-web.err.log .cocxy-web.pid node_modules; do"), "\(workflowName)")
            #expect(workflow.contains(#"mv ${DEPLOY_PATH}\$artifact \$quarantine/"#), "\(workflowName)")
        }

        let releaseWorkflow = try String(
            contentsOf: root.appendingPathComponent(".github/workflows/release.yml"),
            encoding: .utf8
        )
        #expect(releaseWorkflow.contains(#"grep -q "sparkle:version=\"${VERSION}\"" "$APPCAST_CHECK""#))
        for feed in ["/appcast.xml", "/appcast-preview.xml", "/appcast-nightly.xml"] {
            #expect(serverScript.contains("\"\(feed)\","), "server.js refuses the \(feed) update feed")
        }
        let verification = try #require(runtimeScript.range(of: "  verify_current_runtime\n  \"$PM2_BIN\" save"))
        #expect(!runtimeScript[..<verification.lowerBound].contains(#""$PM2_BIN" save"#))
        #expect(ecosystem.contains("cwd: __dirname,"))
        #expect(!ecosystem.contains("/home/"))
        #expect(runtimeScript.contains(#"if [ "$(pm2_exec_path)" = "$APP_DIR/server.js" ]; then"#))
        #expect(runtimeScript.contains(#""$PM2_BIN" delete "$APP_NAME""#))
        #expect(runtimeScript.contains(#"grep -qi '^permissions-policy:'"#))
        #expect(runtimeScript.contains("cocxy-web is still serving a stale runtime"))
        #expect(runtimeScript.components(separatedBy: "verify_current_runtime\n").count == 4)
    }

    private func repositoryRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.path != "/" {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
}
