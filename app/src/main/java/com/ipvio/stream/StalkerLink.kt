package com.ipvio.stream

import java.net.URLEncoder

/**
 * Asking a Stalker portal for a play address ("create_link") and reading its answer. Without Android, testable.
 *
 * Portals differ here, mostly for movies and series:
 * - Some reject the parameters a MAG box sends ("forced_storage=undefined"), others need them. So for movies
 *   several request forms are tried in turn ([requests]).
 * - The address comes back in "cmd" ("ffmpeg http://…"), in "url", as a relative path, or only as a file id plus a
 *   play token that the app turns into ".../play/movie.php?..." itself ([address]).
 */
object StalkerLink {
    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    private fun api(endpoint: String, type: String, extra: String) =
        "$endpoint?type=$type&action=create_link$extra&JsHttpRequest=1-xml"

    /**
     * create_link requests to try in this order. Channels ("itv") keep the single MAG form, so zapping stays fast.
     * [series] = episode number if the command belongs to a whole season.
     */
    fun requests(endpoint: String, type: String, cmd: String, series: String? = null): List<String> {
        val c = enc(cmd.trim())
        val s = series?.let { enc(it) } ?: ""
        val withSeries = if (series != null) "&series=$s" else ""
        val out = LinkedHashSet<String>()
        // 1. As a MAG box sends it
        out.add(api(endpoint, type, "&cmd=$c&series=$s&forced_storage=undefined&disable_ad=0&download=0"))
        if (type != "vod") return out.toList()
        // 2. Empty storage instead of "undefined" (Ministra video club)
        out.add(api(endpoint, type, "&cmd=$c&series=$s&forced_storage=&disable_ad=0&download=0&force_ch_link_check=0"))
        // 3. Only the command (many Xtream-based portals)
        out.add(api(endpoint, type, "&cmd=$c$withSeries"))
        // 4. A bare file id: the form the video club uses itself
        val id = cmd.trim()
        if (id.isNotEmpty() && id.all(Char::isDigit)) out.add(api(endpoint, type, "&cmd=" + enc("/media/file_$id.mpg") + withSeries))
        return out.toList()
    }

    /** "ffmpeg http://…" / "auto http://…" → the address; null if there is no http(s) address. */
    fun strip(cmd: String?): String? {
        val c = cmd?.trim() ?: return null
        val i = c.indexOf("http://").let { if (it >= 0) it else c.indexOf("https://") }
        if (i < 0) return null
        return c.substring(i).trim().substringBefore(' ').takeIf { it.length > 8 }
    }

    /** "http://host:port" of the portal. */
    fun origin(portal: String): String? = Regex("""^(https?://[^/?#]+)""", RegexOption.IGNORE_CASE).find(portal.trim())?.value

    /** The portal installation: [endpoint] without "/server/load.php" or "/portal.php" ("http://host/stalker_portal"). */
    fun installation(endpoint: String): String? {
        val m = Regex("""^(https?://[^/?#]+)([^?#]*)""", RegexOption.IGNORE_CASE).find(endpoint.trim()) ?: return null
        val path = m.groupValues[2].replace(Regex("""/(?:server/load\.php|[^/]*\.php)$""", RegexOption.IGNORE_CASE), "").trimEnd('/')
        return m.groupValues[1] + path
    }

    /**
     * Play address from the "js" part of a create_link answer ([f] = its fields; a bare string counts as "cmd").
     * [endpoint] = the portal API that answered, [sent] = the command that was asked for. null = nothing playable.
     */
    fun address(endpoint: String, mac: String, f: Map<String, String>, type: String, sent: String = ""): String? {
        val base = installation(endpoint)
        for (k in listOf("url", "cmd")) {
            val v = f[k]?.trim()?.takeIf { it.isNotEmpty() && it != "null" } ?: continue
            strip(v)?.let { return it }
            // Path without a server ("/media/…", "/play/movie.php?…"): served by the portal installation.
            // Not when the portal only echoes the command it was sent (that means: no address).
            val p = v.substringAfterLast(' ')
            if (base != null && p.startsWith("/") && p != sent.trim().substringAfterLast(' ')) return base + p
        }
        // Only file id + play token: build the address of the portal's movie player
        val host = origin(endpoint)
        if (type == "vod" && host != null) {
            val token = f["play_token"]?.trim().orEmpty()
            var id = f["id"]?.trim().orEmpty()
            if (token.isNotEmpty() && id.isNotEmpty() && id != "null" && id != "0") {
                if (!id.contains('.')) id += ".mp4"
                return "$host/play/movie.php?mac=${enc(mac)}&stream=${enc(id)}&play_token=${enc(token)}&type=movie"
            }
        }
        return null
    }

