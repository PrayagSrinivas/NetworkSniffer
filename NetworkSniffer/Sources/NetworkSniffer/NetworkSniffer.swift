// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation

public enum NetworkSniffer {
    /// Starts the network sniffer. Only available on macOS 11.0 or newer.
    /// Calls must occur on the main actor because `nx_installSniffer` is main actor-isolated.
    @available(macOS 11.0, *)
    public static func start() async {
        await MainActor.run {
            URLSessionConfiguration.nx_installSniffer(SnifferURLProtocol.self)
        }
    }
}
