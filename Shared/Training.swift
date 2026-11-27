import Foundation

// Træning: your profile (weight, goal, how often), a program built from it, the exercises with
// how-to lines, a log of every workout and your body weight, and a planner that finds free time
// in the Viggo schedule. Only Foundation here, so the iPhone app can use the same code later.
// The Mac window is Sources/TrainingWindow.swift, the setup Sources/TrainingSetup.swift.

enum RepUnit: String, Codable { case reps, seconds, perLeg, perSide }

enum Area: String, Codable, CaseIterable, Identifiable {
    case legs, chest, back, shoulders, arms, abs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .legs: return "Ben og numse"
        case .chest: return "Bryst"
        case .back: return "Ryg"
        case .shoulders: return "Skuldre"
        case .arms: return "Arme"
        case .abs: return "Mave"
        }
    }
    var icon: String {
        switch self {
        case .legs: return "figure.run"
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.rower"
        case .shoulders: return "figure.arms.open"
        case .arms: return "dumbbell.fill"
        case .abs: return "figure.core.training"
        }
    }
}

/// Where an exercise can be done.
enum Gear: String, Codable { case gym, home, both }

struct Exercise: Identifiable, Hashable {
    let id: String
    let name: String
    let muscles: String
    let area: Area
    /// The movement, used to build programs: squat, hinge, hpush, hpull, vpush, vpull, lunge, glute,
    /// legiso, calf, chestiso, shoulderiso, biceps, triceps, core.
    let pattern: String
    var sets: Int
    var repsLow: Int
    var repsHigh: Int
    var unit: RepUnit = .reps
    /// Seconds of rest after a set.
    var rest: Int
    /// What to add once every set reaches the top of the range.
    var increment: Double = 2.5
    /// No weight to log (planke, armbøjninger, knæløft).
    var bodyweight = false
    var gear: Gear = .gym
    let cues: [String]
    /// What to do instead without a gym. Empty for exercises you can already do anywhere.
    var home: String = ""

    var symbol: String { area.icon }
    var compound: Bool { ["squat", "hinge", "hpush", "hpull", "vpush", "vpull", "lunge"].contains(pattern) }

    var target: String {
        let r = repsLow == repsHigh ? "\(repsLow)" : "\(repsLow)-\(repsHigh)"
        switch unit {
        case .reps: return "\(sets) × \(r)"
        case .seconds: return "\(sets) × \(r) sek"
        case .perLeg: return "\(sets) × \(r) pr. ben"
        case .perSide: return "\(sets) × \(r) pr. side"
        }
    }

    var videoURL: URL? {
        let q = "\(name) teknik".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.youtube.com/results?search_query=\(q)")
    }
}

// MARK: - Profile

enum Goal: String, Codable, CaseIterable, Identifiable {
    case recomp, muscle, strength, fit
    var id: String { rawValue }
    var title: String {
        switch self {
        case .recomp: return "Tabe fedt og bygge muskler"
        case .muscle: return "Bygge muskler"
        case .strength: return "Blive stærkere"
        case .fit: return "Komme i bedre form"
        }
    }
    var subtitle: String {
        switch self {
        case .recomp: return "Mindre mave, mere muskler"
        case .muscle: return "Større og mere muskuløs"
        case .strength: return "Løfte tungere"
        case .fit: return "Mere energi og overskud"
        }
    }
    var icon: String {
        switch self {
        case .recomp: return "flame.fill"
        case .muscle: return "figure.strengthtraining.traditional"
        case .strength: return "bolt.fill"
        case .fit: return "heart.fill"
        }
    }
}

enum Level: String, Codable, CaseIterable, Identifiable {
    case new, some, trained
    var id: String { rawValue }
    var title: String {
        switch self {
        case .new: return "Ny"
        case .some: return "Lidt erfaring"
        case .trained: return "Øvet"
        }
    }
    var subtitle: String {
        switch self {
        case .new: return "Jeg har næsten aldrig trænet med vægte"
        case .some: return "Jeg har trænet lidt før"
        case .trained: return "Jeg træner fast og kender øvelserne"
        }
    }
    var icon: String {
        switch self {
        case .new: return "leaf.fill"
        case .some: return "chart.line.uptrend.xyaxis"
        case .trained: return "star.fill"
        }
    }
}

enum Place: String, Codable, CaseIterable, Identifiable {
    case gym, home
    var id: String { rawValue }
    var title: String { self == .gym ? "Fitnessrum" : "Hjemme eller på værelset" }
    var subtitle: String { self == .gym ? "Maskiner, stænger og håndvægte" : "Kun kropsvægt, en stol og et bord" }
    var icon: String { self == .gym ? "building.2.fill" : "house.fill" }
}

enum TimeOfDay: String, Codable, CaseIterable, Identifiable {
    case afternoon, evening, any
    var id: String { rawValue }
    var title: String {
        switch self {
        case .afternoon: return "Eftermiddag"
        case .evening: return "Aften"
        case .any: return "Lige meget"
        }
    }
    var subtitle: String {
        switch self {
        case .afternoon: return "Efter skole, kl. 14-18"
        case .evening: return "Efter aftensmad, fra kl. 18"
        case .any: return "Den første ledige time"
        }
    }
    var icon: String {
        switch self {
        case .afternoon: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        case .any: return "clock.fill"
        }
    }
}

/// What you told the setup. Stays on this Mac in training.json.
struct TrainingProfile: Codable, Equatable {
    var weight: Double = 0
    var height: Double = 0
    var age: Int = 0
    var goal: Goal = .recomp
    var level: Level = .new
    var place: Place = .gym
    var days = 3
    var minutes = 60
    var focus: [Area] = []
    var when: TimeOfDay = .afternoon
    /// Weekdays you can't train, 1 = Monday ... 7 = Sunday.
    var skip: [Int] = []

    var wish: TrainingPlanner.Wish {
        TrainingPlanner.Wish(count: days, minutes: minutes, when: when, skip: Set(skip), anywhere: place == .home)
    }

    /// "Tabe fedt og bygge muskler · 3 dage · 60 min · Fitnessrum"
    var summary: String { "\(goal.title) · \(days) dage · \(minutes) min · \(place == .gym ? "Fitnessrum" : "Hjemme")" }
}

struct BodyWeight: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var kg: Double
}

// MARK: - Program

/// One exercise in your program, with its own sets and reps.
struct PlanItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var exercise: String
    var sets: Int
    var repsLow: Int
    var repsHigh: Int
    var rest: Int
}

