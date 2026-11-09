import SwiftUI

// MARK: - Uge

/// One day at a time on the phone: a strip with the week's days on top, the day's
/// schedule as blocks below. Swipe sideways to change day.
struct WeekScreen: View {
    @EnvironmentObject var state: AppState
    @State private var day = DateUtil.startOfDay(Date())
    @State private var person: UUID?

    private var monday: Date { DateUtil.mondayOf(day) }
    private var weekOffset: Int {
        DateUtil.cal.dateComponents([.weekOfYear], from: DateUtil.mondayOf(Date()), to: monday).weekOfYear ?? 0
    }
    private var range: ClosedRange<Int> { person == nil ? -Config.weeksBack...Config.weeksAhead : 0...1 }
    private var homework: [Homework] { person.flatMap { state.friendHomework[$0] } ?? state.homework }

    private func move(days n: Int) {
        let next = DateUtil.add(.day, n, day)
        let off = DateUtil.cal.dateComponents([.weekOfYear], from: DateUtil.mondayOf(Date()), to: DateUtil.mondayOf(next)).weekOfYear ?? 0
        guard range.contains(off) else { return }
        withAnimation(.viggo) { day = next }
    }

    var body: some View {
        let days = (0..<7).map { DateUtil.add(.day, $0, monday) }
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { d in
                        let sel = DateUtil.cal.isDate(d, inSameDayAs: day)
                        let today = DateUtil.cal.isDateInToday(d)
                        Button { withAnimation(.viggo) { day = d } } label: {
                            VStack(spacing: 3) {
                                Text(DateUtil.weekdayF.string(from: d).prefix(3).capitalized)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(sel ? Color.white.opacity(0.85) : .secondary)
                                Text("\(DateUtil.cal.component(.day, from: d))")
                                    .font(.system(size: 17, weight: sel || today ? .bold : .regular))
                                    .foregroundStyle(sel ? Color.white : today ? Color.accentColor : .primary)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 7)
                            .background {
                                if sel { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor) }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScale(scale: 0.9))
                    }
                }
                .padding(.horizontal, 12).padding(.bottom, 8)

                WeekGrid(days: [day], items: { state.weekItems($0, person: person) },
                         homework: { d in homework.filter { DateUtil.cal.isDate($0.due, inSameDayAs: d) } },
                         hourHeight: 64, dayNames: false)
                    .id(day)
                    .transition(.opacity)
                    .padding(.horizontal, 12)
                    .gesture(DragGesture(minimumDistance: 30).onEnded { g in
                        guard abs(g.translation.width) > abs(g.translation.height) else { return }
                        move(days: g.translation.width < 0 ? 1 : -1)
                    })
            }
            .navigationTitle("Uge \(DateUtil.cal.component(.weekOfYear, from: monday))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { move(days: -7) } label: { Image(systemName: "chevron.left") }
                        .disabled(weekOffset <= range.lowerBound)
                    Button { move(days: 7) } label: { Image(systemName: "chevron.right") }
                        .disabled(weekOffset >= range.upperBound)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !DateUtil.cal.isDateInToday(day) {
                        Button("I dag") { withAnimation(.viggo) { day = DateUtil.startOfDay(Date()) } }
                    }
                    if !state.friends.isEmpty {
                        Menu {
                            Picker("Person", selection: $person) {
                                Text("Mig").tag(UUID?.none)
                                ForEach(state.friends) { f in Text(f.firstName).tag(UUID?.some(f.id)) }
                            }
                        } label: {
                            Image(systemName: person == nil ? "person.crop.circle" : "person.crop.circle.fill")
                        }
                    }
                }
            }
            .onChange(of: person) {
                if !range.contains(weekOffset) { day = DateUtil.startOfDay(Date()) }
            }
        }
    }
}

// MARK: - Venner

