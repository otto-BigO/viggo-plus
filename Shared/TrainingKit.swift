import SwiftUI

// The parts of Træning that the Mac window and the iPhone tab both use: the pages, text helpers
// and the exercise photos. The Mac pages are in Sources/Training*.swift, the iPhone ones in
// iOS/Sources/TrainingScreen.swift.

/// Sizes for the shared training views: the Mac sizes, a bit bigger on the iPhone.
enum Tk {
    #if os(iOS)
    static let phone = true
    static let k: CGFloat = 1.15
    static let device = "iPhone"
    #else
    static let phone = false
    static let k: CGFloat = 1
    static let device = "Mac"
    #endif
}

extension Notification.Name { static let viggoOpenTraining = Notification.Name("viggoOpenTraining") }

enum TrainingPage: String, CaseIterable {
    case plan = "Plan", workout = "Træn", program = "Program", progress = "Fremgang"
    var icon: String {
        switch self {
        case .plan: return "calendar"
        case .program: return "list.bullet.rectangle"
        case .workout: return "dumbbell.fill"
        case .progress: return "chart.line.uptrend.xyaxis"
        }
    }
}

func kgText(_ kg: Double) -> String {
    kg.rounded() == kg ? "\(Int(kg))" : String(format: "%.1f", kg).replacingOccurrences(of: ".", with: ",")
}

func setText(_ s: LoggedSet, _ ex: Exercise) -> String {
    switch ex.unit {
    case .seconds: return "\(s.reps) sek"
    case _ where ex.bodyweight: return "\(s.reps) stk"
    default: return "\(kgText(s.kg)) kg × \(s.reps)"
    }
}

/// "torsdag 26. november" -> "Torsdag 26. november".
func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

let longDay: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.timeZone = DateUtil.tz; f.dateFormat = "EEEE d. MMMM"; return f
}()
let shortDay: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "da_DK"); f.timeZone = DateUtil.tz; f.dateFormat = "EEE d/M"; return f
}()

/// "81" or "80,5".
func numText(_ d: Double) -> String {
    d.rounded() == d ? "\(Int(d))" : String(format: "%.1f", d).replacingOccurrences(of: ".", with: ",")
}

/// Reads "80,5" and "80.5".
func num(_ s: String) -> Double? {
    Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// Sets, reps and rest written the way the program shows them ("3 × 8-12").
func targetText(_ ex: Exercise, _ item: PlanItem) -> String {
    var e = ex
    e.sets = item.sets; e.repsLow = item.repsLow; e.repsHigh = item.repsHigh
    return e.target
}

/// Start and end photos of an exercise from free-exercise-db (public domain), bundled in Resources/Exercises.
enum ExercisePhotos {
    nonisolated(unsafe) static var cache: [String: PlatformImage] = [:]
    static func image(_ id: String, _ frame: Int) -> PlatformImage? {
        let key = "\(id)-\(frame)"
        if let i = cache[key] { return i }
        guard let url = Bundle.main.url(forResource: key, withExtension: "jpg", subdirectory: "Exercises"),
              let img = PlatformImage(contentsOfFile: url.path) else { return nil }
        cache[key] = img
        return img
    }
}

extension Image {
    init(platform i: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: i)
        #else
        self.init(nsImage: i)
        #endif
    }
}

/// Small photo on the card header, the end position (like Strong's thumbnails). Falls back to the symbol.
struct ExerciseThumb: View {
    let ex: Exercise
    var width: CGFloat = 60
    var height: CGFloat = 44
    var frame = 1
    var body: some View {
        Group {
            if let img = ExercisePhotos.image(ex.id, frame) {
                Image(platform: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: ex.symbol).font(.system(size: 18, design: Fomo.design)).foregroundStyle(Fomo.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Fomo.accent.opacity(0.16))
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: min(10, height / 5), style: .continuous))
    }
}

/// The exercise moving: start and end photo fade into each other every 1.2 s.
struct ExerciseMotion: View {
    let ex: Exercise
    @State private var frame = 0
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            ForEach(0..<2, id: \.self) { n in
                if let img = ExercisePhotos.image(ex.id, n) {
                    Color.clear.overlay { Image(platform: img).resizable().aspectRatio(contentMode: .fill) }
                        .clipped()
                        .opacity(frame == n ? 1 : 0)
                }
            }
            Text(frame == 0 ? "Start" : "Slut")
                .font(.system(size: 10 * Tk.k, weight: .bold, design: Fomo.design)).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(.black.opacity(0.55))).foregroundStyle(.white).padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.2))
                withAnimation(.easeInOut(duration: 0.35)) { frame = 1 - frame }
            }
        }
    }
}

// MARK: - iPhone-only modifiers (they do nothing on the Mac)

extension View {
    @ViewBuilder func trKeyboard(decimal: Bool) -> some View {
        #if os(iOS)
        keyboardType(decimal ? .decimalPad : .numberPad)
        #else
        self
        #endif
    }

    @ViewBuilder func trHideNavBar(_ hide: Bool) -> some View {
        #if os(iOS)
        toolbar(hide ? .hidden : .visible, for: .navigationBar)
        #else
        self
        #endif
    }

    @ViewBuilder func trInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
