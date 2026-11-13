import Foundation

/// UI texts. The English text is the key; Turkish and German are looked up here, everything else falls back to English.
/// Kept in code (not .strings files) so a missing translation can never show a raw key.
func L(_ key: String) -> String {
    guard let table = L10n.table else { return key }
    return table[key] ?? key
}

func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

enum L10n {
    static let table: [String: String]? = {
        let code = Locale.preferredLanguages.first?.prefix(2).lowercased() ?? "en"
        switch code {
        case "tr": return tr
        case "de": return de
        default: return nil
        }
    }()

    static let tr: [String: String] = [
        "Live TV": "Canlı TV",
        "Movies": "Filmler",
        "Series": "Diziler",
        "My list": "Listem",
        "Settings": "Ayarlar",
        "Search": "Ara",
        "All": "Tümü",
        "Categories": "Kategoriler",
        "Loading…": "Yükleniyor…",
        "Try again": "Tekrar dene",
        "Nothing here yet.": "Henüz bir şey yok.",
        "No results.": "Sonuç yok.",
        "Add playlist": "Playlist ekle",
        "Add": "Ekle",
        "Cancel": "İptal",
        "OK": "Tamam",
        "Name (optional)": "Ad (isteğe bağlı)",
        "Server (e.g. http://server.tld:8080)": "Sunucu (ör. http://server.tld:8080)",
        "Username": "Kullanıcı adı",
        "Password": "Parola",
        "M3U link": "M3U bağlantısı",
        "Xtream login": "Xtream girişi",
        "Vibe Stream is only a player. It contains no channels, movies or playlists. Use only sources you are allowed to use.":
            "Vibe Stream yalnızca bir oynatıcıdır. Kanal, film veya playlist içermez. Yalnızca kullanma hakkın olan kaynakları kullan.",
        "Please enter a valid server address.": "Lütfen geçerli bir sunucu adresi gir.",
        "Please enter username and password.": "Lütfen kullanıcı adı ve parolayı gir.",
        "Please enter a link that starts with http:// or https://.": "Lütfen http:// veya https:// ile başlayan bir bağlantı gir.",
        "The provider refused the login.": "Sağlayıcı girişi reddetti.",
        "The server did not answer like an Xtream server.": "Sunucu bir Xtream sunucusu gibi yanıt vermedi.",
        "Server error %d.": "Sunucu hatası %d.",
        "The login data for this playlist is missing. Remove the playlist and add it again.":
            "Bu playlistin giriş bilgileri eksik. Playlisti kaldırıp yeniden ekle.",
        "The link does not contain a playlist.": "Bağlantı bir playlist içermiyor.",
        "Invalid address.": "Geçersiz adres.",
        "Checking login…": "Giriş denetleniyor…",
        "Playlists": "Playlistler",
        "Reload playlist": "Playlisti yeniden yükle",
        "Account": "Hesap",
        "Status": "Durum",
        "Expires": "Bitiş",
        "Connections": "Bağlantılar",
        "Unlimited": "Sınırsız",
        "Clear watch history": "İzleme geçmişini temizle",
        "About": "Hakkında",
        "Version": "Sürüm",
        "Vibe Stream is a fork of IPVIO Stream by Emrodev. Free software under the GNU General Public License v3.":
            "Vibe Stream, Emrodev’in IPVIO Stream projesinin bir çatalıdır. GNU Genel Kamu Lisansı v3 kapsamında özgür yazılım.",
        "Continue watching": "İzlemeye devam et",
        "Favorites": "Favoriler",
        "Add to favorites": "Favorilere ekle",
        "Remove from favorites": "Favorilerden kaldır",
        "TV guide": "Yayın akışı",
        "No guide data for this channel.": "Bu kanal için yayın akışı yok.",
        "Now": "Şimdi",
        "Season %d": "%d. Sezon",
        "Episode %d": "%d. Bölüm",
        "No episodes found.": "Bölüm bulunamadı.",
        "Playback failed": "Oynatma başarısız",
        "The stream could not be played. The provider may be offline, the connection limit may be reached, or the format is not supported by iOS.":
            "Yayın oynatılamadı. Sağlayıcı çevrimdışı olabilir, bağlantı sınırına ulaşılmış olabilir veya biçim iOS tarafından desteklenmiyor olabilir.",
        "Open in VLC": "VLC’de aç",
        "Try anyway": "Yine de dene",
        "Format not supported": "Biçim desteklenmiyor",
        "The built-in iOS player cannot open %@ files. The free VLC app can.":
            "Yerleşik iOS oynatıcısı %@ dosyalarını açamaz. Ücretsiz VLC uygulaması açabilir.",
        "Delete": "Sil",
        "Play": "Oynat",
        "Resume": "Devam et",
        "Type at least 2 characters.": "En az 2 karakter yaz."
    ]

