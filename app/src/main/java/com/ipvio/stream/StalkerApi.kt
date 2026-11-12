package com.ipvio.stream

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONArray
import org.json.JSONObject
import java.io.Writer
import java.net.URLEncoder
import java.util.concurrent.TimeUnit

/**
 * Connection to a Stalker/Ministra portal (see [StalkerLogic]): login with the MAC address, channels, movies and
 * series as a list, play address at start. Series appear as placeholders in the list; [episodeList] fetches their episodes
 * only when a series is opened.
 */
object StalkerApi {
    private val client: OkHttpClient = Net.base.newBuilder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(60, TimeUnit.SECONDS).addInterceptor(TlsFallback.interceptor()).build()

    /** Logged-in session: API and token, reused for a few minutes. */
    private class Session(val src: StalkerLogic.Source, val endpoint: String, val token: String, val at: Long)
    private val sessions = HashMap<Int, Session>()
    private const val SESSION_MS = 10 * 60_000L
    private const val MAX_CHANNELS = 30000
    /** Pages per step when a category is opened or scrolled further (~14 titles per page), see [loadChunk]. */
    private const val LOAD_CHUNK = 4
    /** Short pause between two pages so the portal does not block (one request per category while loading). */
    private const val PAGE_PAUSE_MS = 120L
    /** This many categories in a row without an answer: wait [COOLDOWN_MS], at most [MAX_COOLDOWNS] times. */
    private const val GIVE_UP_AFTER = 3
    private const val MAX_COOLDOWNS = 2
    private const val COOLDOWN_MS = 30_000L

    /** Last response of the portal in short form (only code and kind, never address or MAC) for understandable error texts. */
    @Volatile private var note = ""

    private fun enc(s: String) = URLEncoder.encode(s, "UTF-8")

    private fun req(src: StalkerLogic.Source, url: String, token: String?): Request {
        val b = Request.Builder().url(url)
            .header("User-Agent", StalkerLogic.UA)
            .header("X-User-Agent", StalkerLogic.X_UA)
            .header("Accept", "*/*")
            .header("Referer", src.portal)
            .header("Cookie", StalkerLogic.cookie(src.mac))
        if (token != null) b.header("Authorization", "Bearer $token")
        return b.build()
    }

    /** JSON from a response; portals sometimes send a BOM or text before the JSON. */
    private fun jsonOf(body: String): JSONObject? {
        val i = body.indexOf('{')
        if (i < 0) return null
        return runCatching { JSONObject(body.substring(i)) }.getOrNull()
    }

    /** Response as the "js" part, null on error (the reason is then in [note]). */
    private fun js(src: StalkerLogic.Source, url: String, token: String?): Any? = try {
        client.newCall(req(src, url, token)).execute().use { r ->
            val body = r.body?.string().orEmpty()
            if (!r.isSuccessful) { note = "HTTP ${r.code}"; null }
            else {
                val o = jsonOf(body)
                if (o == null) { note = "keine gültige Antwort"; null } else { note = ""; o.opt("js") }
            }
        }
    } catch (e: Exception) {
        note = "keine Verbindung"
        null
    }

    /** Log in: find the API, get the token, fetch the profile (some portals only unlock with it). */
    private fun login(src: StalkerLogic.Source, force: Boolean = false): Session {
        synchronized(sessions) {
            val s = sessions[src.key]
            if (!force && s != null && System.currentTimeMillis() - s.at < SESSION_MS) return s
        }
        var seen = ""
        for (ep in StalkerLogic.endpoints(src.portal)) {
            // First with, then without "prehash" (old portals do not know it)
            var hs: JSONObject? = null
            for (extra in listOf("&token=&prehash=0", "&token=")) {
                hs = js(src, StalkerLogic.api(ep, "stb", "handshake", extra), null) as? JSONObject
                if (hs?.optString("token").isNullOrBlank()) hs = null else break
                if (note.isNotEmpty()) seen = note
            }
            val token = hs?.optString("token")?.takeIf { it.isNotBlank() } ?: continue
            js(src, StalkerLogic.api(ep, "stb", "get_profile", StalkerLogic.profileExtra(src)), token)
            val s = Session(src, ep, token, System.currentTimeMillis())
            synchronized(sessions) { sessions[src.key] = s }
            return s
        }
        throw PlaylistError(
            if (seen.isNotEmpty()) "Das Portal antwortet nicht richtig ($seen). Adresse und MAC-Adresse prüfen."
            else "Das Portal hat die Anmeldung abgelehnt. Adresse und MAC-Adresse prüfen."
        )
    }