struct TrainingSession: Codable, Hashable, Identifiable {
    /// "A", "B" …
    var id: String
    /// "Hele kroppen", "Overkrop", "Underkrop".
    var name: String
    var items: [PlanItem]
}

enum TrainingProgram {
    static func exercise(_ id: String) -> Exercise? { all.first { $0.id == id } }

    /// The first plan from the training note, used until you have done the setup.
    static let standard: [TrainingSession] = [
        ("A", ["squat", "bench", "row", "ohp", "plank"]),
        ("B", ["rdl", "pullup", "incline", "lunge", "kneeraise"]),
        ("C", ["legpress", "pushup", "onearmrow", "lateral", "curl", "pushdown"]),
    ].map { id, list in
        TrainingSession(id: id, name: "Hele kroppen", items: list.compactMap { exercise($0) }.map {
            PlanItem(exercise: $0.id, sets: $0.sets, repsLow: $0.repsLow, repsHigh: $0.repsHigh, rest: $0.rest)
        })
    }

    static let all: [Exercise] = [
        // Ben og numse
        Exercise(id: "squat", name: "Squat", muscles: "Ben og numse", area: .legs, pattern: "squat",
                 sets: 3, repsLow: 8, repsHigh: 10, rest: 120,
                 cues: ["Fødderne i skulderbredde, tæerne lidt ud", "Brystet op, stangen på øvre ryg",
                        "Sæt dig ned og tilbage, til lårene er vandrette", "Pres op gennem hele foden"],
                 home: "Squat med en tung rygsæk"),
        Exercise(id: "legpress", name: "Benpres", muscles: "Ben og numse", area: .legs, pattern: "squat",
                 sets: 3, repsLow: 10, repsHigh: 12, rest: 120, increment: 5,
                 cues: ["Fødderne midt på pladen i skulderbredde", "Sænk til knæene er cirka 90 grader",
                        "Pres op uden at låse knæene", "Lænden helt inde mod sædet"],
                 home: "Squat med en tung rygsæk"),
        Exercise(id: "goblet", name: "Goblet squat", muscles: "Ben og numse", area: .legs, pattern: "squat",
                 sets: 3, repsLow: 10, repsHigh: 12, rest: 90, increment: 2,
                 cues: ["Hold håndvægten lodret ind til brystet", "Fødderne lidt bredere end skuldrene",
                        "Sæt dig ned mellem hælene med brystet op", "Pres op gennem hele foden"],
                 home: "Squat med en rygsæk foran brystet"),
        Exercise(id: "bwsquat", name: "Squat uden vægt", muscles: "Ben og numse", area: .legs, pattern: "squat",
                 sets: 3, repsLow: 15, repsHigh: 20, rest: 60, bodyweight: true, gear: .home,
                 cues: ["Fødderne i skulderbredde", "Hænderne bag hovedet eller strakt frem",
                        "Sæt dig ned og tilbage, hælene bliver i gulvet", "Rejs dig og spænd numsen"]),
        Exercise(id: "rdl", name: "Rumænsk dødløft", muscles: "Baglår, numse og lænd", area: .legs, pattern: "hinge",
                 sets: 3, repsLow: 8, repsHigh: 10, rest: 120,
                 cues: ["Stangen tæt ind til benene", "Let bøjede knæ",
                        "Skub hoften bagud med helt lige ryg", "Stop når baglårene strammer, og skub hoften frem igen"],
                 home: "Dødløft med en tung rygsæk"),
        Exercise(id: "hipthrust", name: "Hip thrust", muscles: "Numse og baglår", area: .legs, pattern: "glute",
                 sets: 3, repsLow: 10, repsHigh: 12, rest: 90,
                 cues: ["Øvre ryg mod bænken, stangen over hoften med en pude", "Fødderne i gulvet, knæene bøjede",
                        "Pres hoften op, til kroppen er lige", "Klem numsen i toppen, langsomt ned"],
                 home: "Hofteløft på gulvet"),
        Exercise(id: "glutebridge", name: "Hofteløft", muscles: "Numse og baglår", area: .legs, pattern: "glute",
                 sets: 3, repsLow: 12, repsHigh: 20, rest: 60, bodyweight: true, gear: .home,
                 cues: ["Lig på ryggen med bøjede knæ", "Fødderne tæt på numsen",
                        "Pres hoften op, til kroppen er lige fra knæ til skuldre", "Klem numsen i et sekund i toppen"]),
        Exercise(id: "lunge", name: "Lunges", muscles: "Ben og numse", area: .legs, pattern: "lunge",
                 sets: 2, repsLow: 10, repsHigh: 10, unit: .perLeg, rest: 90, increment: 1, gear: .both,
                 cues: ["Tag et langt skridt frem", "Sænk det bageste knæ mod gulvet",
                        "Forreste knæ over foden", "Pres tilbage gennem hælen"],
                 home: "Lunges uden vægt eller med rygsæk"),
        Exercise(id: "splitsquat", name: "Bulgarsk split squat", muscles: "Ben og numse", area: .legs, pattern: "lunge",
                 sets: 3, repsLow: 8, repsHigh: 12, unit: .perLeg, rest: 90, increment: 1, gear: .both,
                 cues: ["Bageste fod oppe på en bænk eller stol", "Forreste fod et godt skridt frem",
                        "Sænk dig lige ned, til forreste lår er vandret", "Pres op gennem forreste hæl"],
                 home: "Uden håndvægte, med bagfoden på en stol"),
        Exercise(id: "stepup", name: "Step-ups", muscles: "Ben og numse", area: .legs, pattern: "lunge",
                 sets: 3, repsLow: 10, repsHigh: 12, unit: .perLeg, rest: 60, increment: 1, gear: .both,
                 cues: ["En bænk eller et trin i knæhøjde", "Hele foden op på trinet",
                        "Pres op gennem hælen uden at hoppe", "Langsomt ned, og skift ben"],
                 home: "På en stol eller et trappetrin"),
        Exercise(id: "legcurl", name: "Leg curl", muscles: "Baglår", area: .legs, pattern: "legiso",
                 sets: 3, repsLow: 10, repsHigh: 15, rest: 60,
                 cues: ["Lig på maven, puden lige over hælene", "Hoften nede mod bænken",
                        "Bøj benene, til puden er tæt på numsen", "Langsomt ned"],
                 home: "Hofteløft på ét ben"),
        Exercise(id: "legext", name: "Leg extension", muscles: "Forlår", area: .legs, pattern: "legiso",
                 sets: 3, repsLow: 10, repsHigh: 15, rest: 60,
                 cues: ["Ryggen mod ryglænet, puden foran anklerne", "Stræk benene helt ud",
                        "Hold et sekund i toppen", "Langsomt ned"],
                 home: "Squat uden vægt, langsomt ned"),
        Exercise(id: "calf", name: "Tåhævninger", muscles: "Lægge", area: .legs, pattern: "calf",
                 sets: 3, repsLow: 12, repsHigh: 20, rest: 45, gear: .both,
                 cues: ["Forfoden på en kant, hælene fri", "Pres dig op på tæerne, så højt du kan",
                        "Hold et sekund", "Sænk hælene langt ned"],
                 home: "På et trappetrin uden vægt"),
        // Bryst
        Exercise(id: "bench", name: "Bænkpres", muscles: "Bryst, skuldre og triceps", area: .chest, pattern: "hpush",
                 sets: 3, repsLow: 8, repsHigh: 10, rest: 120,
                 cues: ["Skulderbladene samlet og trukket ned", "Fødderne fast i gulvet",
                        "Sænk stangen til nederste del af brystet", "Pres op og lidt bagud"],
                 home: "Armbøjninger"),
        Exercise(id: "incline", name: "Skråbænkpres med håndvægte", muscles: "Øvre bryst og skuldre", area: .chest, pattern: "hpush",
                 sets: 3, repsLow: 10, repsHigh: 12, rest: 90, increment: 1,
                 cues: ["Bænken på 30-45 grader", "Skulderbladene samlet",
                        "Sænk håndvægtene til brystet", "Pres op og lidt ind mod hinanden"],
                 home: "Armbøjninger med fødderne på en stol"),
        Exercise(id: "pushup", name: "Armbøjninger", muscles: "Bryst og triceps", area: .chest, pattern: "hpush",
                 sets: 3, repsLow: 8, repsHigh: 20, rest: 90, bodyweight: true, gear: .both,
                 cues: ["Hænderne lidt bredere end skuldrene", "Kroppen lige som en planke",
                        "Brystet ned mod gulvet", "Så mange du kan med god teknik"],
                 home: "For svært? Hænderne på en stol. For let? Fødderne på en stol."),
        Exercise(id: "dips", name: "Dips", muscles: "Bryst, triceps og skuldre", area: .chest, pattern: "hpush",
                 sets: 3, repsLow: 6, repsHigh: 12, rest: 90, bodyweight: true,
                 cues: ["Tag fat i stængerne med strakte arme", "Læn dig lidt frem",
                        "Sænk dig, til albuerne er cirka 90 grader", "Pres op igen"],
                 home: "Dips på kanten af en stol"),
        Exercise(id: "fly", name: "Flyes med håndvægte", muscles: "Bryst", area: .chest, pattern: "chestiso",
                 sets: 3, repsLow: 10, repsHigh: 15, rest: 60, increment: 1,
                 cues: ["Lig på bænken med håndvægtene over brystet", "Let bøjede albuer hele vejen",
                        "Åbn armene ud til siden i en bue", "Klem dem sammen igen over brystet"],
                 home: "Armbøjninger med brede hænder"),
        // Ryg
        Exercise(id: "row", name: "Roning", muscles: "Ryg og biceps", area: .back, pattern: "hpull",
                 sets: 3, repsLow: 10, repsHigh: 12, rest: 90,
                 cues: ["Ryggen lige, brystet op", "Træk albuerne tilbage langs kroppen",
                        "Klem skulderbladene sammen i toppen", "Langsomt tilbage"],
                 home: "Roning under et bord"),
        Exercise(id: "onearmrow", name: "Roning med én arm", muscles: "Ryg og biceps", area: .back, pattern: "hpull",
                 sets: 3, repsLow: 10, repsHigh: 12, rest: 90, increment: 1,
                 cues: ["Knæ og hånd på bænken", "Ryggen flad",
                        "Træk håndvægten op mod hoften", "Langsomt ned"],
                 home: "Roning med en rygsæk i én hånd"),
        Exercise(id: "invrow", name: "Roning under et bord", muscles: "Ryg og biceps", area: .back, pattern: "hpull",
                 sets: 3, repsLow: 8, repsHigh: 15, rest: 90, bodyweight: true, gear: .home,
                 cues: ["Lig under et solidt bord eller en stang i hoftehøjde", "Tag fat med begge hænder, kroppen lige",
                        "Træk brystet op mod kanten", "Langsomt ned"]),
        Exercise(id: "pullup", name: "Pull-ups eller lat pulldown", muscles: "Ryg og biceps", area: .back, pattern: "vpull",
                 sets: 3, repsLow: 8, repsHigh: 12, rest: 90,
                 cues: ["Greb lidt bredere end skuldrene", "Træk albuerne ned mod siden",
                        "Brystet op mod stangen", "Langsomt tilbage"],
                 home: "Pull-up-stang i en dørkarm"),
        Exercise(id: "superman", name: "Superman", muscles: "Lænd og ryg", area: .back, pattern: "backiso",
                 sets: 3, repsLow: 10, repsHigh: 15, rest: 45, bodyweight: true, gear: .both,
                 cues: ["Lig på maven med armene strakt frem", "Løft arme, bryst og ben fra gulvet",
                        "Hold i 2 sekunder", "Langsomt ned"]),
        // Skuldre
        Exercise(id: "ohp", name: "Skulderpres med håndvægte", muscles: "Skuldre og triceps", area: .shoulders, pattern: "vpush",
                 sets: 2, repsLow: 10, repsHigh: 12, rest: 90, increment: 1,
                 cues: ["Sid eller stå med ret ryg", "Håndvægtene ved skuldrene",
                        "Pres lige op, til armene er strakte", "Stram maven, svaj ikke i ryggen"],
                 home: "Skulderpres med to vandflasker eller en rygsæk"),
        Exercise(id: "lateral", name: "Sidehævninger", muscles: "Skuldre", area: .shoulders, pattern: "shoulderiso",
                 sets: 3, repsLow: 12, repsHigh: 15, rest: 60, increment: 1,
                 cues: ["Let bøjede albuer", "Løft armene ud til siden til skulderhøjde",
                        "Ingen sving", "Langsomt ned"],
                 home: "Sidehævninger med to vandflasker"),
        Exercise(id: "facepull", name: "Face pull", muscles: "Bagskuldre og øvre ryg", area: .shoulders, pattern: "shoulderiso",
                 sets: 3, repsLow: 12, repsHigh: 15, rest: 60,
                 cues: ["Rebet i øjenhøjde på kabelmaskinen", "Træk rebet ind mod ansigtet",
                        "Albuerne højt og ud til siden", "Klem skulderbladene sammen"],
                 home: "Superman på gulvet"),
        // Arme
        Exercise(id: "curl", name: "Biceps curl", muscles: "Biceps", area: .arms, pattern: "biceps",
                 sets: 2, repsLow: 12, repsHigh: 12, rest: 60, increment: 1,
                 cues: ["Albuerne ind til kroppen", "Bøj op uden at svinge",
                        "Klem i toppen", "Langsomt ned"],
                 home: "Curl med en rygsæk eller vandflasker"),
        Exercise(id: "hammer", name: "Hammer curl", muscles: "Biceps og underarme", area: .arms, pattern: "biceps",
                 sets: 3, repsLow: 10, repsHigh: 12, rest: 60, increment: 1,
                 cues: ["Tommelfingrene peger opad", "Albuerne ind til kroppen",
                        "Bøj op uden at svinge", "Langsomt ned"],
                 home: "Hammer curl med vandflasker"),
        Exercise(id: "pushdown", name: "Triceps pushdown", muscles: "Triceps", area: .arms, pattern: "triceps",
                 sets: 2, repsLow: 12, repsHigh: 12, rest: 60,
                 cues: ["Albuerne ind til siden", "Pres ned, til armene er strakte",
                        "Kun underarmene bevæger sig", "Langsomt op"],
                 home: "Dips på kanten af en stol"),
        Exercise(id: "overhead", name: "Triceps over hovedet", muscles: "Triceps", area: .arms, pattern: "triceps",
                 sets: 3, repsLow: 10, repsHigh: 12, rest: 60, increment: 1,
                 cues: ["Hold én håndvægt med begge hænder over hovedet", "Overarmene tæt ind til hovedet",
                        "Sænk vægten ned bag nakken", "Stræk armene op igen"],
                 home: "Dips på kanten af en stol"),
        Exercise(id: "benchdip", name: "Dips på en stol", muscles: "Triceps", area: .arms, pattern: "triceps",
                 sets: 3, repsLow: 8, repsHigh: 15, rest: 60, bodyweight: true, gear: .home,
                 cues: ["Hænderne på kanten af en stol eller bænk", "Benene strakt frem",
                        "Sænk dig, til albuerne er cirka 90 grader", "Pres op igen"]),
        // Mave
        Exercise(id: "plank", name: "Planke", muscles: "Mave og core", area: .abs, pattern: "core",
                 sets: 3, repsLow: 30, repsHigh: 45, unit: .seconds, rest: 60, bodyweight: true, gear: .both,
                 cues: ["Albuerne lige under skuldrene", "Kroppen i én lige linje",
                        "Spænd mave og numse", "Træk vejret roligt"]),
        Exercise(id: "kneeraise", name: "Hængende knæløft", muscles: "Mave", area: .abs, pattern: "core",
                 sets: 3, repsLow: 10, repsHigh: 15, rest: 60, bodyweight: true,
                 cues: ["Hæng i strakte arme", "Løft knæene op mod brystet",
                        "Sving ikke med kroppen", "Langsomt ned"],
                 home: "Knæløft liggende på ryggen"),
        Exercise(id: "crunch", name: "Mavebøjninger", muscles: "Mave", area: .abs, pattern: "core",
                 sets: 3, repsLow: 15, repsHigh: 20, rest: 45, bodyweight: true, gear: .both,
                 cues: ["Lig på ryggen med bøjede knæ", "Hænderne ved tindingerne, ikke bag nakken",
                        "Rul skuldrene op fra gulvet", "Langsomt ned"]),
        Exercise(id: "deadbug", name: "Dead bug", muscles: "Dyb mave og core", area: .abs, pattern: "core",
                 sets: 3, repsLow: 8, repsHigh: 12, unit: .perSide, rest: 45, bodyweight: true, gear: .both,
                 cues: ["Lig på ryggen, arme og knæ i vejret", "Lænden presset ned i gulvet",
                        "Stræk modsat arm og ben ud", "Tilbage, og skift side"]),
        Exercise(id: "sideplank", name: "Sideplanke", muscles: "Skrå mavemuskler", area: .abs, pattern: "core",
                 sets: 2, repsLow: 20, repsHigh: 40, unit: .seconds, rest: 45, bodyweight: true, gear: .both,
                 cues: ["Lig på siden på én albue", "Albuen lige under skulderen",
                        "Løft hoften, så kroppen er lige", "Hold, og skift side"]),
        Exercise(id: "twist", name: "Russian twist", muscles: "Skrå mavemuskler", area: .abs, pattern: "core",
                 sets: 3, repsLow: 10, repsHigh: 15, unit: .perSide, rest: 45, bodyweight: true, gear: .both,
                 cues: ["Sid med bøjede knæ og læn dig lidt tilbage", "Ryggen lige",
                        "Drej overkroppen fra side til side", "Hold gerne en vægt eller en flaske"]),
        Exercise(id: "climber", name: "Mountain climbers", muscles: "Mave og kondition", area: .abs, pattern: "core",
                 sets: 3, repsLow: 20, repsHigh: 40, unit: .seconds, rest: 45, bodyweight: true, gear: .both,
                 cues: ["Start i armbøjningsstilling", "Træk skiftevis knæene op mod brystet",
                        "Hold hoften nede", "Hurtigt, men kontrolleret"]),
    ]
}

