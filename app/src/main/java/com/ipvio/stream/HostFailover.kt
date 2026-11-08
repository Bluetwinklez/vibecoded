package com.ipvio.stream

import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.TransferListener
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap

/**
 * Backup-Server für Xtream-Zugänge, ohne Android, testbar.
 *
 * Eine Gruppe = Hauptserver + beliebig viele Backup-Server desselben Anbieters (gleicher Benutzername und
 * dasselbe Passwort, nur eine andere Adresse). Alle Adressen in der App (Playlist, EPG, Streams, Archiv) beginnen mit
 * der Adresse des Hauptservers; fällt er aus, wird nur dieser Anfang gegen den eines Backup-Servers getauscht.
 */
object HostFailoverLogic {
    private val BASE = Regex("""^https?://[^\s/?#]+(?:/[^\s?#]*)?$""", RegexOption.IGNORE_CASE)

    /** Eingabe wie im Server-Feld („server.tld:8080“ wird zu „http://server.tld:8080“), null = ungültig oder leer. */
    fun normalize(s: String): String? {
        var h = s.trim().trimEnd('/')
        if (h.isEmpty()) return null
        if (!h.startsWith("http://", true) && !h.startsWith("https://", true)) h = "http://$h"
        return if (BASE.matches(h)) h else null
    }

    /** Index der Adresse aus [bases], mit der [url] beginnt (bei mehreren die längste), sonst -1. */
    fun baseIndex(url: String, bases: List<String>): Int {
        var best = -1
        for ((i, b) in bases.withIndex()) {
            if (!url.startsWith(b, ignoreCase = true)) continue
            if (url.length != b.length && url[b.length] !in "/?#") continue
            if (best < 0 || b.length > bases[best].length) best = i
        }
        return best
    }

    /**
     * Adressen zum Ausprobieren, der Reihe nach: zuerst über den zuletzt funktionierenden Server ([active]),
     * dann über die übrigen. Gehört [url] zu keiner Gruppe, nur [url] selbst.
     */
    fun candidates(url: String, bases: List<String>, active: Int): List<String> {
        val i = baseIndex(url, bases)
        if (i < 0 || bases.size < 2) return listOf(url)
        val rest = url.substring(bases[i].length)
        val first = active.coerceIn(0, bases.lastIndex)
        return (listOf(first) + bases.indices.filter { it != first }).map { bases[it] + rest }
    }

    /** Hauptserver + gültige, verschiedene Backup-Server in der eingegebenen Reihenfolge; leere Eingaben fallen weg. */
    fun group(primary: String, backups: List<String>): List<String> {
        val out = arrayListOf(primary.trimEnd('/'))
        for (b in backups) {
            val n = normalize(b) ?: continue
            if (out.none { it.equals(n, ignoreCase = true) }) out.add(n)
        }
        return out
    }
}

/**
 * Laufzeit-Teil: merkt sich je Gruppe den Server, der zuletzt geantwortet hat (nur bis zum Neustart der App,
 * danach wird wieder zuerst der Hauptserver versucht). Greift an zwei Stellen: [Interceptor] im gemeinsamen
 * HTTP-Client ([Net]) für Playlist, Schnittstelle, EPG und Archiv, [DataSourceWrapper] im Player für die Streams.
 *
 * Außerdem der Zustand jedes Servers (erreichbar / nicht erreichbar seit …), damit die Oberfläche tote Adressen
 * zeigen kann. [PlaylistStore] speichert ihn über [onHealthChange], er gilt also auch nach einem Neustart.
 */
object HostFailover {
    @Volatile private var groups: List<List<String>> = emptyList()
    private val active = ConcurrentHashMap<String, Int>()

    /** Gruppen neu setzen (aus [PlaylistStore]); Gruppen ohne Backup-Server werden ignoriert. */
    fun setGroups(g: List<List<String>>) { groups = g.filter { it.size > 1 } }

    private fun groupOf(url: String): List<String>? = groups.firstOrNull { HostFailoverLogic.baseIndex(url, it) >= 0 }

    fun candidates(url: String): List<String> {
        val g = groupOf(url) ?: return listOf(url)
        return HostFailoverLogic.candidates(url, g, active[g[0].lowercase()] ?: 0)
    }

    fun markWorking(url: String) {
        val g = groupOf(url) ?: return
        val i = HostFailoverLogic.baseIndex(url, g)
        if (i >= 0) active[g[0].lowercase()] = i
        setHealth(url, true)
    }

