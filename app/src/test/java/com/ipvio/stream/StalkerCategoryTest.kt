package com.ipvio.stream

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** Stalker categories: page count, stored state for loading on demand, covers and play addresses. Synthetic data. */
class StalkerCategoryTest {
    @Test fun catRefRoundTrips() {
        val refs = listOf(
            StalkerLogic.CatRef("vod", "12", "Action", 4200, 15),
            StalkerLogic.CatRef("series", "7", "Kids & Family", -1, 0),
        )
        assertEquals(refs, StalkerLogic.decodeCats(StalkerLogic.encodeCats(refs)))
    }

    @Test fun catRefNameCannotBreakTheLine() {
        val r = StalkerLogic.CatRef("vod", "1", "A\tB\nC", 10, 1)
        val back = StalkerLogic.decodeCats(StalkerLogic.encodeCats(listOf(r))).single()
        assertEquals("A B C", back.name)
    }

    @Test fun catRefRejectsGarbage() {
        assertNull(StalkerLogic.CatRef.decode(""))
        assertNull(StalkerLogic.CatRef.decode("itv\t1\t10\t1\tNews"))
        assertNull(StalkerLogic.CatRef.decode("vod\t1\tx\t1\tNews"))
        assertNull(StalkerLogic.CatRef.decode("vod\t1\t10\t-2\tNews"))
        assertNull(StalkerLogic.CatRef.decode("vod\t\t10\t1\tNews"))
        assertEquals(emptyList<StalkerLogic.CatRef>(), StalkerLogic.decodeCats(null))
    }

    @Test fun pageCountFromTotals() {
        assertEquals(3, StalkerLogic.pageCount(30, 14, 1))
        assertEquals(1, StalkerLogic.pageCount(14, 14, 1))
        assertEquals(5, StalkerLogic.pageCount(0, 14, 5))
        assertEquals(5, StalkerLogic.pageCount(30, 0, 5))
    }

    @Test fun movieCoverPathIsResolved() {
        val src = StalkerLogic.source("http://portal.tld:8080/c/", "00:1A:79:12:34:56")!!
        val line = StalkerLogic.movieEntry(src, mapOf("cmd" to "/media/1.mpg", "name" to "Example", "screenshot_uri" to "/stalker_portal/screenshots/1/2.jpg"), "Drama")!!
        assertEquals(true, line.contains("tvg-logo=\"http://portal.tld:8080/stalker_portal/screenshots/1/2.jpg\""))
        val abs = StalkerLogic.movieEntry(src, mapOf("cmd" to "/media/1.mpg", "name" to "Example", "screenshot_uri" to "https://img.tld/p.jpg"), "Drama")!!
        assertEquals(true, abs.contains("tvg-logo=\"https://img.tld/p.jpg\""))
    }

    @Test fun stalkerChannelInMoviesGenreStaysLive() {
        val src = StalkerLogic.source("http://portal.tld:8080/c/", "00:1A:79:12:34:56")!!
        val line = StalkerLogic.liveEntry(src, mapOf("cmd" to "ffrt http://x/ch/1", "name" to "Movie Channel", "tv_genre_id" to "3"), mapOf("3" to "ENGLISH | PREMIUM MOVIES"))!!
        val item = M3uParser.parse("#EXTM3U\n$line\n").single()
        assertEquals(Kind.LIVE, item.kind)
    }

    @Test fun movieWithFilesIsLookedUpAtPlayTime() {
        val src = StalkerLogic.source("http://portal.tld:8080/c/", "00:1A:79:12:34:56")!!
        val f = mapOf("id" to "77", "cmd" to "/media/77.mpg", "name" to "Example", "has_files" to "1")
        val entry = StalkerLogic.movieEntry(src, f, "Drama")!!
        val ref = StalkerLogic.itemRef(entry.lines()[1])!!
        assertEquals("mfile", ref.type)
        assertEquals("77", ref.cmd)
        assertEquals(Kind.MOVIE, M3uParser.parse("#EXTM3U\n$entry\n").single().kind)
        assertEquals("vod", StalkerLogic.itemRef(StalkerLogic.movieEntry(src, f - "has_files", "Drama")!!.lines()[1])!!.type)
        assertEquals(false, StalkerLogic.needsFileLookup(f + ("cmd" to "/media/file_9.mpg"), "/media/file_9.mpg"))
    }

    @Test fun relativePlayUrlUsesPortalInstallation() {
        assertEquals("http://p.tld/x.m3u8", StalkerLogic.playUrl("http://p.tld/stalker_portal/server/load.php", "ffmpeg http://p.tld/x.m3u8"))
        assertEquals("http://p.tld:81/stalker_portal/media/vod/i.m3u8", StalkerLogic.playUrl("http://p.tld:81/stalker_portal/server/load.php", "/media/vod/i.m3u8"))
        assertEquals("http://p.tld/media/1.mp4", StalkerLogic.playUrl("http://p.tld/portal.php", "ffmpeg /media/1.mp4"))
        assertNull(StalkerLogic.playUrl("http://p.tld/portal.php", ""))
    }
}