// MARK: - Building a program from the profile

enum TrainingBuilder {
    /// Exercises per workout for each length.
    static func count(minutes: Int) -> Int { minutes <= 30 ? 4 : minutes <= 45 ? 5 : 6 }

    /// The order of movements in each workout, most important first. Core is put last.
    static func template(days: Int) -> [(id: String, name: String, slots: [String])] {
        switch days {
        case ...2:
            return [("A", "Hele kroppen", ["squat", "hpush", "hpull", "glute", "shoulderiso", "biceps", "core"]),
                    ("B", "Hele kroppen", ["hinge", "vpull", "hpush", "lunge", "triceps", "calf", "core"])]
        case 4...:
            return [("A", "Overkrop", ["hpush", "hpull", "vpush", "vpull", "shoulderiso", "triceps", "biceps"]),
                    ("B", "Underkrop", ["squat", "hinge", "lunge", "legiso", "calf", "core", "core"]),
                    ("C", "Overkrop", ["hpush", "vpull", "hpull", "hpush", "shoulderiso", "biceps", "triceps"]),
                    ("D", "Underkrop", ["squat", "glute", "lunge", "legiso", "calf", "core", "core"])]
        default:
            return [("A", "Hele kroppen", ["squat", "hpush", "hpull", "vpush", "legiso", "biceps", "core"]),
                    ("B", "Hele kroppen", ["hinge", "vpull", "hpush", "lunge", "shoulderiso", "triceps", "core"]),
                    ("C", "Hele kroppen", ["squat", "hpush", "hpull", "shoulderiso", "glute", "biceps", "triceps", "core"])]
        }
    }

