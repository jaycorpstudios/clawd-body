import Foundation

/// Stand-in for the BLE link until it exists: one contract message per line on stdout.
public actor StdoutLink: BuddyLink {
    public init() {}

    public func send(_ data: Data) async {
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}
