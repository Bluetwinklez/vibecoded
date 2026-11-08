package com.ipvio.stream

import java.net.URLEncoder
import java.security.MessageDigest

/**
 * Stalker-/Ministra-Portale (Portal-Adresse + MAC-Adresse), Runde 20, erweitert in Runde 22 (Serien, robustere Anmeldung).
 * Without Android, testable.
 *
 * A login is stored as "stalker:" + portal address + "#mac=" + MAC (encrypted like all logins).
 * The app builds a list in M3U format from it. Because portals hand out the play addresses only on request and often
 * valid only briefly, the list contains an own address per channel/movie "stalker://SOURCE/live|movie/CMD";
 * the player fetches the real address at start ([StalkerApi.resolve]).
 *
 * Series appear with a placeholder in the list ("stalker://SOURCE/series/DETAILS.ser", name "… S01E01"). Their seasons
 * and episodes are fetched by [LazySeries] only when the series is opened ([StalkerApi.episodeList]), just like with Xtream.
 */
object StalkerLogic {
    data class Source(val portal: String, val mac: String) {
        /** Key of the source in the play addresses (hash of the stored details, without the details themselves). */
        val key: Int get() = encode().trim().hashCode()
        fun encode(): String = "stalker:" + portal + "#mac=" + mac
    }

    private val MAC = Regex("""^([0-9A-F]{2}[:-]){5}[0-9A-F]{2}$""")

    /** MAC in the usual form "00:1A:79:AB:CD:EF" or null if invalid. */
    fun normMac(raw: String): String? {
        val t = raw.trim().uppercase().replace('-', ':')
        if (MAC.matches(t)) return t
        val hex = t.filter { it.isDigit() || it in 'A'..'F' }
        return if (hex.length == 12 && t.all { it.isDigit() || it in 'A'..'F' || it == ':' || it == ' ' }) hex.chunked(2).joinToString(":") else null
    }

    /** Login from the inputs; null = portal address or MAC invalid. */
    fun source(portalRaw: String, macRaw: String): Source? {
        var p = portalRaw.trim()
        if (p.isEmpty()) return null
        if (!p.startsWith("http://", true) && !p.startsWith("https://", true)) p = "http://$p"
        if (PlaylistLogic.normalizeUrl(p) == null) return null
        val m = normMac(macRaw) ?: return null
        return Source(p, m)
    }

    fun isSource(url: String): Boolean = url.trim().startsWith("stalker:", true) && !url.trim().startsWith("stalker://", true)

    fun parse(url: String): Source? {
        val u = url.trim()
        if (!isSource(u)) return null
        val body = u.substring("stalker:".length)
        val i = body.lastIndexOf("#mac=")
        if (i <= 0) return null
        return source(body.substring(0, i), body.substring(i + 5))
    }

    private val C_TAIL = Regex("""/c(/[^/]*)?$""", RegexOption.IGNORE_CASE)

    /** Possible API addresses of a portal, to be tried in this order. */
    fun endpoints(portal: String): List<String> {
        val p = portal.trim().trimEnd('/')
        // "…/c" and "…/c/index.html" are the box's web page, the API lies next to it
        val base = C_TAIL.replace(p, "").trimEnd('/')
        val out = LinkedHashSet<String>()
        if (p.endsWith(".php", true)) { out.add(p); return out.toList() }
        if (base.endsWith("/stalker_portal", true)) out.add("$base/server/load.php")
        out.add("$base/portal.php")
        out.add("$base/server/load.php")
        out.add("$base/stalker_portal/server/load.php")
        out.add("$base/c/portal.php")
        return out.toList()
    }

    /** Address of the logos (portals often give only the file name). */
    fun logoUrl(portal: String, logo: String?): String? {
        val l = logo?.trim()?.takeIf { it.isNotEmpty() && it != "null" } ?: return null
        if (l.startsWith("http://") || l.startsWith("https://")) return l
        val p = portal.trim().trimEnd('/')
        val base = C_TAIL.replace(p, "").trimEnd('/')
        return if (l.startsWith("/")) Regex("""^(https?://[^/]+)""").find(base)?.value?.plus(l) else "$base/misc/logos/320/$l"
    }

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    fun api(endpoint: String, type: String, action: String, extra: String = ""): String =
        "$endpoint?type=$type&action=$action$extra&JsHttpRequest=1-xml"

    /** Request a play address. [series] = episode number if the command belongs to a whole season. */
    fun createLink(endpoint: String, type: String, cmd: String, series: String? = null): String =
        api(endpoint, type, "create_link", "&cmd=" + enc(cmd) + "&series=" + (series?.let { enc(it) } ?: "") + "&forced_storage=undefined&disable_ad=0&download=0")