    /// When nothing fits a movement (often at home), the next best one.
    static let fallback = ["hinge": "glute", "vpull": "hpull", "vpush": "hpush", "legiso": "lunge",
                           "chestiso": "hpush", "shoulderiso": "vpush", "biceps": "hpull", "backiso": "hpull"]

    static func focusPattern(_ a: Area, session: Int) -> String {
        switch a {
        case .legs: return "glute"
        case .chest: return "chestiso"
        case .back: return "hpull"
        case .shoulders: return "shoulderiso"
        case .arms: return session % 2 == 0 ? "biceps" : "triceps"
        case .abs: return "core"
        }
    }

    /// Sets, reps and rest for the goal and level.
    static func dose(_ ex: Exercise, _ p: TrainingProfile) -> PlanItem {
        var (sets, lo, hi, rest): (Int, Int, Int, Int)
        if ex.compound {
            switch p.goal {
            case .strength: (sets, lo, hi, rest) = (4, 5, 8, 150)
            case .muscle: (sets, lo, hi, rest) = (3, 8, 12, 120)
            case .recomp: (sets, lo, hi, rest) = (3, 8, 12, 90)
            case .fit: (sets, lo, hi, rest) = (3, 12, 15, 60)
            }
        } else {
            switch p.goal {
            case .strength: (sets, lo, hi, rest) = (3, 8, 12, 90)
            case .muscle, .recomp: (sets, lo, hi, rest) = (3, 10, 15, 60)
            case .fit: (sets, lo, hi, rest) = (2, 15, 20, 45)
            }
        }
        // New: three sets on the big lifts to learn them, two on the small ones.
        if p.level == .new { sets = ex.compound ? min(sets, 3) : max(2, sets - 1) }
        if p.level == .trained && ex.compound && p.goal != .fit { sets = max(sets, 4) }
        // Bodyweight, timed and per-leg work keep their own ranges.
        if ex.bodyweight || ex.unit != .reps {
            (lo, hi) = (ex.repsLow, ex.repsHigh)
            rest = min(rest, ex.rest)
        }
        if ex.unit == .perLeg { (lo, hi) = (min(lo, 10), min(hi, 12)) }
        return PlanItem(exercise: ex.id, sets: sets, repsLow: lo, repsHigh: hi, rest: rest)
    }

