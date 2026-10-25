import Foundation

/// Development link (`hilod --stdout`): one contract message per line on stdout.
public actor StdoutLink: BuddyLink {
    public init() {}

    public func send(_ data: Data) async {
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}