    static let de: [String: String] = [
        "Live TV": "Live TV",
        "Movies": "Filme",
        "Series": "Serien",
        "My list": "Meine Liste",
        "Settings": "Einstellungen",
        "Search": "Suche",
        "All": "Alle",
        "Categories": "Kategorien",
        "Loading…": "Lädt …",
        "Try again": "Erneut versuchen",
        "Nothing here yet.": "Noch nichts vorhanden.",
        "No results.": "Keine Treffer.",
        "Add playlist": "Playlist hinzufügen",
        "Add": "Hinzufügen",
        "Cancel": "Abbrechen",
        "OK": "OK",
        "Name (optional)": "Name (optional)",
        "Server (e.g. http://server.tld:8080)": "Server (z. B. http://server.tld:8080)",
        "Username": "Benutzername",
        "Password": "Passwort",
        "M3U link": "M3U-Link",
        "Xtream login": "Xtream-Login",
        "Vibe Stream is only a player. It contains no channels, movies or playlists. Use only sources you are allowed to use.":
            "Vibe Stream ist nur ein Abspielgerät. Die App liefert keine Sender, Filme oder Playlists. Nutze nur Quellen, für die du eine Berechtigung hast.",
        "Please enter a valid server address.": "Bitte eine gültige Server-Adresse eingeben.",
        "Please enter username and password.": "Bitte Benutzername und Passwort eingeben.",
        "Please enter a link that starts with http:// or https://.": "Bitte einen Link eingeben, der mit http:// oder https:// beginnt.",
        "The provider refused the login.": "Der Anbieter hat die Anmeldung abgelehnt.",
        "The server did not answer like an Xtream server.": "Der Server hat nicht wie ein Xtream-Server geantwortet.",
        "Server error %d.": "Serverfehler %d.",
        "The login data for this playlist is missing. Remove the playlist and add it again.":
            "Die Zugangsdaten dieser Playlist fehlen. Entferne die Playlist und füge sie neu hinzu.",
        "The link does not contain a playlist.": "Der Link enthält keine Playlist.",
        "Invalid address.": "Ungültige Adresse.",
        "Checking login…": "Anmeldung wird geprüft …",
        "Playlists": "Playlists",
        "Reload playlist": "Playlist neu laden",
        "Account": "Konto",
        "Status": "Status",
        "Expires": "Läuft ab",
        "Connections": "Verbindungen",
        "Unlimited": "Unbegrenzt",
        "Clear watch history": "Verlauf löschen",
        "About": "Über",
        "Version": "Version",
        "Vibe Stream is a fork of IPVIO Stream by Emrodev. Free software under the GNU General Public License v3.":
            "Vibe Stream ist ein Fork von IPVIO Stream von Emrodev. Freie Software unter der GNU General Public License v3.",
        "Continue watching": "Weiterschauen",
        "Favorites": "Favoriten",
        "Add to favorites": "Zu Favoriten hinzufügen",
        "Remove from favorites": "Aus Favoriten entfernen",
        "TV guide": "TV-Programm",
        "No guide data for this channel.": "Keine Programmdaten für diesen Sender.",
        "Now": "Jetzt",
        "Season %d": "Staffel %d",
        "Episode %d": "Folge %d",
        "No episodes found.": "Keine Folgen gefunden.",
        "Playback failed": "Wiedergabe fehlgeschlagen",
        "The stream could not be played. The provider may be offline, the connection limit may be reached, or the format is not supported by iOS.":
            "Der Stream konnte nicht abgespielt werden. Der Anbieter ist vielleicht nicht erreichbar, das Verbindungslimit ist erreicht oder iOS unterstützt das Format nicht.",
        "Open in VLC": "In VLC öffnen",
        "Try anyway": "Trotzdem versuchen",
        "Format not supported": "Format nicht unterstützt",
        "The built-in iOS player cannot open %@ files. The free VLC app can.":
            "Der eingebaute iOS-Player kann %@-Dateien nicht öffnen. Die kostenlose VLC-App kann es.",
        "Delete": "Löschen",
        "Play": "Abspielen",
        "Resume": "Fortsetzen",
        "Type at least 2 characters.": "Mindestens 2 Zeichen eingeben."
    ]
}
