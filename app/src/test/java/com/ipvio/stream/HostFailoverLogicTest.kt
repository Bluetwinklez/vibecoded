package com.ipvio.stream

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HostFailoverLogicTest {
    private val g = listOf("http://main.tld:8080", "http://backup1.tld:8080", "http://backup2.tld")

    @Test fun normalize_ergaenzt_schema_und_entfernt_schraegstrich() {
        assertEquals("http://b.tld:8080", HostFailoverLogic.normalize(" b.tld:8080/ "))
        assertEquals("https://b.tld", HostFailoverLogic.normalize("https://b.tld"))
        assertNull(HostFailoverLogic.normalize(""))
        assertNull(HostFailoverLogic.normalize("   "))
        assertNull(HostFailoverLogic.normalize("http://b tld"))
    }

    @Test fun baseIndex_nur_ganze_adressen() {
        assertEquals(0, HostFailoverLogic.baseIndex("http://main.tld:8080/live/u/p/1.ts", g))
        assertEquals(2, HostFailoverLogic.baseIndex("http://BACKUP2.tld/player_api.php?x=1", g))
        // „main.tld:80801“ ist ein anderer Server
        assertEquals(-1, HostFailoverLogic.baseIndex("http://main.tld:80801/live/1.ts", g))
        assertEquals(-1, HostFailoverLogic.baseIndex("http://other.tld/live/1.ts", g))
    }

    @Test fun candidates_beginnen_beim_aktiven_server() {
        val u = "http://main.tld:8080/live/u/p/1.ts"
        assertEquals(
            listOf("http://main.tld:8080/live/u/p/1.ts", "http://backup1.tld:8080/live/u/p/1.ts", "http://backup2.tld/live/u/p/1.ts"),
            HostFailoverLogic.candidates(u, g, 0)
        )
        assertEquals(
            listOf("http://backup2.tld/live/u/p/1.ts", "http://main.tld:8080/live/u/p/1.ts", "http://backup1.tld:8080/live/u/p/1.ts"),
            HostFailoverLogic.candidates(u, g, 2)
        )
        // Adresse eines Backup-Servers (z. B. aus einer Playlist, die über ihn geladen wurde) gehört zur selben Gruppe
        assertEquals("http://main.tld:8080/movie/1.mp4", HostFailoverLogic.candidates("http://backup1.tld:8080/movie/1.mp4", g, 0)[0])
        // zu großer Index (Backup-Server gelöscht) wird begrenzt
        assertEquals("http://backup2.tld/x", HostFailoverLogic.candidates("http://main.tld:8080/x", g, 9)[0])
    }

    @Test fun candidates_ohne_gruppe_nur_die_adresse() {
        assertEquals(listOf("http://other.tld/x"), HostFailoverLogic.candidates("http://other.tld/x", g, 0))
        assertEquals(listOf("http://main.tld:8080/x"), HostFailoverLogic.candidates("http://main.tld:8080/x", listOf("http://main.tld:8080"), 0))
    }

    @Test fun group_beliebig_viele_ohne_leere_und_doppelte() {
        assertEquals(
            listOf("http://main.tld:8080", "http://b1.tld", "http://b2.tld", "http://b3.tld", "http://b4.tld"),
            HostFailoverLogic.group("http://main.tld:8080/", listOf("b1.tld", "", "http://MAIN.tld:8080", "b2.tld", "b1.tld", "b3.tld", "b4.tld", "kaputt adresse"))
        )
        assertEquals(listOf("http://main.tld:8080"), HostFailoverLogic.group("http://main.tld:8080", listOf("", " ")))
    }
}
