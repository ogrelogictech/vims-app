package com.vims.app.data

import kotlinx.serialization.Serializable

/*
 * Shared data v1.15.0 `agreementPrefill` (client Oct 30): the inspection agreement fills in the client / inspection details
 * already entered — header form lines and some closing lines get their blank (`____`) replaced by the value (drawn bold in
 * the viewer and the PDF), and ☐ boxes become ☒ for the property type, inspection type, components, tests, utilities and
 * "NO Report to Real Estate Agent." when sending to the agent is off. Everything here is pure Kotlin (no Android), so it
 * can be unit-tested on the JVM.
 */

/** `agreementPrefill` in vims-checklists.json. Labels / boxes come from the data; the values are resolved in [AgreementFill.value]. */
@Serializable
data class AgreementPrefillDef(
    val lines: List<PrefillLine> = emptyList(),
    val checkboxes: PrefillCheckboxes = PrefillCheckboxes(),
    val emailButton: PrefillEmailDef = PrefillEmailDef(),
)

/** One fill-in line: [part] "header" (the boxed form lines) or "closing"; [occurrence] = n-th header line containing [label]. */
@Serializable
data class PrefillLine(val part: String = "header", val label: String = "", val occurrence: Int = 1, val value: String = "")

/**
 * One box mapping. Exactly one of [structure] / [type] / [component] / [test] / [utility] names the app value; [box] is the
 * agreement's label next to the box; [side] "after" = 'Purchase ☐', "before" = '☐ Radon Testing', "none" = no box.
 */
@Serializable
data class PrefillBox(
    val structure: String? = null,
    val type: String? = null,
    val component: String? = null,
    val test: String? = null,
    val utility: String? = null,
    val box: String = "",
    val side: String = "after",
)

@Serializable
data class PrefillCheckboxes(
    val propertyType: List<PrefillBox> = emptyList(),
    val inspectionType: List<PrefillBox> = emptyList(),
    val components: List<PrefillBox> = emptyList(),
    val tests: List<PrefillBox> = emptyList(),
    val utilities: List<PrefillBox> = emptyList(),
    val noAgentReport: PrefillBox? = null,
)

@Serializable
data class PrefillEmailDef(val label: String = "Email inspection agreement")

/** The inspection values the agreement is filled from (a saved inspection, or the wizard's current, unsaved values). */
data class AgreementFillInput(
    val clientName: String = "",
    val clientPhone: String = "",
    val clientEmail: String = "",
    val inspectorName: String = "",
    val license: String = "",
    val state: String = "",
    /** "Nov 3, 2026 9:00 AM" (date only without a time). */
    val dateTime: String = "",
    /** "<street>, <city>, <state> <zip>" (empty parts skipped). */
    val address: String = "",
    val street: String = "",
    val units: String = "",
    val sqft: String = "",
    val agentName: String = "",
    val agentEmail: String = "",
    val structure: String = "",
    val inspType: String = "",
    val components: List<String> = emptyList(),
    val tests: List<String> = emptyList(),
    val utilities: List<String> = emptyList(),
    val sendToAgent: Boolean = true,
)

object AgreementFill {
    const val BOX = '☐'
    const val TICK = '☒'
    private val blankRun = Regex("_+")

    /**
     * The fill input from wizard selections. [inspectorName] = the signed-in account's full name; [unitMixDefault] = the
     * wizard's default unit mix (an untouched Multi-Unit mix is the default, as the wizard shows it).
     */
    fun input(sel: WizardSelections, inspectorName: String, unitMixDefault: Map<String, Int>): AgreementFillInput {
        val date = com.vims.app.util.Fmt.parseDate(sel.date)?.let { com.vims.app.util.Fmt.date(it) } ?: sel.date
        val time = sel.time.takeIf { it.isNotBlank() }?.let { com.vims.app.util.Fmt.time(it) }.orEmpty()
        val units = when (sel.structure) {
            "Multi-Unit" -> sel.unitMix.ifEmpty { unitMixDefault }.values.sum().takeIf { it > 0 }?.toString().orEmpty()
            "Duplex" -> "2"
            else -> ""
        }
        val phoneDigits = sel.field(WizardSelections.F_CLIENT_PHONE).filter { it.isDigit() }
        return AgreementFillInput(
            clientName = sel.clientName,
            clientPhone = if (phoneDigits.length == 10) com.vims.app.util.formatPhone(phoneDigits) else sel.field(WizardSelections.F_CLIENT_PHONE),
            clientEmail = sel.clientEmail,
            inspectorName = inspectorName.trim(),
            license = sel.license,
            state = sel.state.trim().uppercase(),
            dateTime = listOf(date, time).filter { it.isNotBlank() }.joinToString(" "),
            address = sel.fullAddress,
            street = sel.street,
            units = units,
            sqft = sel.field("Total sq ft"),
            agentName = sel.agentName,
            agentEmail = sel.agentEmail,
            structure = sel.structure,
            inspType = sel.inspType,
            components = sel.component,
            tests = sel.tests,
            utilities = sel.utilOpt,
            sendToAgent = sel.sendToAgent,
        )
    }

