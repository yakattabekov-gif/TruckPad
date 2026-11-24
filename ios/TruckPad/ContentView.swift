import SwiftUI
import Network

struct ContentView: View {
    @EnvironmentObject var link: Link

    var body: some View {
        Group {
            if link.state == .connected { PadView() } else { ConnectView() }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Подключение

struct ConnectView: View {
    @EnvironmentObject var link: Link
    @AppStorage("pin") private var pin = ""
    @AppStorage("host") private var host = ""
    @AppStorage("port") private var port = "5330"

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("TruckPad").font(.largeTitle.bold())
                Text("Запустите приёмник на Mac и введите PIN из его окна.")
                    .font(.footnote).foregroundStyle(.secondary)
                TextField("PIN", text: $pin).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
                switch link.state {
                case .connecting: ProgressView("Подключение…")
                case .failed(let m): Text(m).foregroundStyle(.red).font(.footnote)
                default: EmptyView()
                }
            }
            .frame(maxWidth: 260)

            VStack(alignment: .leading, spacing: 10) {
                Text("Найденные Mac").font(.headline)
                if link.found.isEmpty {
                    Text("Ничего не найдено. Проверьте Wi‑Fi и доступ к локальной сети.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(link.found, id: \.endpoint) { r in
                    Button(name(of: r)) { link.connect(to: r.endpoint, pin: pin) }
                        .buttonStyle(.borderedProminent)
                }
                Divider()
                Text("Вручную").font(.headline)
                HStack {
                    TextField("IP, напр. 192.168.10.12", text: $host)
                        .keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder)
                    TextField("порт", text: $port).keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder).frame(width: 80)
                    Button("Войти") { link.connect(host: host, port: UInt16(port) ?? 5330, pin: pin) }
                        .buttonStyle(.bordered)
                }
            }
        }
        .padding(32)
    }

    func name(of r: NWBrowser.Result) -> String {
        if case let .service(name, _, _, _) = r.endpoint { return name }
        return "Mac"
    }
}

// MARK: - Пульт

struct PadView: View {
    @EnvironmentObject var link: Link

    var body: some View {
        HStack(spacing: 16) {
            // Руль: две кнопки
            HStack(spacing: 12) {
                HoldButton(id: "steerLeft", title: "◀", color: .blue, big: true)
                HoldButton(id: "steerRight", title: "▶", color: .blue, big: true)
            }
            .frame(maxWidth: 360)

            // Центр: функции
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    HoldButton(id: "indicatorLeft", title: "⬅︎ Поворот", color: .orange)
                    HoldButton(id: "hazard", title: "Аварийка", color: .red)
                    HoldButton(id: "indicatorRight", title: "Поворот ➡︎", color: .orange)
                }
                HStack(spacing: 8) {
                    HoldButton(id: "lights", title: "Свет", color: .gray)
                    HoldButton(id: "highBeam", title: "Дальний", color: .gray)
                    HoldButton(id: "horn", title: "Сигнал", color: .gray)
                    HoldButton(id: "wipers", title: "Дворники", color: .gray)
                }
                HStack(spacing: 8) {
                    HoldButton(id: "engine", title: "Двигатель", color: .green)
                    HoldButton(id: "handbrake", title: "Ручник", color: .red)
                    HoldButton(id: "cruise", title: "Круиз", color: .gray)
                    HoldButton(id: "retarder", title: "Ретардер", color: .gray)
                }
                HStack(spacing: 8) {
                    HoldButton(id: "gearDown", title: "КПП −", color: .purple)
                    HoldButton(id: "gearUp", title: "КПП +", color: .purple)
                    HoldButton(id: "trailer", title: "Прицеп", color: .gray)
                    HoldButton(id: "camera", title: "Камера", color: .gray)
                }
                HStack(spacing: 8) {
                    HoldButton(id: "map", title: "Карта", color: .gray)
                    HoldButton(id: "pause", title: "Пауза", color: .gray)
                    Button("Выйти") { link.disconnect() }
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }

            // Педали
            HStack(spacing: 12) {
                HoldButton(id: "brake", title: "СТОП", color: .red, big: true)
                HoldButton(id: "throttle", title: "ГАЗ", color: .green, big: true)
            }
            .frame(maxWidth: 260)
        }
        .padding(16)
    }
}

/// Кнопка: нажатие при касании, отпускание при отрыве пальца. Работает с мультитачем.
struct HoldButton: View {
    @EnvironmentObject var link: Link
    let id: String
    let title: String
    let color: Color
    var big = false
    @State private var down = false

    var body: some View {
        Text(title)
            .font(big ? .title.bold() : .footnote.bold())
            .frame(maxWidth: .infinity, maxHeight: big ? .infinity : 46)
            .frame(minHeight: big ? 0 : 40)
            .background(color.opacity(down ? 0.95 : 0.45), in: RoundedRectangle(cornerRadius: big ? 20 : 10))
            .foregroundColor(.white)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !down { down = true; link.button(id, down: true) }
                    }
                    .onEnded { _ in
                        down = false; link.button(id, down: false)
                    }
            )
    }
}