    /**
     * Portal answer made safe to show on screen: MAC, token, server addresses, account names/passwords and
     * other secrets in addresses are replaced. Only the shape stays (which fields, which kind of path).
     */
    fun mask(text: String, mac: String, token: String): String {
        var t = text
        if (mac.isNotEmpty()) {
            t = t.replace(mac, "MAC", ignoreCase = true).replace(enc(mac), "MAC", ignoreCase = true)
        }
        if (token.length >= 4) t = t.replace(token, "TOKEN")
        t = t.replace("\\/", "/")
        t = Regex("""(?i)(https?://)[^/\s"'?]+""").replace(t, "$1SERVER")
        t = Regex("""(?i)/(movie|series|live|timeshift)/[^/\s"]+/[^/\s"]+/""").replace(t, "/$1/USER/PASS/")
        t = Regex("""(?i)\b(play_token|token|password|pass|passwd|username|user|login|mac|sn|key|sig|signature|auth)=([^&\s"']+)""").replace(t, "$1=…")
        t = Regex("""(?i)"(play_token|token|password|username|login|mac)"\s*:\s*"[^"]*"""").replace(t, "\"$1\":\"…\"")
        return t
    }

    private val MEDIA_ID = Regex("""^(?:\S+\s+)?/media/(\d+)\.mpg$""")

    /** Movie ID of a video club command "/media/<id>.mpg" (not "/media/file_<id>.mpg"); null otherwise. */
    fun movieIdOf(cmd: String): String? = MEDIA_ID.find(cmd.trim())?.groupValues?.get(1)

    /**
     * Play command of a movie's first file from the answer to get_ordered_list with movie_id ([items], [total] = total_items).
     * Prefers an entry that already carries "/media/file_…". An entry's bare ID only counts if the answer is a short file
     * list – a portal that ignores movie_id returns a whole category, and its first movie must not be played instead.
     */
    fun fileCmd(items: List<Map<String, String>>, total: Int): String? {
        for (f in items) {
            val c = f["cmd"]?.trim().orEmpty()
            val i = c.indexOf("/media/file_")
            if (i >= 0) return c.substring(i).substringBefore(' ')
        }
        if (items.isEmpty() || total > 20 || items.size > 20) return null
        val id = items[0]["id"]?.trim()?.takeIf { it.isNotEmpty() && it != "null" && it != "0" } ?: return null
        return "/media/file_$id.mpg"
    }

    /**
     * What to ask the portal for one item. [cmd] = command for create_link first (null = go straight to the file),
     * [lookup] = get_ordered_list parameters that list the item's own files ([lookupType] "vod"/"series"), null = none.
     */
    class Play(val linkType: String, val cmd: String?, val series: String?, val lookupType: String, val lookup: String?) {
        companion object {
            private const val SEP = '\u0002'
            private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

            /** Stored command of a single episode: its own command plus list type, series, season and episode ID. */
            fun episode(cmd: String, listType: String, movieId: String, seasonId: String, episodeId: String): String =
                listOf(cmd, listType, movieId, seasonId, episodeId).joinToString(SEP.toString())

            fun of(type: String, cmd: String, series: String?): Play = when (type) {
                "mfile" -> Play("vod", null, null, "vod", "&movie_id=${enc(cmd)}")
                "efile" -> {
                    val p = cmd.split(SEP)
                    if (p.size != 5) Play("vod", p[0], series, "vod", null)
                    else Play("vod", p[0].ifBlank { null }, series, p[1],
                        "&movie_id=${enc(p[2])}&season_id=${enc(p[3])}&episode_id=${enc(p[4])}")
                }
                "vod" -> Play("vod", cmd, series, "vod", if (series == null) movieIdOf(cmd)?.let { "&movie_id=$it" } else null)
                else -> Play(type, cmd, series, type, null)
            }
        }
    }
}
