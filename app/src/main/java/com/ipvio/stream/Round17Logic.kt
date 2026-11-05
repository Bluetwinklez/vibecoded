package com.ipvio.stream

// Reine Regeln aus Nachtrag 17 (ohne Android, damit getestet werden kann)

/** Reine Formatierung der Technik-Info (getestet). */
object TechText {
    fun kbps(bps: Int): String = if (bps <= 0) "?" else if (bps >= 1_000_000) "%.1f Mbit/s".format(bps / 1_000_000.0) else "${bps / 1000} kbit/s"
    fun fps(f: Float): String = if (f <= 0f) "?" else if (Math.abs(f - Math.round(f)) < 0.01f) "${Math.round(f)}" else "%.3f".format(f)
    fun secs(ms: Long): String = "%.1f s".format(ms.coerceAtLeast(0L) / 1000.0)
}


/** Reine Regeln der App-Aktualisierung (getestet). */
object UpdateLogic {
    fun isNewer(current: Long, remote: Long): Boolean = remote > current

    /** Die APK-Adresse darf relativ zur Update-Adresse angegeben sein. */
    fun resolve(base: String, apk: String): String =
        if (apk.startsWith("http://") || apk.startsWith("https://")) apk
        else base.substringBeforeLast('/', base) + "/" + apk.trimStart('/')
}


/** Puffer-Stufen für langsames Internet (Nachtrag 18). Stufe 0 = Normal, 1 = Groß, 2 = Sehr groß. */
object BufferLogic {
    /** Wirksame Stufe: Modus 0 (Automatisch) nutzt die gelernte Stufe, 1 Normal, 2 Groß, 3 Sehr groß. */
    fun level(mode: Int, learned: Int): Int = when (mode) { 0 -> learned.coerceIn(0, 2); 1 -> 0; 2 -> 1; else -> 2 }

    /** Nur die Automatik lernt; eine Stufe pro Aufruf, höchstens 2. */
    fun bump(mode: Int, learned: Int): Int = if (mode == 0) (learned + 1).coerceAtMost(2) else learned

    /** [base] = (min ms, max ms, Start ms, Nachpuffern ms, Byte-Grenze oder -1). */
    fun scale(base: IntArray, level: Int): IntArray {
        if (level <= 0) return base
        val m = level + 1
        val bytes = if (base[4] > 0) minOf(base[4].toLong() * m, 64L * 1024 * 1024).toInt() else base[4]
        return intArrayOf(base[0] * m, base[1] * m, base[2] + 2000 * level, base[3] + 4000 * level, bytes)
    }
}