    private fun categories(s: Session, type: String, action: String): Map<String, String> {
        val out = LinkedHashMap<String, String>()
        val a = js(s.src, StalkerLogic.api(s.endpoint, type, action), s.token) as? JSONArray ?: return out
        for (i in 0 until a.length()) {
            val o = a.optJSONObject(i) ?: continue
            val id = o.opt("id")?.toString().orEmpty()
            val t = o.optString("title").ifBlank { o.optString("name") }
            if (id.isNotEmpty() && t.isNotBlank()) out[id] = t.trim()
        }
        return out
    }

    private fun fields(o: JSONObject): Map<String, String> {
        val f = HashMap<String, String>()
        for (k in o.keys()) { val v = o.opt(k); if (v is String || v is Number) f[k] = v.toString() }
        return f
    }

    /**
     * Fetch all pages of a list ([extra] = parameters), [each] per entry. Stops at [maxItems], an empty page or
     * a repeating page. true = at least one page arrived.
     */
    private fun paged(s: Session, type: String, extra: String, maxItems: Int, check: () -> Unit, each: (JSONObject) -> Unit): Boolean {
        var page = 1
        var pages = 1
        var got = 0
        var ok = false
        var lastFirst: String? = null
        while (page <= pages && got < maxItems) {
            check()
            val o = js(s.src, StalkerLogic.api(s.endpoint, type, "get_ordered_list", "$extra&p=$page"), s.token) as? JSONObject ?: break
            ok = true
            val a = o.optJSONArray("data") ?: break
            if (a.length() == 0) break
            val first = a.optJSONObject(0)?.let { it.opt("id")?.toString() ?: it.opt("name")?.toString() }
            if (first != null && first == lastFirst) break
            lastFirst = first
            val total = o.optInt("total_items", 0)
            val per = o.optInt("max_page_items", 14).coerceAtLeast(1)
            // Without a total count just keep paging until a page is empty
            pages = if (total > 0) ((total + per - 1) / per).coerceIn(1, 800) else (page + 1).coerceAtMost(800)
            for (i in 0 until a.length()) { a.optJSONObject(i)?.let { each(it); got++ } }
            page++
        }
        return ok
    }

