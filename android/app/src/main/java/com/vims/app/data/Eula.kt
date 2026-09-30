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
    val isValid: Boolean get() = title.isNotBlank() && sections.isNotEmpty()

    companion object {
        const val ASSET = "legal/eula.json"

        /**
         * Loads the EULA synchronously (called once at app start). Never silently returns an empty agreement:
         * failures are logged and returned as an error so the screen can say so instead of rendering a blank card.
         */
        fun load(context: Context, asset: String = ASSET): Result<Eula> = try {
            val e = context.assets.open(asset).bufferedReader(Charsets.UTF_8).use { ChecklistLoader.json.decodeFromString(serializer(), it.readText()) }
            if (!e.isValid) throw IllegalStateException("$asset has no title/sections")
            Result.success(e)
        } catch (t: Throwable) {
            android.util.Log.e("VIMS-EULA", "Could not load $asset", t)
            Result.failure(t)
        }
    }
}

@Serializable
data class EulaSection(val heading: String, val paragraphs: List<String> = emptyList())