    /** The value for a spec line, keyed by its label (the data's `value` is a description). Unknown label = nothing filled. */
    fun value(label: String, i: AgreementFillInput): String = when (label) {
        "Clients Name", "Printed Name of Client:" -> i.clientName
        "Phone #" -> i.clientPhone
        "Email" -> i.clientEmail
        "Inspectors Name" -> i.inspectorName
        "License/Reg #" -> i.license
        "State" -> i.state
        "Date and Time of Inspection" -> i.dateTime
        "Address of Property to be inspected" -> i.address
        "# Units" -> i.units
        "Total Sqft" -> i.sqft
        "Real Estate Agents Name" -> i.agentName
        "Agents Email" -> i.agentEmail
        else -> ""
    }.trim()

    /** Boxes to tick (each with its side) for [i]. Component ticks the chosen components (only for the Component type). */
    fun ticks(def: PrefillCheckboxes, i: AgreementFillInput): List<PrefillBox> = buildList {
        def.propertyType.filter { it.structure == i.structure }.forEach(::add)
        def.inspectionType.filter { it.type == i.inspType }.forEach(::add)
        if (def.inspectionType.any { it.type == i.inspType && it.side == "none" } || i.inspType == "Component") {
            def.components.filter { it.component in i.components }.forEach(::add)
        }
        def.tests.filter { it.test in i.tests }.forEach(::add)
        def.utilities.filter { it.utility in i.utilities }.forEach(::add)
        if (!i.sendToAgent) def.noAgentReport?.let(::add)
    }.filter { it.side == "after" || it.side == "before" }

    /** A line with filled values: [bold] = character ranges of inserted values. */
    data class Filled(val text: String, val bold: List<IntRange> = emptyList())

    /**
     * Replaces the first underscore run after [label] (starting at [labelAt]) in [f] with the value: the run becomes the value,
     * with one space between it and the text before it ("Date and Time of Inspection__" → "… Inspection Nov 3, 2026").
     * Returns null when there's no blank after the label or the blank is already filled.
     */
    fun fillAt(f: Filled, labelAt: Int, label: String, value: String): Filled? {
        val v = value.trim()
        if (v.isEmpty()) return null
        val m = blankRun.find(f.text, labelAt + label.length) ?: return null
        if (f.bold.any { m.range.first in it }) return null
        val needsSpace = m.range.first > 0 && !f.text[m.range.first - 1].isWhitespace()
        val insert = (if (needsSpace) " " else "") + v
        val text = f.text.substring(0, m.range.first) + insert + f.text.substring(m.range.last + 1)
        val delta = insert.length - (m.range.last + 1 - m.range.first)
        val start = m.range.first + if (needsSpace) 1 else 0
        val shifted = f.bold.map { if (it.first > m.range.first) (it.first + delta)..(it.last + delta) else it }
        return Filled(text, (shifted + listOf<IntRange>(start until start + v.length)).sortedBy { it.first })
    }

    /** Ticks the box next to [box] (side "after" / "before") the first place it appears unticked; null when not found. */
    fun tick(text: String, box: String, side: String): String? {
        if (box.isEmpty()) return null
        var from = 0
        while (true) {
            val at = text.indexOf(box, from)
            if (at < 0) return null
            val boxAt = if (side == "before") {
                var j = at - 1
                while (j >= 0 && text[j] == ' ') j--
                j
            } else {
                var j = at + box.length
                while (j < text.length && text[j] == ' ') j++
                j
            }
            if (boxAt in text.indices && text[boxAt] == BOX) return text.substring(0, boxAt) + TICK + text.substring(boxAt + 1)
            from = at + 1
        }
    }

