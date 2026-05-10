// Copyright (c) 2026 Said Arturo Lopez. MIT License.

import Testing
@testable import CocxyInputClassifier

@Suite("Dangerous command dictionary")
struct DangerousCommandDictionarySwiftTestingTests {

    @Test("matches critical destructive root deletion")
    func matchesCriticalRootDeletion() {
        let dictionary = DangerousCommandDictionary.default

        let match = dictionary.match("sudo rm -rf /")

        #expect(match?.severity == .critical)
        #expect(match?.reason.contains("root filesystem") == true)
    }

    @Test("matches disk erase and raw disk writes")
    func matchesDiskEraseAndRawWrites() {
        let dictionary = DangerousCommandDictionary.default

        #expect(dictionary.match("diskutil eraseDisk APFS Test disk2")?.severity == .critical)
        #expect(dictionary.match("dd if=/dev/zero of=/dev/disk2 bs=1m")?.severity == .critical)
    }

    @Test("matches filesystem creation commands")
    func matchesFilesystemCreationCommands() {
        let dictionary = DangerousCommandDictionary.default

        #expect(dictionary.match("mkfs.ext4 /dev/sdb1")?.severity == .high)
        #expect(dictionary.match("newfs_apfs /dev/disk3")?.severity == .high)
    }

    @Test("allows scoped project cleanup commands")
    func allowsScopedProjectCleanupCommands() {
        let dictionary = DangerousCommandDictionary.default

        #expect(dictionary.match("rm -rf ./build") == nil)
        #expect(dictionary.match("git clean -fd build") == nil)
    }

    @Test("normalizes whitespace and shell separators")
    func normalizesWhitespaceAndShellSeparators() {
        let dictionary = DangerousCommandDictionary.default

        #expect(dictionary.match(" cd /tmp &&   rm   -rf    / ")?.severity == .critical)
    }
}
