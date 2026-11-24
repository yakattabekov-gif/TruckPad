import Foundation
import Network
import UIKit

/// Соединение с Mac-приёмником: поиск по Bonjour, TCP, JSON-строки.
final class Link: ObservableObject {
    enum State: Equatable { case idle, connecting, connected, failed(String) }

    @Published var state: State = .idle
    @Published var found: [NWBrowser.Result] = []

    private var browser: NWBrowser?
    private var conn: NWConnection?
    private let queue = DispatchQueue(label: "truckpad.link")
    private var pin = ""
    private let haptics = UIImpactFeedbackGenerator(style: .light)

    init() { startBrowsing() }

    func startBrowsing() {
        let b = NWBrowser(for: .bonjour(type: "_truckpad._tcp", domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async { self?.found = Array(results) }
        }
        b.start(queue: queue)
        browser = b
    }

    func connect(to endpoint: NWEndpoint, pin: String) {
        disconnect()
        self.pin = pin
        state = .connecting
        let c = NWConnection(to: endpoint, using: .tcp)
        c.stateUpdateHandler = { [weak self] st in
            guard let self else { return }
            switch st {
            case .ready:
                self.sendRaw(["t": "hello", "pin": pin])
                self.receive()
            case .failed(let e):
                DispatchQueue.main.async { self.state = .failed(e.localizedDescription) }
            case .waiting(let e):
                DispatchQueue.main.async { self.state = .failed(e.localizedDescription) }
            default: break
            }
        }
        conn = c
        c.start(queue: queue)
    }

    func connect(host: String, port: UInt16, pin: String) {
        guard let p = NWEndpoint.Port(rawValue: port) else { return }
        connect(to: .hostPort(host: NWEndpoint.Host(host), port: p), pin: pin)
    }

    func disconnect() {
        conn?.cancel(); conn = nil
        DispatchQueue.main.async { self.state = .idle }
    }

    func button(_ id: String, down: Bool) {
        if down { haptics.impactOccurred() }
        sendRaw(["t": "btn", "id": id, "d": down])
    }

    private func sendRaw(_ obj: [String: Any]) {
        guard let c = conn, var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        data.append(0x0A)
        c.send(content: data, completion: .contentProcessed { _ in })
    }

    private func receive() {
        conn?.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data, let s = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    if s.contains("\"ok\"") { self.state = .connected }
                    if s.contains("bad-pin") { self.state = .failed("Неверный PIN") }
                }
            }
            if done || err != nil {
                DispatchQueue.main.async { if self.state == .connected { self.state = .failed("Соединение потеряно") } }
                return
            }
            self.receive()
        }
    }
}