    /**
     * Write the list to [out] (M3U): all channels, plus only the first page (newest titles) of every movie and series
     * category, fast like IPTVnator. Categories with more titles go to [onCats]; their further pages come when the
     * category is opened or scrolled ([loadChunk], [StalkerMore]). [onPhase] = progress, [check] throws on abort.
     * Return value: number of entries.
     */
    fun write(
        src: StalkerLogic.Source, out: Writer, onPhase: (String) -> Unit, check: () -> Unit,
        onCats: (List<StalkerLogic.CatRef>) -> Unit = {}
    ): Int {
        onPhase("Zugang wird geprüft …")
        val s = login(src, force = true)
        var n = 0
        out.write("#EXTM3U\n")

        // ---- Channels
        onPhase("Sender werden geladen …")
        val genres = categories(s, "itv", "get_genres")
        var live = 0
        val all = js(src, StalkerLogic.api(s.endpoint, "itv", "get_all_channels"), s.token)
        val data = (all as? JSONObject)?.optJSONArray("data") ?: (all as? JSONArray)
        if (data != null) for (i in 0 until data.length()) {
            val o = data.optJSONObject(i) ?: continue
            StalkerLogic.liveEntry(src, fields(o), genres)?.let { out.write(it); out.write("\n"); n++; live++ }
            if (i % 1000 == 0) check()
        }
        if (live == 0) {
            // Fallback: many portals block "all channels at once" and deliver only page by page
            paged(s, "itv", "&genre=*&force_ch_link_check=&fav=0&sortby=number&hd=0", MAX_CHANNELS, check) { o ->
                StalkerLogic.liveEntry(src, fields(o), genres)?.let { out.write(it); out.write("\n"); n++; live++ }
                if (live % 400 == 0) onPhase("Sender werden geladen ($live) …")
            }
        }

        // ---- Movies and series: only the first page (newest titles) per category, the rest on opening ([loadChunk])
        onPhase("Kategorien werden geladen …")
        val em = Emitter(src) { out.write(it); out.write("\n"); n++ }
        val cats = categories(s, "vod", "get_categories").filterKeys { it != "*" }.map { "vod" to it } +
            categories(s, "series", "get_categories").filterKeys { it != "*" }.map { "series" to it }
        val more = ArrayList<StalkerLogic.CatRef>()
        val skipped = ArrayList<Pair<String, Map.Entry<String, String>>>()
        var failedInRow = 0
        var cooldowns = 0
        fun wait() { var w = 0L; while (w < COOLDOWN_MS) { check(); Thread.sleep(1000); w += 1000 } }
        fun load(type: String, cid: String, cname: String): Paged {
            val r = firstPage(src, type, cid, cname, check, em)
            if (r.more && r.last > 0) more.add(StalkerLogic.CatRef(type, cid, StalkerLogic.groupName(cname), r.total, r.last))
            return r
        }
        for ((idx, c) in cats.withIndex()) {
            val (type, cat) = c
            // Portal stops answering several times in a row: pause briefly, then continue
            if (failedInRow >= GIVE_UP_AFTER && cooldowns < MAX_COOLDOWNS) {
                cooldowns++; failedInRow = 0
                onPhase("Portal antwortet nicht, neuer Versuch in ${COOLDOWN_MS / 1000} s …")
                wait()
            }
            if (failedInRow >= GIVE_UP_AFTER) { skipped.add(c); continue }
            val r = load(type, cat.key, cat.value)
            failedInRow = if (r.ok) 0 else failedInRow + 1
            // Without a single title the category would not appear at all: try again at the end
            if (!r.ok && r.last == 0) skipped.add(c)
            if (idx % 10 == 0) onPhase("Kategorien werden geladen (${idx + 1}/${cats.size}) …")
        }
        if (skipped.isNotEmpty()) {
            onPhase("Kategorien werden erneut versucht …")
            wait()
            var inRow = 0
            for ((type, cat) in skipped) {
                if (inRow >= GIVE_UP_AFTER) break
                inRow = if (load(type, cat.key, cat.value).ok) 0 else inRow + 1
            }
        }
        onCats(more)
        out.flush()
        if (n == 0) {
            val why = if (note.isNotEmpty()) " ($note)" else ""
            throw PlaylistError("Das Portal hat keine Sender geliefert$why. MAC-Adresse und Abo beim Anbieter prüfen.")
        }
        return n
    }

    /** Result of a run over pages: [total] entries according to the portal (-1 = unknown), [last] = last page loaded. */
    private class Paged(val ok: Boolean, val total: Int, val last: Int, val more: Boolean)

    /**
     * Pages [from] .. [from]+[max]-1 of a list to [each]. Stops at an empty or repeating page. [Paged.more] = the portal
     * has further pages; [Paged.ok] false = a page did not come even after logging in again.
     */
    private fun pageRange(
        src: StalkerLogic.Source, type: String, extra: String, from: Int, max: Int, check: () -> Unit, each: (JSONObject) -> Unit
    ): Paged {
        var page = from
        var pages = from
        var total = -1
        var lastFp: String? = null
        while (page <= pages && page < from + max) {
            check()
            var o: JSONObject? = null
            for (attempt in 0 until 2) {
                val s = runCatching { login(src, force = attempt > 0) }.getOrNull() ?: break
                o = js(src, StalkerLogic.api(s.endpoint, type, "get_ordered_list", "$extra&p=$page"), s.token) as? JSONObject
                if (o != null) break
            }
            if (o == null) return Paged(false, total, page - 1, true)
            val a = o.optJSONArray("data") ?: return Paged(true, total, page - 1, false)
            if (a.length() == 0) return Paged(true, total, page - 1, false)
            val fp = a.optJSONObject(0)?.opt("id")?.toString() + "|" + a.optJSONObject(a.length() - 1)?.opt("id")?.toString() + "|" + a.length()
            if (fp == lastFp) return Paged(true, total, page - 1, false)
            lastFp = fp
            total = o.optInt("total_items", -1).takeIf { it > 0 } ?: total
            val per = o.optInt("max_page_items", a.length()).coerceAtLeast(1)
            pages = StalkerLogic.pageCount(total, per, page + 1).coerceAtLeast(page)
            for (i in 0 until a.length()) a.optJSONObject(i)?.let(each)
            page++
            if (page < from + max && page <= pages) Thread.sleep(PAGE_PAUSE_MS)
        }
        return Paged(true, total, page - 1, page <= pages)
    }

