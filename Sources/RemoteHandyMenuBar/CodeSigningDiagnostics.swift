import Foundation

struct CodeSigningStatus {
    let bundlePath: String
    let identifier: String?
    let signature: String?
    let authority: String?
    let teamIdentifier: String?
    let designatedRequirement: String?
    let verified: Bool
    let verifyDetail: String

    var summary: String {
        [
            "bundle=\(bundlePath)",
            "identifier=\(identifier ?? "unknown")",
            "signature=\(signature ?? "unknown")",
            "authority=\(authority ?? "none")",
            "team=\(teamIdentifier ?? "none")",
            "verified=\(verified ? "yes" : "no")"
        ].joined(separator: ", ")
    }
}

enum CodeSigningDiagnostics {
    static func currentAppStatus() -> CodeSigningStatus {
        status(for: Bundle.main.bundleURL.path)
    }

    static func status(for bundlePath: String) -> CodeSigningStatus {
        let details = runCodesign(arguments: ["-dv", "--verbose=4", bundlePath])
        let requirement = runCodesign(arguments: ["-d", "-r-", bundlePath])
        let verify = runCodesign(arguments: ["--verify", "--deep", "--strict", bundlePath])

        let combinedDetails = details.output + "\n" + details.error
        let requirementText = requirement.output + "\n" + requirement.error

        return CodeSigningStatus(
            bundlePath: bundlePath,
            identifier: firstMatch(in: combinedDetails, prefix: "Identifier="),
            signature: firstMatch(in: combinedDetails, prefix: "Signature="),
            authority: firstMatch(in: combinedDetails, prefix: "Authority="),
            teamIdentifier: firstMatch(in: combinedDetails, prefix: "TeamIdentifier="),
            designatedRequirement: requirementText
                .split(separator: "\n")
                .first { $0.contains("# designated =>") }
                .map(String.init),
            verified: verify.exitCode == 0,
            verifyDetail: (verify.output + verify.error).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func firstMatch(in text: String, prefix: String) -> String? {
        text
            .split(separator: "\n")
            .compactMap { line -> String? in
                let value = line.trimmingCharacters(in: .whitespaces)
                guard value.hasPrefix(prefix) else {
                    return nil
                }
                return String(value.dropFirst(prefix.count))
            }
            .first
    }

    private static func runCodesign(arguments: [String]) -> (output: String, error: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ("", String(describing: error), 1)
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (output, error, process.terminationStatus)
    }
}
