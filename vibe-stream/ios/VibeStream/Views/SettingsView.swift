import SwiftUI
import VibeCore

struct SettingsView: View {
    @EnvironmentObject private var playlists: PlaylistRepository
    @EnvironmentObject private var content: ContentStore
    @EnvironmentObject private var library: LibraryStore

    @State private var adding = false
    @State private var account: Xtream.AuthInfo?

    private var version: String {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(name) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section(L("Playlists")) {
                    ForEach(playlists.playlists) { p in
                        Button {
                            playlists.selectedID = p.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.name)
                                    Text(p.type == .xtream ? "Xtream · \(p.username)" : "M3U")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if p.id == playlists.selected?.id {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) { remove(p) } label: { Label(L("Delete"), systemImage: "trash") }
                        }
                    }
                    Button { adding = true } label: { Label(L("Add playlist"), systemImage: "plus") }
                    Button {
                        if let id = playlists.selected?.id { content.invalidate(id) }
                    } label: {
                        Label(L("Reload playlist"), systemImage: "arrow.clockwise")
                    }
                }

                if let info = account {
                    Section(L("Account")) {
                        if let status = info.status { LabeledRow(title: L("Status"), value: status) }
                        LabeledRow(title: L("Expires"),
                                   value: info.expires.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? L("Unlimited"))
                        if let max = info.maxConnections {
                            LabeledRow(title: L("Connections"), value: "\(info.activeConnections ?? 0) / \(max)")
                        }
                    }
                }

                Section {
                    Button(role: .destructive) { library.clearHistory() } label: {
                        Label(L("Clear watch history"), systemImage: "clock.arrow.circlepath")
                    }
                }

                Section(L("About")) {
                    LabeledRow(title: L("Version"), value: version)
                    Text(L("Vibe Stream is a fork of IPVIO Stream by Emrodev. Free software under the GNU General Public License v3."))
                        .font(.footnote).foregroundStyle(.secondary)
                    Text(L("Vibe Stream is only a player. It contains no channels, movies or playlists. Use only sources you are allowed to use."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Settings"))
            .sheet(isPresented: $adding) {
                NavigationStack { AddPlaylistView(showsCancel: true) }
            }
        }
        .task(id: playlists.selected?.id) { await loadAccount() }
    }

    private func remove(_ p: Playlist) {
        content.invalidate(p.id)
        library.removeAll(ofPlaylist: p.id)
        playlists.remove(p)
    }

    private func loadAccount() async {
        account = nil
        guard case .xtream(_, let acct)? = playlists.selectedSource else { return }
        account = try? await ContentStore.login(acct)
    }
}

struct LabeledRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}

/// Form for a new playlist: Xtream login or an M3U link.
struct AddPlaylistView: View {
    let showsCancel: Bool

    @EnvironmentObject private var playlists: PlaylistRepository
    @Environment(\.dismiss) private var dismiss

    private enum Mode: Hashable { case xtream, m3u }

    @State private var mode: Mode = .xtream
    @State private var name = ""
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var link = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        Form {
            Section {
                Picker("", selection: $mode) {
                    Text(L("Xtream login")).tag(Mode.xtream)
                    Text(L("M3U link")).tag(Mode.m3u)
                }
                .pickerStyle(.segmented)
            }
            Section {
                if mode == .xtream {
                    TextField(L("Server (e.g. http://server.tld:8080)"), text: $server)
                        .keyboardType(.URL)
                    TextField(L("Username"), text: $username)
                    SecureField(L("Password"), text: $password)
                } else {
                    TextField(L("M3U link"), text: $link)
                        .keyboardType(.URL)
                }
                TextField(L("Name (optional)"), text: $name)
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            if let error = error {
                Section { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button {
                    Task { await add() }
                } label: {
                    HStack {
                        if working { ProgressView() }
                        Text(working ? L("Checking login…") : L("Add"))
                    }
                }
                .disabled(working)
            } footer: {
                Text(L("Vibe Stream is only a player. It contains no channels, movies or playlists. Use only sources you are allowed to use."))
            }
        }
        .navigationTitle(L("Add playlist"))
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
            }
        }
    }

    private func add() async {
        error = nil
        let title = name.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .xtream:
            guard let base = Xtream.normalizeServer(server) else {
                error = L("Please enter a valid server address.")
                return
            }
            let user = username.trimmingCharacters(in: .whitespaces)
            let pass = password.trimmingCharacters(in: .whitespaces)
            guard !user.isEmpty, !pass.isEmpty else {
                error = L("Please enter username and password.")
                return
            }
            await addXtream(XtreamAccount(base: base, username: user, password: pass), title: title)
        case .m3u:
            let address = link.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = address.lowercased()
            guard lower.hasPrefix("http://") || lower.hasPrefix("https://"), URL(string: address) != nil else {
                error = L("Please enter a link that starts with http:// or https://.")
                return
            }
            // A get.php link is an Xtream login in disguise: the API is faster and lighter than the full list
            if let account = Xtream.account(fromURL: address) {
                await addXtream(account, title: title, fallbackM3U: address)
            } else {
                playlists.addM3U(name: title, url: address)
                if showsCancel { dismiss() }
            }
        }
    }

    private func addXtream(_ account: XtreamAccount, title: String, fallbackM3U: String? = nil) async {
        working = true
        defer { working = false }
        do {
            _ = try await ContentStore.login(account)
            playlists.addXtream(name: title, account: account)
            if showsCancel { dismiss() }
        } catch {
            if let address = fallbackM3U, !(error is ContentError) || isNotXtream(error) {
                // The API is not reachable for this account; the list itself may still load
                playlists.addM3U(name: title, url: address)
                if showsCancel { dismiss() }
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    private func isNotXtream(_ error: Error) -> Bool {
        if case ContentError.notXtream = error { return true }
        return false
    }
}