    static func fits(_ ex: Exercise, _ place: Place) -> Bool {
        place == .gym ? ex.gear != .home : ex.gear != .gym
    }

    static func build(_ p: TrainingProfile) -> [TrainingSession] {
        let n = count(minutes: p.minutes)
        var used: [String: Int] = [:]
        return template(days: p.days).enumerated().map { si, t in
            let lower = t.name == "Underkrop", upper = t.name == "Overkrop"
            var list: [String] = []

            func pick(_ pattern: String, area: Area? = nil) {
                func candidates(_ pat: String) -> [Exercise] {
                    TrainingProgram.all.filter { $0.pattern == pat && fits($0, p.place) && !list.contains($0.id) }
                }
                var c = candidates(pattern)
                if c.isEmpty, let f = fallback[pattern] { c = candidates(f) }
                if c.isEmpty, let area { c = TrainingProgram.all.filter { $0.area == area && fits($0, p.place) && !list.contains($0.id) } }
                let order = TrainingProgram.all.map(\.id)
                guard let best = c.min(by: { (used[$0.id, default: 0], order.firstIndex(of: $0.id)!) < (used[$1.id, default: 0], order.firstIndex(of: $1.id)!) })
                else { return }
                list.append(best.id)
                used[best.id, default: 0] += 1
            }

            let focus = p.focus.prefix(2).filter { a in
                if a == .legs && upper { return false }
                if [.chest, .back, .shoulders, .arms].contains(a) && lower { return false }
                return true
            }
            // The first three movements always stay. Then your focus, then core, then the rest.
            let main = t.slots.filter { $0 != "core" }
            let cores = t.slots.filter { $0 == "core" }.count
            let base = min(3, main.count)
            var room = n - base
            let f = Array(focus.prefix(room))
            room -= f.count
            let wantCore = min(room, cores == 0 ? 0 : (cores > 1 && n >= 6 ? 2 : 1))
            room -= wantCore
            var mi = 0
            while list.count < base + room && mi < main.count { pick(main[mi]); mi += 1 }
            for a in f { pick(focusPattern(a, session: si), area: a) }
            while list.count < n - wantCore && mi < main.count { pick(main[mi]); mi += 1 }
            for _ in 0..<wantCore { pick("core", area: .abs) }

            // Big lifts first, small ones after, mave last.
            let rank: (Exercise) -> Int = { $0.area == .abs ? 2 : $0.compound ? 0 : 1 }
            let items = list.compactMap { TrainingProgram.exercise($0) }.enumerated()
                .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
                .map { dose($0.element, p) }
            return TrainingSession(id: t.id, name: t.name, items: items)
        }
    }
}

// MARK: - Log

struct LoggedSet: Codable, Hashable {
    var kg: Double
    var reps: Int
    var done = false
}

struct ExerciseLog: Codable, Hashable, Identifiable {
    var exercise: String
    var sets: [LoggedSet]
    var id: String { exercise }

    /// The heaviest finished set (most reps for bodyweight).
    var best: LoggedSet? {
        sets.filter(\.done).max { ($0.kg, $0.reps) < ($1.kg, $1.reps) }
    }
}

struct WorkoutLog: Codable, Identifiable, Hashable {
    var id = UUID()
    var session: String
    var started: Date
    var finished: Date
    var exercises: [ExerciseLog]

