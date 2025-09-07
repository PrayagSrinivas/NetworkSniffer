//
//  SnifferURLProtocol.swift
//  NetworkSniffer
//
//  Created by Srinivas Prayag Sahu on 07/09/25.
//

import Foundation
import os

@available(macOS 11.0, *)
final class SnifferURLProtocol: URLProtocol {
    private static let handledKey = "SnifferHandled"
    private var session: URLSession?
    internal var snifferTask: URLSessionDataTask?
    private var buf = Data()
    private var start = Date()
    private var metrics: URLSessionTaskMetrics?

    private let log = Logger(subsystem: "Sniffer", category: "Net")

    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        if URLProtocol.property(forKey: handledKey, in: request) as? Bool == true { return false }
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        start = Date()
        let mreq = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mreq)

        // Forwarding session must not include this protocol to avoid recursion
        let cfg = URLSessionConfiguration.default
        if var classes = cfg.protocolClasses {
            classes.removeAll { $0 == SnifferURLProtocol.self }
            cfg.protocolClasses = classes
        }

        let delegate = Delegate(owner: self)
        session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)

        let method = request.httpMethod ?? "GET"
        log.info("→ \(method, privacy: .public) \(request.url?.absoluteString ?? "-", privacy: .public)")

        task = session?.dataTask(with: mreq as URLRequest)
        task?.resume()

        // ADD THIS PENDING ENTRY:
        NetworkSnifferStore.shared.append(
          NetworkLogEntry(startedAt: start,
                          endedAt: nil,
                          method: request.httpMethod ?? "GET",
                          url: request.url!,
                          status: nil,
                          requestHeaders: request.allHTTPHeaderFields ?? [:],
                          responseHeaders: [:],
                          duration: nil)
        )
    }

    override func stopLoading() {
        self.snifferTask?.cancel()
        self.session?.invalidateAndCancel()
        self.session = nil
    }

    private final class Delegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
        // Mark as nonisolated(unsafe) because URLSession delegate methods are called on arbitrary threads
        // and owner is weak to avoid retain cycles.
        nonisolated(unsafe) weak var owner: SnifferURLProtocol?

        init(owner: SnifferURLProtocol) { self.owner = owner }

        func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            self.owner?.metrics = metrics
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            guard let owner = self.owner else { return }
            owner.buf.append(data)
            owner.client?.urlProtocol(owner, didLoad: data)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                        didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            if let owner = self.owner, let http = response as? HTTPURLResponse {
                owner.client?.urlProtocol(owner, didReceive: http, cacheStoragePolicy: .notAllowed)
            }
            completionHandler(.allow)
        }
        
        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            guard let owner = owner else { return }
            let http = task.response as? HTTPURLResponse
            if let http = http {
                owner.client?.urlProtocol(owner, didReceive: http, cacheStoragePolicy: .notAllowed)
            }
            if let e = error {
                owner.client?.urlProtocol(owner, didFailWithError: e)
            } else {
                owner.client?.urlProtocolDidFinishLoading(owner)
            }

            // ADD THIS COMPLETED ENTRY:
            let status = (task.response as? HTTPURLResponse)?.statusCode
            let headers = (task.response as? HTTPURLResponse)?
                .allHeaderFields
                .reduce(into: [String:String]()) { if let k = $1.key as? String { $0[k] = String(describing: $1.value) } }
                ?? [:]

            NetworkSnifferStore.shared.append(
              NetworkLogEntry(startedAt: owner.start,
                              endedAt: Date(),
                              method: owner.request.httpMethod ?? "GET",
                              url: owner.request.url!,
                              status: status,
                              requestHeaders: owner.request.allHTTPHeaderFields ?? [:],
                              responseHeaders: headers,
                              duration: Date().timeIntervalSince(owner.start))
            )

            // existing logging
            let method = owner.request.httpMethod ?? "GET"
            let url = owner.request.url?.absoluteString ?? "-"
            let dur = Date().timeIntervalSince(owner.start)
            owner.log.info("← \(method, privacy: .public) \(url, privacy: .public) [\(status ?? -1)] in \(String(format: "%.2f", dur))s")
        }
    }
}
