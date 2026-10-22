// Copyright (c) 2026 Said Arturo Lopez. MIT License.
// DescriptorBoundTerminalEngine.swift - Descriptor-bound terminal creation contract.

/// Terminal engines that can bind the initial shell directory to an already
/// verified directory descriptor instead of reopening an untrusted pathname.
@MainActor
protocol DescriptorBoundTerminalEngine: TerminalEngine {
    func createSurface(
        in view: NativeTerminalView,
        verifiedWorkingDirectory: ProjectDirectoryRoot,
        command: String?
    ) throws -> SurfaceID
}