struct FriendsScreen: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        NavigationStack {
            List {
                if state.friends.isEmpty {
                    ContentUnavailableView {
                        Label("Ingen venner endnu", systemImage: "person.2")
                    } description: {
                        Text("Tilføj en ven for at se deres skema, og hvornår I har fri samtidig.")
                    } actions: {
                        NavigationLink("Tilføj ven") { FriendsTab().navigationTitle("Venner") }
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(state.friends) { f in
                            let (text, free) = state.friendStatus(f, now: state.tick)
                            let expired = state.friendExpired.contains(f.id)
                            NavigationLink {
                                FriendDayScreen(friend: f)
                            } label: {
                                HStack(spacing: 12) {
                                    Avatar(url: f.image, size: 40, name: f.name).opacity(expired ? 0.4 : 1)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(f.name).font(.body.weight(.medium))
                                        HStack(spacing: 5) {
                                            Circle().fill(expired ? Color.gray : free ? .green : .orange).frame(width: 7, height: 7)
                                            Text(expired ? "Skal logge ind igen" : text)
                                                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    } header: {
                        Text("Lige nu")
                    }
                    Section {
                        NavigationLink { FriendsTab().navigationTitle("Administrer venner") } label: {
                            Label("Tilføj eller fjern venner", systemImage: "person.badge.plus")
                        }
                    }
                }
            }
            .navigationTitle("Venner")
            .refreshable { await state.syncFriends() }
        }
    }
}

struct FriendDayScreen: View {
    @EnvironmentObject var state: AppState
    let friend: Friend

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if state.friendExpired.contains(friend.id) {
                    HStack {
                        Text("\(friend.firstName) skal logge ind igen").font(.subheadline).foregroundStyle(.orange)
                        Spacer()
                        Button("Log ind igen") { state.addFriend(relogin: friend) }.controlSize(.small)
                    }
                }
                DayPanel(name: friend.firstName, events: state.friendEvents[friend.id] ?? [],
                         homework: state.friendHomework[friend.id] ?? [], now: state.tick)
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .navigationTitle(friend.firstName)
        .refreshable { await state.syncFriends() }
    }
}

// MARK: - Indstillinger

struct SettingsScreen: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var p = Prefs.shared

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private func row(_ title: String, _ icon: String, _ color: Color) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(color.gradient))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if let p = state.profile {
                    Section {
                        NavigationLink { AccountTab().navigationTitle("Konto") } label: {
                            HStack(spacing: 12) {
                                Avatar(url: p.image, size: 52, name: p.name)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name).font(.title3.weight(.semibold))
                                    Text(Config.baseURL.host ?? "Viggo").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section {
                    NavigationLink { PanelTab().navigationTitle("I dag") } label: { row("I dag-skærmen", "sun.max.fill", .teal) }
                    NavigationLink { NotificationsTab().navigationTitle("Notifikationer") } label: { row("Notifikationer", "bell.badge.fill", .red) }
                    NavigationLink { LessonsTab().navigationTitle("Timer") } label: { row("Timer", "paintpalette.fill", .pink) }
                    NavigationLink { CustomItemsTab().navigationTitle("Egne punkter") } label: { row("Egne punkter", "checklist", .green) }
                    NavigationLink { FriendsTab().navigationTitle("Venner") } label: { row("Venner", "person.2.fill", .blue) }
                }
                Section {
                    Toggle(isOn: $p.liveActivity) { row("Live Activity i skoletiden", "clock.badge.fill", .orange) }
                        .onChange(of: p.liveActivity) { state.updateLiveActivity() }
                } footer: {
                    Text("Timen der er i gang og nedtællingen står på låseskærmen og i Dynamic Island, fra en halv time før første time til sidste time slutter.")
                }
                Section {
                    Button { state.openViggo() } label: { row("Åbn Viggo", "safari.fill", .indigo) }
                        .foregroundStyle(.primary)
                } footer: {
                    Text("Viggo+ \(version)").frame(maxWidth: .infinity).padding(.top, 12)
                }
            }
            .navigationTitle("Indstillinger")
        }
    }
}