    /** Writes movies and series as M3U lines (each movie ID and series name only once). */
    private class Emitter(val src: StalkerLogic.Source, val put: (String) -> Unit) {
        private val movies = HashSet<String>()
        private val series = HashSet<String>()

        fun video(o: JSONObject, type: String, cid: String, cname: String) {
            val f = fields(o)
            if (type == "series" || o.optString("is_series") == "1") {
                val nm = (f["name"] ?: f["title"] ?: "").trim().lowercase()
                if (nm.isNotEmpty() && series.add(nm))
                    StalkerLogic.seriesEntry(src, f, cid, cname, if (type == "series") "s" else "v")?.let(put)
            } else if (movies.add(f["id"] ?: f["cmd"] ?: return)) {
                StalkerLogic.movieEntry(src, f, cname)?.let(put)
            }
        }
    }

    private fun catExtra(cid: String) = "&category=${enc(cid)}&sortby=added"

    /** First page of a category. The portal sends the newest first; the app reads "new" from the end of the list: write oldest first. */
    private fun firstPage(src: StalkerLogic.Source, type: String, cid: String, cname: String, check: () -> Unit, em: Emitter): Paged {
        val rows = ArrayList<JSONObject>()
        val r = pageRange(src, type, catExtra(cid), 1, 1, check) { rows.add(it) }
        for (i in rows.indices.reversed()) em.video(rows[i], type, cid, cname)
        return r
    }

    /** One step loaded on demand: new M3U lines, new state, [done] = no further pages, [ok] false = portal does not answer. */
    class Chunk(val m3u: String, val ref: StalkerLogic.CatRef, val done: Boolean, val ok: Boolean)

    /** The next [LOAD_CHUNK] pages of a category after page [StalkerLogic.CatRef.pages] (on opening or scrolling). */
    fun loadChunk(src: StalkerLogic.Source, ref: StalkerLogic.CatRef, check: () -> Unit): Chunk {
        val sb = StringBuilder()
        val em = Emitter(src) { sb.append(it).append('\n') }
        val rows = ArrayList<JSONObject>()
        val r = pageRange(src, ref.type, catExtra(ref.id), ref.pages + 1, LOAD_CHUNK, check) { rows.add(it) }
        // Oldest first (see [firstPage]); these titles are older than everything loaded so far and go in front
        for (i in rows.indices.reversed()) em.video(rows[i], ref.type, ref.id, ref.name)
        val cur = ref.copy(pages = maxOf(ref.pages, r.last), total = if (r.total > 0) r.total else ref.total)
        return Chunk(sb.toString(), cur, r.ok && !r.more, r.ok)
    }

    /** Play command of a movie with its own files: "/media/file_<file ID>.mpg" of the first file ([StalkerLogic.fileCmdOf]). */
    private fun movieFileCmd(src: StalkerLogic.Source, s: Session, movieId: String): String? {
        val o = js(src, StalkerLogic.api(s.endpoint, "vod", "get_ordered_list", "&movie_id=${enc(movieId)}&p=1"), s.token)
        val a = (o as? JSONObject)?.optJSONArray("data") ?: (o as? JSONArray) ?: return null
        val items = (0 until a.length()).mapNotNull { a.optJSONObject(it)?.let(::fields) }
        val total = (o as? JSONObject)?.optInt("total_items", items.size) ?: items.size
        return StalkerLogic.fileCmdOf(items, total)
    }

    private fun sourceOf(key: Int): StalkerLogic.Source? =
        PlaylistStore.lists.asSequence().mapNotNull { StalkerLogic.parse(it.url) }.firstOrNull { it.key == key }

