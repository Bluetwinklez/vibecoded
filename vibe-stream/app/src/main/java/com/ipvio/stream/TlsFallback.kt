package com.ipvio.stream

import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.SSLPeerUnverifiedException

/**
 * Some providers deliver a certificate that does not belong to their address (wrong or expired domain, shared default
 * certificate: "Hostname x not verified, certificate is for y"). Playlist, live TV and movies then fail although the
 * server itself works. For exactly this error – and only for provider streams – the app can try the same address over
 * plain http once and remember that host. Every other TLS error (expired, untrusted CA …) is still refused.
 *
 * The downgrade sends login data without encryption, and anyone on the network path can trigger it by presenting a
 * certificate for another name. It is therefore **off by default** and only happens when the user switched it on
 * (Settings > General > Security, [allowed]). Without that the request fails with the normal certificate error.
 * Core logic without Android, testable.
 */
object TlsFallback {
    private val broken: MutableSet<String> = ConcurrentHashMap.newKeySet()

    /** The user's choice: may a provider with a mismatching certificate be reached over plain http? Default: no. */
    @Volatile var allowed = false
        private set

    /** Applies the setting; switching it off also forgets the hosts that were downgraded in this session. */
    fun setAllowed(on: Boolean) {
        allowed = on
        if (!on) broken.clear()
    }

    /** Host name is in [url] (null = unparsable). */
    private fun hostOf(url: String): String? = url.toHttpUrlOrNull()?.host?.lowercase()

    /** Is the error (or one of its causes) "certificate does not match the host name"? */
    fun isHostMismatch(e: Throwable?): Boolean {
        var t = e
        var depth = 0
        while (t != null && depth < 8) {
            if (t is SSLPeerUnverifiedException) return true
            t = t.cause
            depth++
        }
        return false
    }

    fun markBroken(host: String) { if (allowed) broken.add(host.lowercase()) }
    fun isBroken(host: String): Boolean = allowed && broken.contains(host.lowercase())
    fun isBrokenUrl(url: String): Boolean = hostOf(url)?.let { isBroken(it) } ?: false

    /** The plain-http address to retry [url] with after the error [e], or null when no downgrade may happen. */
    fun fallbackUrl(url: String, e: Throwable?): String? = if (allowed && isHostMismatch(e)) downgradeUrl(url) else null

    /** https address -> same address over http (default port 443 becomes 80, a special port stays). null = not applicable. */
    fun downgradeUrl(url: String): String? {
        val u = url.toHttpUrlOrNull() ?: return null
        if (!u.isHttps) return null
        val port = if (u.port == 443) 80 else u.port
        return u.newBuilder().scheme("http").port(port).build().toString()
    }

    /** For OkHttp clients that talk to the provider (playlist, Xtream/Stalker login, live buffer). */
    fun interceptor(): Interceptor = Interceptor { chain ->
        val req = chain.request()
        val url = req.url
        if (!url.isHttps || !allowed) return@Interceptor chain.proceed(req)
        val host = url.host
        if (isBroken(host)) {
            val low = downgradeUrl(url.toString())?.toHttpUrlOrNull()
            if (low != null) return@Interceptor chain.proceed(req.newBuilder().url(low).build())
        }
        try {
            chain.proceed(req)
        } catch (e: IOException) {
            val low = fallbackUrl(url.toString(), e)?.toHttpUrlOrNull()
            if (low == null) throw e
            markBroken(host)
            Diag.report("Zertifikat passt nicht zur Adresse – Verbindung ohne Verschlüsselung")
            chain.proceed(req.newBuilder().url(low).build())
        }
    }
}
