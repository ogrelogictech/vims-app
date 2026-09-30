package com.vims.app.data

import android.content.Context
import kotlinx.serialization.Serializable

/** The client's End User License Agreement (shared/legal/eula.json → assets/legal/eula.json), rendered verbatim. */
@Serializable
data class Eula(
    val title: String = "",
    val revised: String = "",
    /** Bump in eula.json when the client revises the EULA — every user must re-accept. */
    val version: String = "",
    val intro: List<String> = emptyList(),
    val sections: List<EulaSection> = emptyList(),
    val footer: String = "",
) {
    companion object {
        fun load(context: Context): Eula = try {
            context.assets.open("legal/eula.json").bufferedReader().use { ChecklistLoader.json.decodeFromString(serializer(), it.readText()) }
        } catch (_: Exception) { Eula() }
    }
}

@Serializable
data class EulaSection(val heading: String, val paragraphs: List<String> = emptyList())