    /** „ffmpeg http://…“ / „ffrt http://…“ / „auto http://…“ → reine Adresse. */
    fun stripCmd(cmd: String?): String? {
        val c = cmd?.trim() ?: return null
        val i = c.indexOf("http")
        val u = if (i >= 0) c.substring(i).trim() else return null
        return u.substringBefore(' ').takeIf { it.startsWith("http://") || it.startsWith("https://") }
    }

    /**
     * Cookie like on a MAG box: the MAC unchanged with colons (the device sends it that way too). Some portals
     * do not read the cookie URL-decoded and do not recognize an encoded MAC ("00%3A1A…").
     */
    fun cookie(mac: String, tz: String = "Europe/Berlin"): String = "mac=$mac; stb_lang=en; timezone=$tz"

    const val UA = "Mozilla/5.0 (QtEmbedded; U; Linux; C) AppleWebKit/533.3 (KHTML, like Gecko) MAG200 stbapp ver: 2 rev: 250 Safari/533.3"
    const val X_UA = "Model: MAG250; Link: WiFi"

    private fun hash(alg: String, s: String) = MessageDigest.getInstance(alg).digest(s.toByteArray()).joinToString("") { "%02X".format(it) }

    /** Device identifiers some portals expect when fetching the profile (derived from the MAC, always the same). */
    fun profileExtra(mac: String): String {
        val sn = hash("MD5", mac).take(13)
        val dev = hash("SHA-256", mac)
        return "&hd=1&stb_type=MAG250&client_type=STB&image_version=218&sn=$sn&device_id=$dev&device_id2=$dev&auth_second_step=1&not_valid_token=0"
    }

    // ------------------------------------------------------------------ Play addresses in the list

    /** Separator in the stored details (never occurs in portal data). */
    private const val SEP = "\u0001"

    private fun hex(s: String): String = s.toByteArray(Charsets.UTF_8).joinToString("") { "%02x".format(it) }
    private fun unhex(h: String): String? {
        if (h.length % 2 != 0) return null
        val b = ByteArray(h.length / 2)
        for (i in b.indices) b[i] = (h.substring(i * 2, i * 2 + 2).toIntOrNull(16) ?: return null).toByte()
        return String(b, Charsets.UTF_8)
    }

    /**
     * "stalker://KEY/live/HEX.ts" or "…/movie/HEX.mp4" – the extension helps with classification (live/movie).
     * [series] = episode number (episodes of a season share the season's command).
     */
    fun itemUrl(key: Int, kind: String, cmd: String, series: String? = null): String =
        "stalker://$key/$kind/" + hex(if (series != null) cmd + SEP + series else cmd) + (if (kind == "movie") ".mp4" else ".ts")

    class ItemRef(val key: Int, val type: String, val cmd: String, val series: String? = null)

    fun itemRef(url: String): ItemRef? {
        if (!url.startsWith("stalker://")) return null
        val rest = url.removePrefix("stalker://").split('/')
        if (rest.size != 3) return null
        val key = rest[0].toIntOrNull() ?: return null
        val type = when (rest[1]) { "live" -> "itv"; "movie" -> "vod"; else -> return null }
        val raw = unhex(rest[2].substringBefore('.')) ?: return null
        val p = raw.split(SEP, limit = 2)
        return ItemRef(key, type, p[0], p.getOrNull(1))
    }

    fun isItem(url: String): Boolean = url.startsWith("stalker://") && !url.contains("/series/")

    // ------------------------------------------------------------------ Series (placeholder, episodes only on opening)

    /** A series of the portal: [id], [cat] (category), [mode] "s" = own series area, "v" = series in the movie area. */
    class SeriesRef(val key: Int, val id: String, val cat: String, val mode: String)

    fun seriesUrl(key: Int, id: String, cat: String, mode: String): String =
        "stalker://$key/series/" + hex(listOf(id, cat, mode).joinToString(SEP)) + ".ser"

    fun seriesRef(url: String): SeriesRef? {
        if (!url.startsWith("stalker://")) return null
        val rest = url.removePrefix("stalker://").split('/')
        if (rest.size != 3 || rest[1] != "series") return null
        val key = rest[0].toIntOrNull() ?: return null
        val p = unhex(rest[2].substringBefore('.'))?.split(SEP) ?: return null
        if (p.size != 3 || p[0].isEmpty()) return null
        return SeriesRef(key, p[0], p[1], p[2])
    }

    /** Placeholder addresses of a series (one per source with several playlists, label = name of the source). Empty = real episodes. */
    fun lazyUrls(i: Item): List<Pair<String, String>> {
        if (i.kind != Kind.SERIES || i.episodes.size != 1) return emptyList()
        val e = i.episodes[0]
        val vs = e.variants.ifEmpty { listOf(Variant(e.url, "", e.quality, null)) }
        if (vs.any { seriesRef(it.url) == null }) return emptyList()
        return vs.map { it.url to it.label }
    }

    fun isLazy(i: Item): Boolean = lazyUrls(i).isNotEmpty()

