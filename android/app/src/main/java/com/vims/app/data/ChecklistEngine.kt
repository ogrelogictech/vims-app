package com.vims.app.data

/**
 * Checklist logic, driven entirely by vims-checklists.json (+ admin edits):
 *  - effective section definitions (shared JSON with admin overrides and custom sections applied)
 *  - checklist generation from wizard selections (mirrors buildGroups() in the prototype via `checklistBuilder`)
 *  - depth rules (which items / photo categories a section shows at High Detail / Standard / Fast Entry)
 */
class ChecklistEngine(val config: ChecklistConfig, val edits: ChecklistEdits) {

    /** Admin groups (Manage checklist): shared sectionGroups + admin-added custom sections. */
    val adminGroups: List<Pair<String, List<String>>> by lazy {
        config.sectionGroups.map { g -> g.group to (g.sections + edits.custom.filter { it.group == g.group }.map { it.def.name }) }
    }

    fun def(name: String): SectionDef? {
        val base = baseName(name)
        edits.custom.firstOrNull { it.def.name == name || it.def.name == base }?.let { return it.def }
        val shared = config.section(name) ?: config.section(base) ?: return null
        val o = edits.overrides[shared.name] ?: return shared
        return shared.copy(items = o.items ?: shared.items, itemsHigh = o.itemsHigh ?: shared.itemsHigh)
    }

    /** Builds the section list for an inspection from the wizard selections. */
    fun buildGroups(sel: WizardSelections): List<BuiltGroup> {
        val cb = config.checklistBuilder
        cb.phaseTypes[sel.inspType]?.let { layout ->
            return layout.map { BuiltGroup(it.heading, it.icon ?: iconFor(it), it.link, it.sections.orEmpty()) }
        }
        return cb.standardLayout.map { g ->
            when {
                g.link != null -> BuiltGroup(g.heading, g.icon ?: iconFor(g), g.link)
                else -> {
                    val secs = resolve(g, sel) + customFor(g.heading)
                    val sub = g.sub?.let { s -> BuiltGroup(s.heading, s.icon, null, resolve(s, sel) + customFor(s.heading)) }
                    BuiltGroup(g.heading, g.icon, null, secs, sub)
                }
            }
        }
    }

    private fun resolve(g: LayoutGroupDef, sel: WizardSelections): List<String> {
        val out = mutableListOf<String>()
        g.sections?.let { out += it }
        g.always?.let { out += it }
        g.order?.forEach { token ->
            when {
                token.endsWith("?") -> token.dropLast(1).let { if (it in sel.rooms) out += it }
                token.contains("×") -> {
                    val base = token.substringBefore("×")
                    val n = sel.count(token.substringAfter("×"))
                    for (i in 1..n) out += "$base $i"
                }
                else -> out += token
            }
        }
        g.optional?.let { key ->
            val (options, chosen) = when (key) {
                "exteriorOptions" -> config.wizard.exteriorOptions to sel.exterior
                "utilityOptions" -> config.wizard.utilityOptions to sel.utilOpt
                "testOptions" -> config.wizard.testOptions to sel.tests
                "roomOptions" -> config.wizard.roomOptions to sel.rooms
                else -> emptyList<String>() to emptyList()
            }
            out += options.filter { it in chosen }
        }
        g.then?.let { out += it }
        return out
    }

    /** Admin-added sections are appended to the end of their group (Exterior, Interior, Utility, Testing). */
    private fun customFor(heading: String): List<String> {
        val group = when (heading) {
            "Property Exterior" -> "Exterior"
            "Property Interior" -> "Interior"
            "Utility & Function" -> "Utility"
            "Testing" -> "Testing"
            else -> return emptyList()
        }
        return edits.custom.filter { it.group == group }.map { it.def.name }
    }

    private fun iconFor(g: LayoutGroupDef): String = when (g.link) {
        "inspectionInfo" -> "info"
        "summary" -> "list"
        else -> "list"
    }

    /** Snapshot of the definitions an inspection uses (so later admin edits only affect new inspections). */
    fun snapshot(groups: List<BuiltGroup>, existing: Map<String, SectionDef> = emptyMap()): Map<String, SectionDef> {
        val out = existing.toMutableMap()
        groups.flatMap { it.leaves }.map { baseName(it) }.distinct().forEach { b ->
            if (b !in out) def(b)?.let { out[b] = it }
        }
        return out
    }

    fun defaultSelections(defaultDepth: String): WizardSelections {
        val w = config.wizard
        val d = w.defaults
        val chips = mutableMapOf<String, String>()
        // Every chips field with a default except depth (tracked separately as an id: high / standard / fast).
        (w.step1 + w.step2).filter { it.kind == "chips" && it.id != "wdepth" }.forEach { f -> f.default?.let { chips[f.label] = it } }
        return WizardSelections(
            chips = chips,
            inspType = d.inspType,
            structure = d.structure,
            depth = defaultDepth,
            counts = mapOf("bedrooms" to d.bedrooms, "bathrooms" to d.bathrooms, "hallways" to d.hallways),
            rooms = d.rooms.filter { it.value > 0 }.keys.toList(),
            exterior = d.exterior.filter { it.value > 0 }.keys.toList(),
            utilOpt = d.utilOpt.filter { it.value > 0 }.keys.toList(),
            tests = d.tests.filter { it.value > 0 }.keys.toList(),
            component = w.componentOptions.take(1),
            unitMix = w.unitMixDefault,
        )
    }

    companion object {
        fun number(defs: Map<String, SectionDef>, name: String): Int = defs[baseName(name)]?.number ?: 99

        /** Items to render for a section at a depth (Fast Entry renders its own "Items reviewed" chips). */
        fun itemsFor(def: SectionDef, depth: String): List<ItemDef> =
            if (def.form == null && depth == "high" && def.itemsHigh != null) def.itemsHigh else def.items

        /** State forms ignore the inspection's checklist depth. */
        fun effectiveDepth(def: SectionDef?, depth: String): String = if (def?.form != null) "standard" else depth

        /** High Detail without a High Detail list → Standard items + an optional "Detail / measurement" input. */
        fun showDetailInput(def: SectionDef, depth: String): Boolean = def.form == null && depth == "high" && def.itemsHigh == null

        fun photoCategories(def: SectionDef?, depth: String): List<String> {
            if (def == null) return listOf("Overview", "Concerns")
            val cats = if (def.form == null && depth == "high" && !def.photoCategoriesHigh.isNullOrEmpty()) def.photoCategoriesHigh else def.photoCategories
            return cats.ifEmpty { listOf("Overview", "Concerns") }
        }

        /**
         * Stable answer keys. Question text alone can repeat inside a section (e.g. "Any cracks" under several
         * headers), so the key is "header|question" plus an occurrence counter when still ambiguous.
         */
        fun keyed(items: List<ItemDef>): List<Pair<String?, ItemDef>> {
            var header = ""
            val seen = mutableMapOf<String, Int>()
            return items.map { it ->
                if (it.isHeader) { header = it.header.orEmpty(); null to it }
                else {
                    val base = "$header|${it.q}"
                    val n = seen.merge(base, 1, Int::plus)!!
                    (if (n == 1) base else "$base#$n") to it
                }
            }
        }
    }
}