    /** Real play address for "stalker://…" (freshly generated by the portal). null = not possible. */
    suspend fun resolve(c: Context, url: String): String? = withContext(Dispatchers.IO) {
        val ref = StalkerLogic.itemRef(url) ?: return@withContext null
        val src = sourceOf(ref.key) ?: return@withContext null
        for (attempt in 0 until 2) {
            val s = runCatching { login(src, force = attempt > 0) }.getOrNull() ?: return@withContext null
            val (type, cmd) = if (ref.type == "mfile") "vod" to (movieFileCmd(src, s, ref.cmd) ?: continue) else ref.type to ref.cmd
            val r = js(src, StalkerLogic.createLink(s.endpoint, type, cmd, ref.series), s.token) as? JSONObject
            val u = StalkerLogic.playUrl(s.endpoint, r?.optString("cmd"), cmd)
            if (u != null) return@withContext u
        }
        if (ref.type == "mfile") return@withContext null
        // Some portals already deliver a directly playable address in the channel
        StalkerLogic.stripCmd(ref.cmd)?.takeIf { !it.contains("localhost") }
    }

    /**
     * Seasons and episodes of a series ([url] = placeholder "stalker://…/series/…"). null = portal does not answer;
     * empty list = series without episodes. Two portal constructions are recognized: seasons with episode numbers ("series" list)
     * and seasons that deliver their episodes as separate entries.
     */
    fun episodeList(url: String): List<Episode>? {
        val ref = StalkerLogic.seriesRef(url) ?: return null
        val src = sourceOf(ref.key) ?: return null
        val s = runCatching { login(src) }.getOrNull() ?: return null
        val type = if (ref.mode == "v") "vod" else "series"
        val seen = HashSet<Long>()
        val out = ArrayList<Episode>()

        fun add(season: Int, num: Int, cmd: String, series: String?) {
            if (cmd.isBlank() || !seen.add((season.toLong() shl 32) or num.toLong())) return
            out.add(Episode(season, num, EpTitles.of(num), StalkerLogic.itemUrl(src.key, "movie", cmd, series)))
        }

        /** Entries of a season: episode numbers or single episodes. true = something found. */
        fun fill(o: JSONObject, season: Int, fallbackNum: Int): Boolean {
            val cmd = o.optString("cmd").trim()
            val nums = o.optJSONArray("series")
            if (nums != null && nums.length() > 0) {
                var any = false
                for (i in 0 until nums.length()) {
                    val n = nums.opt(i)?.toString()?.trim()?.toIntOrNull() ?: continue
                    add(season, n, cmd, n.toString()); any = true
                }
                if (any) return true
            }
            if (cmd.isNotEmpty() && !isSeason(o)) {
                add(season, StalkerLogic.episodeNumber(fields(o), fallbackNum), cmd, null)
                return true
            }
            return false
        }

        val base = "&movie_id=${enc(ref.id)}&category=${enc(ref.cat)}&fav=0&sortby=added&hd=0&not_ended=0"
        val level1 = ArrayList<JSONObject>()
        if (!paged(s, type, "$base&season_id=0&episode_id=0", 600, {}) { level1.add(it) }) return null
        var idx = 0
        for (o in level1) {
            idx++
            val f = fields(o)
            val season = if (level1.size == 1 && !isSeason(o)) 1 else StalkerLogic.seasonNumber(f, idx)
            if (fill(o, season, idx)) continue
            // Season without own episodes: fetch its episodes individually
            val sid = o.opt("id")?.toString().orEmpty()
            if (sid.isEmpty()) continue
            var k = 0
            paged(s, type, "$base&season_id=${enc(sid)}&episode_id=0", 1000, {}) { e ->
                k++
                fill(e, season, k)
            }
        }
        out.sortWith(compareBy({ it.season }, { it.num }))
        return out
    }

    private fun isSeason(o: JSONObject): Boolean {
        val v = o.opt("is_season")
        if (v == true || v == 1 || v == "1" || v == "true") return true
        val nm = o.optString("name")
        return o.optJSONArray("series")?.length() == 0 && Regex("""(?i)(season|staffel|sezon|saison|temporada|stagione)""").containsMatchIn(nm)
    }
}
