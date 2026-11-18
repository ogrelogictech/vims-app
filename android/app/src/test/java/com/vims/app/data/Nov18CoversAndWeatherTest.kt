package com.vims.app.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Client Nov 17 (shared v1.26.0): Christmas + Nativity, Day of the Dead and Feliz Navidad covers, Partly Cloudy weather. */
class Nov18CoversAndWeatherTest {
    private val config = TestData.config
    private fun sharedFile(path: String) = listOf("../../shared/$path", "../shared/$path").map(::File).first { it.exists() }

    @Test fun data_version() = assertEquals("1.26.0", config.version)

    @Test fun holidays_newCovers_haveArtInTheRightHalf() {
        val holidays = config.covers.categories.getValue("Holidays")
        assertEquals(listOf("Easter", "Christmas", "4th of July", "Hanukkah", "Passover", "Halloween", "Cinco de Mayo", "Day of the Dead", "Feliz Navidad"), holidays)
        for (name in listOf("Christmas", "Day of the Dead", "Feliz Navidad")) {
            val art = config.covers.themeArt.getValue(name)
            assertTrue(name, sharedFile(art.file).isFile)
            val (x, y, w, h) = art.rect
            // Never left of the page center (the footer text box), never past the page box (0.5, 0.68, 7.48 x 9.52).
            assertTrue("$name x=$x", x >= 4.25f)
            assertTrue("$name right=${x + w}", x + w <= 7.98f + 0.001f)
            assertTrue("$name bottom=${y + h}", y + h <= 10.20f + 0.001f)
        }
        assertEquals("covers/day-of-the-dead.webp", config.covers.themeArt.getValue("Day of the Dead").file)
        assertEquals("covers/feliz-navidad.webp", config.covers.themeArt.getValue("Feliz Navidad").file)
    }

    @Test fun weather_partlyCloudyAfterSunny() {
        val root = Json.parseToJsonElement(sharedFile("data/vims-checklists.json").readText())
        val found = mutableListOf<List<String>>()
        fun walk(e: JsonElement) {
            when (e) {
                is JsonObject -> {
                    if ((e["label"] as? JsonPrimitive)?.content == "Weather & site conditions") {
                        (e["options"] as? JsonArray)?.let { a -> found += a.map { it.jsonPrimitive.content } }
                    }
                    e.values.forEach(::walk)
                }
                is JsonArray -> e.forEach(::walk)
                else -> {}
            }
        }
        walk(root)
        assertEquals(1, found.size)
        assertEquals(listOf("Sunny", "Partly Cloudy", "Cloudy", "Overcast", "Windy", "Rainy", "Snowing"), found.single())
    }
}
