import Foundation

/// Moving your login (and your friends') from the Mac app to the iPhone app.
/// The Mac packs it into one file and copies it into the iPhone app's own data container
/// with `devicectl` while the phone is connected. The iPhone app reads it at launch or when
/// it comes to the front, and deletes it straight away.
struct LoginTransfer: Codable {
    var own: LoginStore.Login?
    var session: Data?                       // your Viggo cookies, as CookieJar writes them
    var friends: [Friend] = []
    var friendLogins: [String: LoginStore.Login] = [:]
    var friendSessions: [String: Data] = [:]
    var from: String
    var created = Date()

    /// Where the file lands inside the iPhone app's container.
    static let devicePath = "Documents/viggo-import.plist"

    var isEmpty: Bool { own == nil && session == nil && friends.isEmpty }

    #if os(macOS)
    /// Everything the Mac app has saved.
    static func make() -> LoginTransfer {
        let store = LoginStore.data
        var t = LoginTransfer(own: store.own, session: try? Data(contentsOf: CookieJar.url),
                              from: Host.current().localizedName ?? "Mac'en")
        let friendsURL = CookieJar.dir.appendingPathComponent("friends.json")
        t.friends = (try? JSONDecoder().decode([Friend].self, from: Data(contentsOf: friendsURL))) ?? []
        for f in t.friends {
            if let l = store.friends[f.id.uuidString] { t.friendLogins[f.id.uuidString] = l }
            if let s = try? Data(contentsOf: CookieJar.friendURL(f.id)) { t.friendSessions[f.id.uuidString] = s }
        }
        return t
    }
    #endif

    #if os(iOS)
    static var inbox: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("viggo-import.plist")
    }
    #endif
}

#if os(iOS)
extension AppState {
    /// Picks up a login sent from the Mac. Returns true if there was one.
    @discardableResult
    func importTransfer() -> Bool {
        let url = LoginTransfer.inbox
        guard let data = try? Data(contentsOf: url) else { return false }
        try? FileManager.default.removeItem(at: url)          // never leave a password lying around
        guard let t = try? PropertyListDecoder().decode(LoginTransfer.self, from: data),
              -t.created.timeIntervalSinceNow < 3600 else { return false }

        if let own = t.own { LoginStore.data.own = own }
        if let s = t.session {
            try? s.write(to: CookieJar.url, options: [.atomic, .completeFileProtection])
            CookieJar.restore()
        }
        // Friends: add the ones the phone doesn't have, and give every one the Mac's login and session.
        for f in t.friends {
            let local: Friend
            if let have = friends.first(where: { $0.viggoID == f.viggoID }) { local = have } else { friends.append(f); local = f }
            if let l = t.friendLogins[f.id.uuidString] { LoginStore.data.friends[local.id.uuidString] = l }
            if let s = t.friendSessions[f.id.uuidString] {
                try? s.write(to: CookieJar.friendURL(local.id), options: [.atomic, .completeFileProtection])
            }
            friendExpired.remove(local.id)
        }
        try? JSONEncoder().encode(friends).write(to: CookieJar.dir.appendingPathComponent("friends.json"), options: .atomic)
        needsLogin = false
        loginMessage = "Login hentet fra \(t.from)"
        Haptic.success()
        return true
    }
}
#endif
