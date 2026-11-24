import Foundation
import Network
import ApplicationServices
import CoreGraphics

// TruckPad receiver: принимает команды от iPhone по TCP и нажимает клавиши на Mac.
// Протокол: JSON-строки, по одной на строку.
//   {"t":"hello","pin":"1234"}
//   {"t":"btn","id":"horn","d":true}   // d=true нажать, d=false отпустить

// MARK: - Раскладка клавиш (должна совпадать с настройками управления в ETS2)

let defaultKeys: [String: String] = [
    "steerLeft": "a", "steerRight": "d",
    "throttle": "w", "brake": "s", "handbrake": "space",
    "engine": "e", "lights": "l", "highBeam": "k", "horn": "h", "wipers": "p",
    "indicatorLeft": "[", "indicatorRight": "]", "hazard": "f",
    "cruise": "c", "gearUp": "x", "gearDown": "z",
    "retarder": "r", "trailer": "t", "camera": "2", "map": "m", "pause": "escape",
]

let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
    "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
    "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
    "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "escape": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
]

// MARK: - Конфиг: ~/.config/truckpad/config.json

struct Config: Codable {
    var pin: String
    var port: UInt16
    var keys: [String: String]
}

let configURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/truckpad/config.json")

func loadConfig() -> Config {
    if let data = try? Data(contentsOf: configURL),
       let cfg = try? JSONDecoder().decode(Config.self, from: data) {
        return cfg
    }
    let pin = String(format: "%04d", Int.random(in: 0...9999))
    let cfg = Config(pin: pin, port: 5330, keys: defaultKeys)
    try? FileManager.default.createDirectory(
        at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? enc.encode(cfg) { try? data.write(to: configURL) }
    return cfg
}

let config = loadConfig()

// MARK: - Нажатия клавиш

var pressed = Set<CGKeyCode>()
let lock = NSLock()

func post(_ code: CGKeyCode, down: Bool) {
    lock.lock(); defer { lock.unlock() }
    if down { if pressed.contains(code) { return }; pressed.insert(code) }
    else { if !pressed.contains(code) { return }; pressed.remove(code) }
    CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
}

func releaseAll() {
    lock.lock(); let all = pressed; pressed.removeAll(); lock.unlock()
    for c in all { CGEvent(keyboardEventSource: nil, virtualKey: c, keyDown: false)?.post(tap: .cghidEventTap) }
}

func handle(button id: String, down: Bool) {
    guard let name = config.keys[id], let code = keyCodes[name.lowercased()] else { return }
    post(code, down: down)
}

// MARK: - Сеть

final class Session {
    let conn: NWConnection
    var buffer = Data()
    var authed = false

    init(_ conn: NWConnection) { self.conn = conn }

    func start() {
        conn.stateUpdateHandler = { [weak self] st in
            switch st {
            case .failed, .cancelled: releaseAll(); self?.conn.cancel()
            default: break
            }
        }
        conn.start(queue: .global(qos: .userInteractive))
        receive()
    }

    func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, done, err in
            guard let self else { return }
            if let data { self.buffer.append(data); self.drain() }
            if done || err != nil { releaseAll(); self.conn.cancel(); log("отключился"); return }
            self.receive()
        }
    }

    func drain() {
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer.subdata(in: buffer.startIndex..<nl)
            buffer.removeSubrange(buffer.startIndex...nl)
            guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let t = obj["t"] as? String else { continue }
            if t == "hello" {
                if (obj["pin"] as? String) == config.pin {
                    authed = true; log("iPhone подключён"); send(["t": "ok"])
                } else {
                    log("неверный PIN"); send(["t": "bad-pin"]); conn.cancel()
                }
            } else if t == "btn", authed, let id = obj["id"] as? String, let d = obj["d"] as? Bool {
                handle(button: id, down: d)
            }
        }
    }

    func send(_ obj: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        data.append(0x0A)
        conn.send(content: data, completion: .contentProcessed { _ in })
    }
}

func log(_ s: String) { print("[truckpad] \(s)"); fflush(stdout) }

// MARK: - Запуск

let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
if !AXIsProcessTrustedWithOptions(opts) {
    log("Нужен доступ: Системные настройки → Конфиденциальность → Универсальный доступ → разрешите этому терминалу/программе, затем перезапустите.")
}

var sessions: [Session] = []
do {
    let params = NWParameters.tcp
    let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: config.port)!)
    listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: "_truckpad._tcp")
    listener.newConnectionHandler = { c in
        let s = Session(c); sessions.append(s); s.start(); log("новое соединение")
    }
    listener.stateUpdateHandler = { st in
        if case .ready = st { log("слушаю порт \(config.port), PIN: \(config.pin)") }
        if case .failed(let e) = st { log("ошибка: \(e)"); exit(1) }
    }
    listener.start(queue: .main)
} catch {
    log("не удалось запустить: \(error)"); exit(1)
}

signal(SIGINT) { _ in releaseAll(); exit(0) }
signal(SIGTERM) { _ in releaseAll(); exit(0) }
dispatchMain()
