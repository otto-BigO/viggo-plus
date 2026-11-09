import AppIntents
import SwiftUI
import WidgetKit

/// A Control Center button that shows what you have now (or next) and opens Viggo+.
struct ViggoControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ViggoControl") {
            ControlWidgetButton(action: OpenViggoIntent()) {
                let d = WidgetStore.load()
                let (cur, next, _) = d.now(Date())
                if let c = cur, !c.isPause {
                    Label(c.title, systemImage: "graduationcap.fill")
                    Text("til \(c.end.formatted(date: .omitted, time: .shortened))")
                } else if let n = next {
                    Label(n.title, systemImage: "graduationcap")
                    Text("kl. \(n.start.formatted(date: .omitted, time: .shortened))")
                } else {
                    Label("Viggo+", systemImage: "graduationcap")
                }
            }
        }
        .displayName("Viggo+ nu")
        .description("Viser hvad du har nu og åbner Viggo+.")
    }
}