    var doneSets: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.done).count } }
    /// Kilos lifted in total (kg × reps over finished sets).
    var volume: Double { exercises.reduce(0) { $0 + $1.sets.filter(\.done).reduce(0) { $0 + $1.kg * Double($1.reps) } } }
}

/// The workout going on right now. Kept on disk, so closing the window loses nothing.
struct ActiveWorkout: Codable, Hashable {
    var session: String
    var started: Date
    var exercises: [ExerciseLog]
    var restEnds: Date?
}

@MainActor
final class TrainingStore: ObservableObject {
    static var shared = TrainingStore(url: CookieJar.dir.appendingPathComponent("training.json"))

    @Published private(set) var logs: [WorkoutLog] = []
    @Published var active: ActiveWorkout? { didSet { save() } }
    /// Nil until the setup is done.
    @Published var profile: TrainingProfile? { didSet { save() } }
    @Published var program: [TrainingSession] = TrainingProgram.standard { didSet { save() } }
    @Published private(set) var weights: [BodyWeight] = []
    private let url: URL?

    private struct File: Codable {
        var logs: [WorkoutLog]
        var active: ActiveWorkout?
        var profile: TrainingProfile?
        var program: [TrainingSession]?
        var weights: [BodyWeight]?
    }

    /// `url` nil keeps everything in memory (tests and pictures).
    init(url: URL?) {
        self.url = url
        if let url, let f = try? JSONDecoder().decode(File.self, from: Data(contentsOf: url)) {
            logs = f.logs
            active = f.active
            profile = f.profile
            if let p = f.program, !p.isEmpty { program = p }
            weights = f.weights ?? []
        }
    }

    private func save() {
        guard let url else { return }
        let f = File(logs: logs, active: active, profile: profile, program: program, weights: weights)
        try? JSONEncoder().encode(f).write(to: url, options: .atomic)
    }

    var order: [String] { program.map(\.id) }
    var wish: TrainingPlanner.Wish { profile?.wish ?? TrainingPlanner.Wish() }

    func session(_ id: String) -> TrainingSession? { program.first { $0.id == id } }

    /// The exercises of a workout, with your program's sets, reps and rest.
    func exercises(_ session: String) -> [Exercise] {
        (self.session(session)?.items ?? []).compactMap { apply($0) }
    }

    /// One exercise as it is in a workout (falls back to its own defaults).
    func spec(_ exercise: String, session: String) -> Exercise? {
        if let item = self.session(session)?.items.first(where: { $0.exercise == exercise }) { return apply(item) }
        return TrainingProgram.exercise(exercise)
    }

    private func apply(_ item: PlanItem) -> Exercise? {
        guard var ex = TrainingProgram.exercise(item.exercise) else { return nil }
        ex.sets = item.sets; ex.repsLow = item.repsLow; ex.repsHigh = item.repsHigh; ex.rest = item.rest
        return ex
    }

    /// Saves the setup and the program built from it. Your weight goes in the log too.
    func apply(profile p: TrainingProfile, program list: [TrainingSession]? = nil, now: Date = Date()) {
        profile = p
        program = list ?? TrainingBuilder.build(p)
        if p.weight > 0 { logWeight(p.weight, at: now) }
    }

    /// One weight per day: a new one the same day replaces it.
    func logWeight(_ kg: Double, at now: Date = Date()) {
        guard kg > 0 else { return }
        weights.removeAll { DateUtil.cal.isDate($0.date, inSameDayAs: now) }
        weights.append(BodyWeight(date: now, kg: kg))
        weights.sort { $0.date < $1.date }
        if profile != nil { profile?.weight = weights.last!.kg } else { save() }
    }

    func deleteWeight(_ w: BodyWeight) {
        weights.removeAll { $0.id == w.id }
        save()
    }

    /// The session after the last one you finished: A, B, C, A …
    var nextSession: String {
        let o = order
        guard let first = o.first else { return "A" }
        guard let last = logs.max(by: { $0.started < $1.started }), let i = o.firstIndex(of: last.session) else { return first }
        return o[(i + 1) % o.count]
    }

    /// The most recent time you did this exercise.
    func last(_ exercise: String) -> ExerciseLog? {
        logs.sorted { $0.started > $1.started }.lazy.compactMap { $0.exercises.first { $0.exercise == exercise } }
            .first { $0.sets.contains(where: \.done) }
    }

    /// The weight to use today: last time's, plus the step once every set reached the top of the range.
    func suggestedKg(_ ex: Exercise) -> Double? {
        guard !ex.bodyweight, let last = last(ex.id) else { return nil }
        let done = last.sets.filter(\.done)
        guard let kg = done.map(\.kg).max(), kg > 0 else { return nil }
        let allTop = done.count >= ex.sets && done.allSatisfy { $0.reps >= ex.repsHigh }
        return allTop ? kg + ex.increment : kg
    }

    func start(_ session: String, at now: Date = Date()) {
        let list = exercises(session).map { ex -> ExerciseLog in
            let prev = last(ex.id)?.sets.filter(\.done)
            let kg = suggestedKg(ex) ?? prev?.first?.kg ?? 0
            let sets = (0..<ex.sets).map { i in
                LoggedSet(kg: ex.bodyweight ? 0 : kg, reps: prev.flatMap { $0.indices.contains(i) ? $0[i].reps : $0.last?.reps } ?? ex.repsLow)
            }
            return ExerciseLog(exercise: ex.id, sets: sets)
        }
        active = ActiveWorkout(session: session, started: now, exercises: list)
    }

    /// Ticks a set and starts the rest timer when it becomes done.
    func toggle(exercise: Int, set: Int, now: Date = Date()) {
        guard var a = active, a.exercises.indices.contains(exercise), a.exercises[exercise].sets.indices.contains(set) else { return }
        a.exercises[exercise].sets[set].done.toggle()
        if a.exercises[exercise].sets[set].done, let ex = spec(a.exercises[exercise].exercise, session: a.session) {
            a.restEnds = now.addingTimeInterval(Double(ex.rest))
        }
        active = a
    }

    func addSet(exercise: Int) {
        guard var a = active, a.exercises.indices.contains(exercise) else { return }
        let last = a.exercises[exercise].sets.last ?? LoggedSet(kg: 0, reps: 10)
        a.exercises[exercise].sets.append(LoggedSet(kg: last.kg, reps: last.reps))
        active = a
    }

