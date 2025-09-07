//
//  URLSessionConfiguration+Sniffer.swift
//  NetworkSniffer
//
//  Created by Srinivas Prayag Sahu on 07/09/25.
//

import Foundation
import ObjectiveC.runtime

@MainActor
extension URLSessionConfiguration {
    private static var nx_installed = false
    private static var nx_proto: URLProtocol.Type?
    private static let nx_lock = DispatchQueue(label: "nx.lock.urlsession.sniffer")

    static func nx_installSniffer(_ proto: URLProtocol.Type) {
        var alreadyInstalled = false
        nx_lock.sync {
            alreadyInstalled = nx_installed
        }
        guard !alreadyInstalled else { return }
        nx_lock.sync {
            nx_installed = true
            nx_proto = proto
        }

        func swizzle(on cfg: URLSessionConfiguration) {
            guard let meta: AnyClass = object_getClass(cfg) else { return }
            let original = #selector(getter: URLSessionConfiguration.protocolClasses)
            let swizzled = #selector(URLSessionConfiguration.nx_protocolClassesGetter)
            if let m1 = class_getInstanceMethod(meta, original),
               let m2 = class_getInstanceMethod(URLSessionConfiguration.self, swizzled) {
                method_exchangeImplementations(m1, m2)
            }
        }
        swizzle(on: .default)
        swizzle(on: .ephemeral)
        // Background configurations are out-of-process and not fully interceptable.
    }

    @objc private func nx_protocolClassesGetter() -> [AnyClass] {
        var classes = self.nx_protocolClassesGetter() // original via swizzle
        var proto: URLProtocol.Type?
        URLSessionConfiguration.nx_lock.sync {
            proto = URLSessionConfiguration.nx_proto
        }
        if let p = proto,
           classes.first(where: { $0 == p }) == nil {
            classes.insert(p, at: 0)
        }
        return classes
    }
}