    /**
     * Applies the fill to the viewer's pieces (VIMS agreement or a company's edited version): header lines fill the boxed
     * [AgreementPiece.Form] lines, closing lines fill the first paragraph that has the label followed by a blank; boxes are
     * ticked in the form lines first, then the paragraphs. Labels that no longer appear are skipped.
     */
    fun apply(pieces: List<AgreementPiece>, def: AgreementPrefillDef, i: AgreementFillInput): List<AgreementPiece> {
        val out = pieces.toMutableList()
        // --- form (header) lines
        val formAt = out.indexOfFirst { it is AgreementPiece.Form }
        if (formAt >= 0) {
            val form = out[formAt] as AgreementPiece.Form
            val lines = form.lines.mapIndexed { k, l -> Filled(l, form.bold[k].orEmpty()) }.toMutableList()
            // Each label is located in the original line; a line's labels are filled right to left so the positions of the
            // ones further left don't move (a fill only changes text after its own label).
            val targets = def.lines.filter { it.part == "header" && it.label.isNotEmpty() }.mapNotNull { spec ->
                val idx = form.lines.indices.filter { form.lines[it].contains(spec.label) }.getOrNull(spec.occurrence.coerceAtLeast(1) - 1)
                idx?.let { Triple(it, form.lines[it].indexOf(spec.label), spec) }
            }
            targets.sortedWith(compareBy<Triple<Int, Int, PrefillLine>> { it.first }.thenByDescending { it.second }).forEach { (idx, at, spec) ->
                fillAt(lines[idx], at, spec.label, value(spec.label, i))?.let { lines[idx] = it }
            }
            val ticks = ticks(def.checkboxes, i)
            val pending = ticks.toMutableList()
            for (k in lines.indices) {
                pending.toList().forEach { t -> tick(lines[k].text, t.box, t.side)?.let { lines[k] = lines[k].copy(text = it); pending.remove(t) } }
            }
            out[formAt] = AgreementPiece.Form(lines.map { it.text }, lines.mapIndexedNotNull { k, f -> f.bold.takeIf { it.isNotEmpty() }?.let { k to it } }.toMap())
            tickParas(out, pending)
        } else {
            tickParas(out, ticks(def.checkboxes, i).toMutableList())
        }
        // --- closing lines (first paragraph with the label followed by a blank)
        def.lines.filter { it.part == "closing" && it.label.isNotEmpty() }.forEach { spec ->
            val v = value(spec.label, i)
            for (k in out.indices) {
                val p = out[k] as? AgreementPiece.Para ?: continue
                val at = p.text.indexOf(spec.label).takeIf { it >= 0 } ?: continue
                if (p.bold.any { at in it }) continue
                val filled = fillAt(Filled(p.text, p.bold), at, spec.label, v)
                if (filled != null) { out[k] = p.copy(text = filled.text, bold = filled.bold); break }
                if (v.isEmpty()) break // nothing to fill: the blank stays
            }
        }
        return out
    }

    private fun tickParas(out: MutableList<AgreementPiece>, pending: MutableList<PrefillBox>) {
        if (pending.isEmpty()) return
        for (k in out.indices) {
            val p = out[k] as? AgreementPiece.Para ?: continue
            pending.toList().forEach { t ->
                val cur = out[k] as AgreementPiece.Para
                tick(cur.text, t.box, t.side)?.let { out[k] = cur.copy(text = it); pending.remove(t) }
            }
        }
    }

    /* ------------------------------------------------------------------ email */

    /** "Inspection-Agreement-<Client-Name>.pdf" ("…-<Company-Name>.pdf" without a client name). */
    fun pdfName(clientName: String, companyName: String): String =
        "Inspection-Agreement" + clientName.ifBlank { companyName }.replace(Regex("[^A-Za-z0-9]+"), "-").trim('-').let { if (it.isEmpty()) "" else "-$it" } + ".pdf"

    /** "Inspection Agreement – <street address>" ("Inspection Agreement" without an address). */
    fun subject(street: String): String = if (street.isBlank()) "Inspection Agreement" else "Inspection Agreement – ${street.trim()}"

    /**
     * The email body: greeting with the client's first name ("Hello," without a name), the agreement line (address / date
     * left out when empty), the state documents line when any are attached, and the inspector's sign-off.
     */
    fun body(i: AgreementFillInput, companyName: String, companyPhone: String, stateDocTitles: List<String>, stateName: String): String = buildString {
        val first = i.clientName.trim().split(Regex("\\s+")).firstOrNull().orEmpty()
        append(if (first.isEmpty()) "Hello," else "Hi $first,")
        append("\n\nAttached is the inspection agreement for the inspection")
        if (i.address.isNotBlank()) append(" at ${i.address.trim()}")
        if (i.dateTime.isNotBlank()) append(" on ${i.dateTime.trim()}")
        append(". Please read it, sign it and send it back to me before the inspection.")
        if (stateDocTitles.isNotEmpty()) append("\n\nAlso attached: ${stateDocTitles.joinToString(", ")}, which $stateName requires with the agreement.")
        append("\n\nThank you,")
        listOf(i.inspectorName, companyName, companyPhone).map { it.trim() }.filter { it.isNotEmpty() }.forEach { append("\n").append(it) }
    }
}
