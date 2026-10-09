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

    /**
     * What the viewer shows (and the downloaded PDF prints), with `{companyName}` filled: title, form lines (the first two
     * header lines are the page's logo / title placeholders and are skipped), body, the state disclosures (all when
     * [state] is blank; only that state's otherwise), closing.
     */
    fun pieces(companyName: String, state: String, stateName: (String) -> String): List<AgreementPiece> {
        fun f(t: String) = fill(t, companyName)
        val out = mutableListOf<AgreementPiece>(AgreementPiece.Title(f(title)))
        header.drop(2).takeIf { it.isNotEmpty() }?.let { out += AgreementPiece.Form(it.map(::f)) }
        body.forEach { out += it.piece(::f) }
        out += AgreementPiece.Heading(f(stateDisclosuresHeading))
        val code = state.trim().uppercase()
        val shown = if (code.isEmpty()) disclosures else disclosures.filterKeys { it == code }
        if (code.isNotEmpty() && shown.isEmpty()) out += AgreementPiece.Para("No additional disclosures for ${stateName(code)}.", muted = true)
        shown.forEach { (k, v) -> out += AgreementPiece.Disclosure(stateName(k), f(v)) }
        if (code.isNotEmpty() && shown.isNotEmpty() && shown.size < disclosures.size) {
            out += AgreementPiece.Note("Showing ${stateName(code)} only. The full agreement lists ${disclosures.size} states.")
        }
        closing.forEach { out += it.piece(::f) }
        return out
    }

    /**
     * The whole agreement (every state) as plain text for the editor: title, form lines, paragraphs separated by blank
     * lines, bullets prefixed "• ", the state-disclosures heading followed by one "State name: text" paragraph per state,
     * closing. `{companyName}` is filled in. [AgreementText.pieces] reads it back.
     */
    fun plainText(companyName: String, stateName: (String) -> String): String =
        pieces(companyName, "", stateName).mapNotNull { p ->
            when (p) {
                is AgreementPiece.Title -> p.text
                is AgreementPiece.Form -> p.lines.joinToString("\n")
                is AgreementPiece.Para -> p.text
                is AgreementPiece.Bullet -> AgreementText.BULLET + p.text
                is AgreementPiece.Heading -> p.text
                is AgreementPiece.Disclosure -> "${p.state}: ${p.text}"
                is AgreementPiece.Note -> null
            }
        }.joinToString("\n\n")

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
data class AgreementBlock(val t: String = "p", val text: String = "", val lead: Boolean = false) {
    fun piece(f: (String) -> String): AgreementPiece = if (t == "li") AgreementPiece.Bullet(f(text)) else AgreementPiece.Para(f(text), lead = lead)
}

/** One piece of the agreement as the viewer shows it; [AgreementPdf] prints the same list (except [Note]). */
sealed interface AgreementPiece {
    data class Title(val text: String) : AgreementPiece
    /** The boxed form lines (client / property / services). */
    data class Form(val lines: List<String>) : AgreementPiece
    /** Paragraph (may contain line breaks); `lead` = darker lead-in line, `muted` = gray (e.g. "No additional disclosures"). */
    data class Para(val text: String, val lead: Boolean = false, val muted: Boolean = false) : AgreementPiece
    data class Bullet(val text: String) : AgreementPiece
    data class Heading(val text: String) : AgreementPiece
    /** "State name: text" (state name in bold). */
    data class Disclosure(val state: String, val text: String) : AgreementPiece
    /** Viewer-only hint (not part of the agreement; not printed). */
    data class Note(val text: String) : AgreementPiece
}

/** A company's edited agreement (plain text, see [InspectionAgreement.plainText]). */
object AgreementText {
    const val BULLET = "• "
    /** Save limit for the editor. */
    const val MAX_CHARS = 100_000

    /** Paragraph per blank-line-separated block; lines starting with "• " are bullets (other lines keep their line breaks). */
    fun pieces(text: String): List<AgreementPiece> {
        val out = mutableListOf<AgreementPiece>()
        text.replace("\r\n", "\n").replace('\r', '\n').split(Regex("\n[ \t]*\n")).forEach { block ->
            val para = mutableListOf<String>()
            fun flush() { if (para.isNotEmpty()) { out += AgreementPiece.Para(para.joinToString("\n")); para.clear() } }
            block.split('\n').map { it.trimEnd() }.forEach { line ->
                val t = line.trimStart()
                when {
                    t.startsWith("•") -> { flush(); t.removePrefix("•").trim().takeIf { it.isNotEmpty() }?.let { out += AgreementPiece.Bullet(it) } }
                    line.isNotBlank() -> para += line
                }
            }
            flush()
        }
        return out
    }
}