    private val SEASON_NAME = Regex("""(?i)(season|staffel|sezon|saison|temporada|stagione|sezona|s)\s*\.?\s*0*(\d{1,3})\b""")
    private val EPISODE_NAME = Regex("""(?i)(episode|folge|ep|e|bölüm|épisode|episodio|epizoda|aflevering)\s*\.?\s*0*(\d{1,4})\b""")
    private val EPISODE_AFTER = Regex("""(?i)\b0*(\d{1,4})\s*\.?\s*(episode|folge|bölüm|épisode|episodio|epizoda|aflevering)""")

    /** Season number: from fields of the portal, otherwise from the name ("Staffel 2", "Season 2", "S02"), otherwise [fallback]. */
    fun seasonNumber(f: Map<String, String>, fallback: Int): Int {
        for (k in listOf("season_number", "season_num", "season")) f[k]?.trim()?.toIntOrNull()?.takeIf { it in 0..999 }?.let { return it }
        val m = SEASON_NAME.find(f["name"] ?: f["title"] ?: "")
        return m?.groupValues?.get(2)?.toIntOrNull()?.takeIf { it in 0..999 } ?: fallback
    }

    /** Episode number: from fields of the portal, otherwise from the name ("Episode 5", "E05", "5. Folge"), otherwise [fallback]. */
    fun episodeNumber(f: Map<String, String>, fallback: Int): Int {
        for (k in listOf("series_number", "episode_number", "episode_num", "episode")) f[k]?.trim()?.toIntOrNull()?.takeIf { it in 1..9999 }?.let { return it }
        val n = f["name"] ?: f["title"] ?: ""
        EPISODE_NAME.find(n)?.groupValues?.get(2)?.toIntOrNull()?.takeIf { it in 1..9999 }?.let { return it }
        EPISODE_AFTER.find(n)?.groupValues?.get(1)?.toIntOrNull()?.takeIf { it in 1..9999 }?.let { return it }
        return fallback
    }

    // ------------------------------------------------------------------ Entries of the list

    private fun attr(s: String?) = (s ?: "").replace('"', '\'').replace('\n', ' ').trim()
    private fun name(s: String?) = (s ?: "").replace(',', '‚').replace('\n', ' ').trim()

    /** Ein Sender als zwei M3U-Zeilen. */
    fun liveEntry(src: Source, f: Map<String, String>, genres: Map<String, String>): String? {
        val cmd = f["cmd"]?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val n = name(f["name"]).ifEmpty { return null }
        val sb = StringBuilder("#EXTINF:-1")
        attr(f["xmltv_id"]).takeIf { it.isNotEmpty() }?.let { sb.append(" tvg-id=\"").append(it).append('"') }
        logoUrl(src.portal, f["logo"])?.let { sb.append(" tvg-logo=\"").append(attr(it)).append('"') }
        sb.append(" group-title=\"").append(attr(f["tv_genre_id"]?.let { genres[it] } ?: "Sonstige")).append('"')
        return sb.append(',').append(n).append('\n').append(itemUrl(src.key, "live", cmd)).toString()
    }

    /** Ein Film als zwei M3U-Zeilen. */
    fun movieEntry(src: Source, f: Map<String, String>, category: String): String? {
        val cmd = f["cmd"]?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        var n = name(f["name"]).ifEmpty { return null }
        val y = f["year"]?.trim()?.takeIf { it.length == 4 && it.all(Char::isDigit) }
        if (y != null && !n.contains("($y)")) n = "$n ($y)"
        val sb = StringBuilder("#EXTINF:-1")
        attr(f["screenshot_uri"]).takeIf { it.startsWith("http") }?.let { sb.append(" tvg-logo=\"").append(it).append('"') }
        sb.append(" group-title=\"").append(attr(category.ifBlank { "Filme" })).append('"')
        return sb.append(',').append(n).append('\n').append(itemUrl(src.key, "movie", cmd)).toString()
    }

    /** A series as a placeholder (two M3U lines); the name ends in "S01E01" so parsing recognizes it as a series. */
    fun seriesEntry(src: Source, f: Map<String, String>, catId: String, catName: String, mode: String): String? {
        val id = (f["id"] ?: f["series_id"])?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val n = name(f["name"] ?: f["title"]).ifEmpty { return null }
        val sb = StringBuilder("#EXTINF:-1")
        listOf("screenshot_uri", "cover_big", "cover").firstNotNullOfOrNull { k -> attr(f[k]).takeIf { it.startsWith("http") } }
            ?.let { sb.append(" tvg-logo=\"").append(it).append('"') }
        sb.append(" group-title=\"").append(attr(catName.ifBlank { "Serien" })).append('"')
        return sb.append(',').append(n).append(" S01E01").append('\n').append(seriesUrl(src.key, id, catId, mode)).toString()
    }
}