    /// Saves the workout (only finished sets) and returns it. Nil when nothing was ticked.
    @discardableResult
    func finish(at now: Date = Date()) -> WorkoutLog? {
        guard let a = active else { return nil }
        active = nil
        let ex = a.exercises.compactMap { e -> ExerciseLog? in
            let done = e.sets.filter(\.done)
            return done.isEmpty ? nil : ExerciseLog(exercise: e.exercise, sets: done)
        }
        guard !ex.isEmpty else { save(); return nil }
        let log = WorkoutLog(session: a.session, started: a.started, finished: now, exercises: ex)
        logs.append(log)
        save()
        return log
    }

    func cancel() { active = nil }

    func delete(_ log: WorkoutLog) {
        logs.removeAll { $0.id == log.id }
        save()
    }

    /// Exercises where this workout beat every earlier one.
    func records(in log: WorkoutLog) -> [String] {
        log.exercises.compactMap { e in
            guard let b = e.best else { return nil }
            let before = logs.filter { $0.started < log.started }.compactMap { $0.exercises.first { $0.exercise == e.exercise }?.best }
            guard let prev = before.max(by: { ($0.kg, $0.reps) < ($1.kg, $1.reps) }) else { return nil }
            return (b.kg, b.reps) > (prev.kg, prev.reps) ? e.exercise : nil
        }
    }

    /// Best set per workout for one exercise, oldest first: kilos, or reps for bodyweight.
    func history(_ exercise: String) -> [(Date, Double)] {
        let bw = TrainingProgram.exercise(exercise)?.bodyweight ?? false
        return logs.sorted { $0.started < $1.started }.compactMap { l in
            guard let b = l.exercises.first(where: { $0.exercise == exercise })?.best else { return nil }
            return (l.started, bw ? Double(b.reps) : b.kg)
        }
    }

    /// Weeks in a row (this one included once it has a workout) with at least one workout.
    func weeksInRow(now: Date = Date()) -> Int {
        let cal = DateUtil.cal
        let weeks = Set(logs.compactMap { cal.dateInterval(of: .weekOfYear, for: $0.started)?.start })
        guard var w = cal.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(w) { w = cal.date(byAdding: .weekOfYear, value: -1, to: w)! }
        var n = 0
        while weeks.contains(w) { n += 1; w = cal.date(byAdding: .weekOfYear, value: -1, to: w)! }
        return n
    }

    func thisWeek(now: Date = Date()) -> Int {
        guard let w = DateUtil.cal.dateInterval(of: .weekOfYear, for: now) else { return 0 }
        return logs.filter { w.contains($0.started) }.count
    }

    /// Fills the store with made-up workouts and weights (pictures and tests only).
    func fillDemo(now: Date = Date()) {
        var list: [WorkoutLog] = []
        for w in 0..<6 {
            for (i, s) in order.enumerated() {
                let day = DateUtil.cal.date(byAdding: .day, value: -((5 - w) * 7 + (4 - i * 2)), to: now)!
                let ex = exercises(s).map { e in
                    let kg = e.bodyweight ? 0 : (e.increment >= 2.5 ? 30 : 8) + Double(w) * e.increment
                    return ExerciseLog(exercise: e.id, sets: (0..<e.sets).map { _ in LoggedSet(kg: kg, reps: e.repsLow + w % 3, done: true) })
                }
                list.append(WorkoutLog(session: s, started: day, finished: day.addingTimeInterval(55 * 60), exercises: ex))
            }
        }
        logs = list
        weights = (0..<6).map { w in
            BodyWeight(date: DateUtil.cal.date(byAdding: .day, value: -(5 - w) * 7, to: now)!, kg: 82 - Double(w) * 0.3)
        }
    }
}

// MARK: - Finding time in the schedule

enum TrainingPlanner {
    /// `PlannedItem.from` for workouts Viggo+ put in the schedule.
    static let tag = "Træning i Viggo+"

    /// What the planner looks for, from your setup.
    struct Wish: Equatable {
        var count = 3
        var minutes = 60
        var when: TimeOfDay = .afternoon
        /// Weekdays to leave out, 1 = Monday ... 7 = Sunday.
        var skip: Set<Int> = []
        /// Home workouts can go on days you are not at school too.
        var anywhere = false
        var length: TimeInterval { Double(minutes) * 60 }
    }

    struct Slot: Hashable { let start: Date; let end: Date }

    static func weekday(_ d: Date) -> Int { (DateUtil.cal.component(.weekday, from: d) + 5) % 7 + 1 }

    /// What fills the day: lessons, events, everyday routines and your own items. Teachers'
    /// duties and birthdays are not yours, so they don't count.
    static func busy(on day: Date, events: [ViggoEvent], planned: [PlannedItem], custom: [CustomItem], ignoring: UUID? = nil) -> [(Date, Date, String)] {
        let cal = DateUtil.cal
        var out = events.filter { [.lesson, .event, .routine].contains($0.kind) && cal.isDate($0.start, inSameDayAs: day) && $0.end > $0.start }
            .map { ($0.start, $0.end, $0.rawName.trimmingCharacters(in: .whitespaces)) }
        out += planned.filter { $0.id != ignoring && cal.isDate($0.start, inSameDayAs: day) }.map { ($0.start, $0.end, $0.title) }
        out += custom.enumerated().compactMap { $0.element.event(on: day, index: $0.offset) }.map { ($0.start, $0.end, $0.rawName) }
        return out.sorted { $0.0 < $1.0 }
    }

    /// Only days you are at school (Viggo has something that day). Home weekends have no gym.
    static func atSchool(_ day: Date, events: [ViggoEvent]) -> Bool {
        events.contains { ($0.kind == .routine || $0.kind == .lesson) && DateUtil.cal.isDate($0.start, inSameDayAs: day) }
    }