    fun markFailed(url: String) = setHealth(url, false)

    /** Zustand eines Servers: [ok] = hat zuletzt geantwortet; [at] = seit wann dieser Zustand gilt. */
    class Health(val ok: Boolean, val at: Long)
    private val health = ConcurrentHashMap<String, Health>()

    /** Erhöht sich bei jeder Änderung, damit die Oberfläche neu zeichnet. */
    var healthVersion by mutableIntStateOf(0)
        private set

    /** Bei jedem Wechsel erreichbar ↔ nicht erreichbar (nicht bei jeder Anfrage), zum Speichern. */
    @Volatile var onHealthChange: ((Map<String, Health>) -> Unit)? = null

    fun health(base: String): Health? = health[base.trimEnd('/').lowercase()]

    /** Gespeicherten Zustand beim Start übernehmen. */
    fun loadHealth(m: Map<String, Health>) { health.putAll(m); healthVersion++ }

    private fun setHealth(url: String, ok: Boolean) {
        val g = groupOf(url) ?: return
        val i = HostFailoverLogic.baseIndex(url, g)
        if (i < 0) return
        val k = g[i].lowercase()
        // Nur ein Wechsel zählt: so bleibt bei einem Ausfall der erste Zeitpunkt stehen („nicht erreichbar seit …“)
        if (health[k]?.ok == ok) return
        health[k] = Health(ok, System.currentTimeMillis())
        healthVersion++
        onHealthChange?.invoke(HashMap(health))
    }

    /** Für alle OkHttp-Anfragen: bei Verbindungsfehler oder 5xx der Reihe nach die Backup-Server versuchen. */
    object Interceptor : okhttp3.Interceptor {
        override fun intercept(chain: okhttp3.Interceptor.Chain): okhttp3.Response {
            val req = chain.request()
            val urls = candidates(req.url.toString())
            if (urls.size < 2) return chain.proceed(req)
            var last: IOException? = null
            for ((i, u) in urls.withIndex()) {
                val target = u.toHttpUrlOrNull() ?: continue
                try {
                    val resp = chain.proceed(req.newBuilder().url(target).build())
                    if (resp.code >= 500) {
                        markFailed(u)
                        if (i < urls.lastIndex) { resp.close(); continue }
                    } else markWorking(u)
                    return resp
                } catch (e: IOException) {
                    if (chain.call().isCanceled()) throw e
                    markFailed(u)
                    last = e
                }
            }
            throw last ?: IOException("Kein Server erreichbar")
        }
    }

    /** Server antwortet nicht (Verbindung, Zeitlimit) oder meldet einen Serverfehler (5xx)? 4xx = Server lebt. */
    private fun serverDown(e: IOException): Boolean = when (e) {
        is HttpDataSource.InvalidResponseCodeException -> e.responseCode >= 500
        is HttpDataSource.HttpDataSourceException -> true
        else -> false
    }

    /** Für den Player: öffnet Streams über den zuletzt funktionierenden Server und weicht bei Ausfall aus. */
    class DataSourceWrapper(private val inner: DataSource) : DataSource {
        override fun addTransferListener(transferListener: TransferListener) = inner.addTransferListener(transferListener)

        override fun open(dataSpec: DataSpec): Long {
            val urls = candidates(dataSpec.uri.toString())
            if (urls.size < 2) return inner.open(dataSpec)
            for ((i, u) in urls.withIndex()) {
                try {
                    val n = inner.open(dataSpec.withUri(Uri.parse(u)))
                    markWorking(u)
                    return n
                } catch (e: IOException) {
                    if (!serverDown(e)) throw e
                    markFailed(u)
                    if (i == urls.lastIndex) throw e
                    runCatching { inner.close() }
                }
            }
            return inner.open(dataSpec)   // nicht erreichbar: die Schleife endet immer mit return oder throw
        }

        override fun read(buffer: ByteArray, offset: Int, length: Int): Int = inner.read(buffer, offset, length)
        override fun getUri(): Uri? = inner.uri
        override fun getResponseHeaders(): Map<String, List<String>> = inner.responseHeaders
        override fun close() = inner.close()

        class Factory(private val inner: DataSource.Factory) : DataSource.Factory {
            override fun createDataSource(): DataSource = DataSourceWrapper(inner.createDataSource())
        }
    }
}
