package com.vims.app.data

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The VIMS default Home Inspection Agreement (shared/legal/inspection-agreement.json → assets/legal/inspection-agreement.json),
 * rendered verbatim. Every company uses it unless they upload their own (Company profile). `{companyName}` is replaced
 * with the signed-in company's name at display time ([fill]). See the file's `_about`.
 */
@Serializable
data class InspectionAgreement(
    val title: String = "",
    val version: String = "",
    val status: String = "",
    /** Form lines (client / property / services). The first two lines are the page's logo + title placeholders. */
    val header: List<String> = emptyList(),
    val body: List<AgreementBlock> = emptyList(),
    val stateDisclosuresHeading: String = "",
    /** Keyed by state code; kept as raw JSON so a non-string entry (e.g. a future `_about`) is skipped, not fatal. */
    val stateDisclosures: JsonObject = JsonObject(emptyMap()),
    val closing: List<AgreementBlock> = emptyList(),
) {
    val isValid: Boolean get() = title.isNotBlank() && body.isNotEmpty()

    /** State code → disclosure text, in file order (non-string / `_`-prefixed entries ignored). */
    val disclosures: Map<String, String> by lazy {
        stateDisclosures.entries.mapNotNull { (k, v) ->
            if (k.startsWith("_")) return@mapNotNull null
            (v as? JsonPrimitive)?.takeIf { it.isString }?.content?.let { k.uppercase() to it }
        }.toMap()
    }

    companion object {
        const val ASSET = "legal/inspection-agreement.json"
        const val COMPANY_TOKEN = "{companyName}"

        fun fill(text: String, companyName: String): String = text.replace(COMPANY_TOKEN, companyName.ifBlank { "the inspection company" })

        /** Loads the agreement synchronously (once, during background app startup, like the EULA). Failures are logged and returned. */
        fun load(context: Context, asset: String = ASSET): Result<InspectionAgreement> = try {
            val a = context.assets.open(asset).bufferedReader(Charsets.UTF_8).use { ChecklistLoader.json.decodeFromString(serializer(), it.readText()) }
            if (!a.isValid) throw IllegalStateException("$asset has no title/body")
            Result.success(a)
        } catch (t: Throwable) {
            android.util.Log.e("VIMS-Agreement", "Could not load $asset", t)
            Result.failure(t)
        }
    }
}

/** One paragraph (`t` = "p") or bullet (`t` = "li"); `lead` = a lead-in line shown in the darker ink. */
@Serializable
data class AgreementBlock(val t: String = "p", val text: String = "", val lead: Boolean = false)
