package com.vims.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Client Nov 19 (shared v1.27.0): Feliz Navidad cover art replaced by OgreLogic's own, license-clean lettering. */
class Nov19FelizNavidadTest {
    private val config = TestData.config

    // Shared v1.27.0 or later (Nov24AnnualBasePlanTest pins the current version).
    @Test fun data_version() = assertTrue(config.version, config.version.split(".").map { it.toInt() }.let { (a, b, _) -> a > 1 || (a == 1 && b >= 27) })

    @Test fun felizNavidad_art() {
        val art = config.covers.themeArt.getValue("Feliz Navidad")
        assertEquals("covers/feliz-navidad.webp", art.file)
        assertEquals(listOf(4.25f, 8.02f, 3.7f, 2.08f), art.rect)
        val f = listOf("../../shared/${art.file}", "../shared/${art.file}").map(::File).first { it.exists() }
        assertTrue(f.length() in 20_000L..400_000L)
        assertTrue(config.covers.categories.getValue("Holidays").contains("Feliz Navidad"))
    }
}
