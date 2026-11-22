import Foundation

struct ShellResult {
    var out: String
    var err: String
    var code: Int32
    var ok: Bool { code == 0 }
}

/// Esegue comandi di sistema fuori dal main thread, con timeout.
enum Shell {
    private final class Box { var data = Data() }

    static func run(_ path: String, _ args: [String] = [], timeout: TimeInterval = 30) async -> ShellResult {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: runSync(path, args, timeout: timeout))
            }
        }
    }

    /// `sh -c "<comando>"`.
    static func sh(_ command: String, timeout: TimeInterval = 30) async -> ShellResult {
        await run("/bin/sh", ["-c", command], timeout: timeout)
    }

    static func runSync(_ path: String, _ args: [String], timeout: TimeInterval) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do { try process.run() } catch {
            return ShellResult(out: "", err: error.localizedDescription, code: -1)
        }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        // Si legge stderr in parallelo per non riempire il buffer della pipe.
        let errBox = Box()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        killer.cancel()
        return ShellResult(
            out: String(decoding: outData, as: UTF8.self),
            err: String(decoding: errBox.data, as: UTF8.self),
            code: process.terminationStatus
        )
    }
}

extension String {
    /// Primo gruppo di una regex, se c'è.
    func firstMatch(_ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: self) else { return nil }
        return String(self[r])
    }
}