    /// Free gaps long enough for a workout, from 07:00 until "Alle på eget område" (or 21:45).
    /// A workout starts 20 min after a meal at the earliest.
    static func gaps(on day: Date, events: [ViggoEvent], planned: [PlannedItem], custom: [CustomItem],
                     now: Date, ignoring: UUID? = nil, wish: Wish = Wish()) -> [Slot] {
        let cal = DateUtil.cal
        guard !wish.skip.contains(weekday(day)) else { return [] }
        guard atSchool(day, events: events) else {
            // A day at home: one workout at the time you like, if you train at home.
            guard wish.anywhere else { return [] }
            let hour = wish.when == .evening ? 19 : wish.when == .afternoon ? 15 : 11
            let s = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
            return s > now ? [Slot(start: s, end: s.addingTimeInterval(wish.length))] : []
        }
        let items = busy(on: day, events: events, planned: planned, custom: custom, ignoring: ignoring)
        let dayStart = cal.date(bySettingHour: 7, minute: 0, second: 0, of: day)!
        let lights = items.first { let n = $0.2.lowercased(); return n.contains("eget område") || n.contains("eget værelse") || n.hasPrefix("godnat") }?.0
        // Nothing in Viggo after 17:00 (no Aftensmad) means a home weekend starts: the day ends with its last item.
        let evening = cal.date(bySettingHour: 17, minute: 0, second: 0, of: day)!
        let home = items.allSatisfy { $0.1 <= evening } ? items.map(\.1).max() : nil
        let dayEnd = lights ?? home ?? cal.date(bySettingHour: 21, minute: 45, second: 0, of: day)!
        var cursor = max(dayStart, now)
        var out: [Slot] = []
        func add(until end: Date) {
            let start = roundUp(cursor)
            if end.timeIntervalSince(start) >= wish.length { out.append(Slot(start: start, end: end)) }
        }
        for (s, e, name) in items where e > cursor {
            if s > cursor { add(until: min(s, dayEnd)) }
            let n = name.lowercased()
            let meal = n.contains("mad") || n.contains("middag") || n.contains("frokost")
            cursor = max(cursor, meal ? e.addingTimeInterval(20 * 60) : e)
            if cursor >= dayEnd { break }
        }
        if cursor < dayEnd { add(until: dayEnd) }
        return out
    }

    private static func roundUp(_ d: Date) -> Date {
        let m = DateUtil.cal.component(.minute, from: d) % 5
        let s = DateUtil.cal.component(.second, from: d)
        return m == 0 && s == 0 ? d : d.addingTimeInterval(Double((5 - m) * 60 - s))
    }

    private static func hour(_ d: Date) -> Int { DateUtil.cal.component(.hour, from: d) }

    /// Every possible slot in the next `days` days: one per free gap, moved to the time you like when it fits.
    static func options(events: [ViggoEvent], planned: [PlannedItem], custom: [CustomItem], now: Date,
                        days: Int = 7, ignoring: UUID? = nil, wish: Wish = Wish()) -> [Slot] {
        (0..<days).flatMap { i -> [Slot] in
            let day = DateUtil.cal.date(byAdding: .day, value: i, to: DateUtil.startOfDay(now))!
            let from: Date? = wish.when == .evening ? DateUtil.cal.date(bySettingHour: 18, minute: 0, second: 0, of: day)
                : wish.when == .afternoon ? DateUtil.cal.date(bySettingHour: 14, minute: 0, second: 0, of: day) : nil
            return gaps(on: day, events: events, planned: planned, custom: custom, now: now, ignoring: ignoring, wish: wish).map { g in
                var s = g.start
                if let from, from > s, from.addingTimeInterval(wish.length) <= g.end { s = from }
                return Slot(start: s, end: s.addingTimeInterval(wish.length))
            }
        }
    }

    /// Does this slot match the time of day you asked for?
    static func liked(_ s: Slot, _ when: TimeOfDay) -> Bool {
        switch when {
        case .afternoon: return (14..<18).contains(hour(s.start))
        case .evening: return hour(s.start) >= 18
        case .any: return true
        }
    }

    /// Your workouts in the next seven days, on days with a rest day between when possible.
    /// Old planned workouts that have not happened yet are left out, so this replaces them.
    static func suggest(events: [ViggoEvent], planned: [PlannedItem], custom: [CustomItem], now: Date,
                        first: String, order: [String] = ["A", "B", "C"], wish: Wish = Wish()) -> [PlannedItem] {
        let keep = planned.filter { !($0.from == tag && $0.end > now) }
        let all = options(events: events, planned: keep, custom: custom, now: now, wish: wish)
        // One slot per day: the first one at the time you like, else the first of the day.
        var perDay: [Date: Slot] = [:]
        for s in all {
            let d = DateUtil.startOfDay(s.start)
            if let have = perDay[d] {
                if liked(s, wish.when) && !liked(have, wish.when) { perDay[d] = s }
            } else { perDay[d] = s }
        }
        let days = perDay.keys.sorted()
        let n = min(wish.count, days.count)
        guard n > 0, !order.isEmpty else { return [] }
        func gap(_ a: Date, _ b: Date) -> Int { DateUtil.cal.dateComponents([.day], from: a, to: b).day ?? 0 }
        // Best spread: a rest day between (2 days apart) matters most, then the time you like, then earlier.
        var best: [Date] = Array(days.prefix(n)), bestScore = (-1, -1)
        func walk(_ from: Int, _ pick: [Date]) {
            if pick.count == n {
                let spread = n == 1 ? 2 : min(2, zip(pick, pick.dropFirst()).map { gap($0, $1) }.min()!)
                let likes = pick.filter { liked(perDay[$0]!, wish.when) }.count
                let score = (spread, likes)
                if score > bestScore || (score == bestScore && pick.lexicographicallyPrecedes(best)) { best = pick; bestScore = score }
                return
            }
            guard from < days.count else { return }
            for i in from..<days.count { walk(i + 1, pick + [days[i]]) }
        }
        walk(0, [])
        let start = order.firstIndex(of: first) ?? 0
        return best.enumerated().map { i, d in
            let s = perDay[d]!
            let letter = order[(start + i) % order.count]
            return PlannedItem(title: "Træning \(letter)", start: s.start, end: s.end, from: tag)
        }
    }

    /// What a planned workout now overlaps, if Viggo moved something on top of it.
    static func conflict(_ item: PlannedItem, events: [ViggoEvent], custom: [CustomItem]) -> String? {
        busy(on: item.start, events: events, planned: [], custom: custom)
            .first { $0.0 < item.end && $0.1 > item.start }?.2
    }

    /// "Træning B" -> "B".
    static func letter(_ item: PlannedItem) -> String {
        String(item.title.split(separator: " ").last ?? "A")
    }
}

extension ViggoEvent {
    /// A workout Viggo+ put in the schedule.
    var isTraining: Bool { kind == .custom && notes == TrainingPlanner.tag }
    /// "Træning B" -> "B".
    var trainingSession: String? { isTraining ? rawName.split(separator: " ").last.map(String.init) : nil }
}
