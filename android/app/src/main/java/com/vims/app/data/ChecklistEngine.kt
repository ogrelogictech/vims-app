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

    /** Client Oct 28: a section the company added in Manage checklist (not part of the VIMS checklist). */
    fun isCustom(name: String): Boolean = edits.custom.any { it.def.name == name }

    /** Client Oct 28 ("Edited" tag): a VIMS section whose items the company changed (renamed / added / removed / reordered). */
    fun isEdited(name: String): Boolean {
        val shared = config.section(name) ?: return false
        val o = edits.overrides[shared.name] ?: return false
        return (o.items != null && o.items != shared.items) || (o.itemsHigh != null && o.itemsHigh != (shared.itemsHigh ?: shared.items))
    }

    /** Anything to restore: an edited VIMS section or a company-added section. */
    val hasCompanyEdits: Boolean get() = edits.custom.isNotEmpty() || edits.overrides.keys.any { isEdited(it) }

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
        // Data v1.10 (client Oct 25, `wizard.areasLockedTypes`): the locked step-3 areas (exterior / interior rooms / utility
        // options) never add sections for these types, whatever was chosen before switching the type (the choices are kept).
        val eff = if (config.wizard.areasLocked(sel.inspType)) sel.copy(exterior = emptyList(), rooms = emptyList(), utilOpt = emptyList()) else sel
        // Phase / form layouts (`checklistBuilder.phaseTypes`) are read like the standard layout: fixed `sections`, and the
        // `optional` / `order` / `always` / `then` / `sub` forms — Tests Only (v1.10) = Inspection Info + the tests chosen in
        // step 4 (`optional: "testOptions"`, + admin-added Testing sections) + Summary.
        val phase = cb.phaseTypes[sel.inspType]
        return (phase ?: cb.standardLayout).map { g ->
            when {
                g.link != null -> BuiltGroup(g.heading, g.icon ?: iconFor(g), g.link)
                else -> {
                    val secs = resolve(g, eff) + customFor(g.heading)
                    val sub = g.sub?.let { s -> BuiltGroup(s.heading, s.icon, null, resolve(s, eff) + customFor(s.heading)) }
                    BuiltGroup(g.heading, g.icon ?: if (phase != null) iconFor(g) else null, null, secs, sub)
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
            // Data v1.9.1 (team QA Oct 22): no type preselected — Type of inspection is required on step 1.
            inspType = d.inspType.orEmpty(),
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
        /**
         * Brings an inspection's checklist snapshot up to the current data where only the way an answer is ENTERED changed
         * (iOS reads the live data), matched by section + question:
         *  - v1.7.1: free-text inspection-day fields became date / time pickers (IAQ Date / Time, Termite, Wind Mitigation);
         *  - v1.9.1 (team QA Oct 22): text → `num` (Radon "Measured level (pCi/L)" 1 decimal, Septic "System number" whole
         *    number) and the `integer` / `decimals` limits of `num` items; Meth Test (High Detail) "Test date and time" + "AM/PM"
         *    became "Test date" (date) + "Test time" (time) — answers are moved over by [upgradeAnswers].
         * Nothing else in the snapshot changes; an answer typed earlier still shows and prints as typed.
         */
        fun upgradePickers(defs: Map<String, SectionDef>, current: List<SectionDef>, noMerge: Set<String> = emptySet()): Map<String, SectionDef> {
            if (defs.isEmpty()) return defs
            val byName = current.associateBy { it.name }
            var changed = false
            val out = defs.mapValues { (name, d) ->
                val cur = byName[name] ?: return@mapValues d
                val now = (cur.items + cur.itemsHigh.orEmpty()).filter { it.q != null }.groupBy { it.q!! }.mapValues { it.value.first() }
                var u = d.copy(items = upItems(d.items, now), itemsHigh = d.itemsHigh?.let { upItems(it, now) })
                // Client Oct 25 (shower pan items): questions ADDED to a section since the snapshot was taken join it, in data
                // order, answers untouched. Only for purely additive changes (every saved line is still in the current data) of
                // sections the company admin hasn't edited ([noMerge]); restructured sections (e.g. Termite / Wind Mitigation
                // before their v1.9 forms) keep their saved checklist exactly.
                if (name !in noMerge) u = u.copy(items = mergeAdded(u.items, cur.items),
                    itemsHigh = u.itemsHigh?.let { h -> cur.itemsHigh?.let { mergeAdded(h, it) } ?: h })
                // Data v1.8 section fields that only affect display / print (never the saved answers): the display title,
                // the report note, and photo categories added later (Meth Test "Cartridge Result") — so older snapshots get them too.
                if (u.title == null && cur.title != null) u = u.copy(title = cur.title)
                if (u.reportNote == null && cur.reportNote != null) u = u.copy(reportNote = cur.reportNote)
                u = u.copy(photoCategories = mergeCats(u.photoCategories, cur.photoCategories),
                    photoCategoriesHigh = u.photoCategoriesHigh?.let { h -> cur.photoCategoriesHigh?.let { mergeCats(h, it) } ?: h })
                if (u != d) changed = true
                u
            }
            return if (changed) out else defs
        }

        /** Identity of each line for [mergeAdded]: "H:header" / "Q:header|question" (+ "#n" when a question repeats under a header). */
        private fun lineKeys(items: List<ItemDef>): List<String> {
            var header = ""
            val seen = mutableMapOf<String, Int>()
            return items.map { i ->
                val base = if (i.isHeader) { header = i.header.orEmpty(); "H:$header" } else "Q:$header|${i.q.orEmpty()}"
                val n = seen.merge(base, 1, Int::plus)!!
                if (n == 1) base else "$base#$n"
            }
        }

        /**
         * [saved] plus the lines of [current] it lacks, each placed right after its nearest predecessor in [current] that is
         * already there (so "Shower pan filled for testing" / "Shower pan leaking" land before Comments, as in the data).
         * Nothing is removed or reordered. Returns [saved] unchanged unless every saved line still exists in [current]
         * (an additive data change) — a restructured section keeps its saved checklist.
         */
        fun mergeAdded(saved: List<ItemDef>, current: List<ItemDef>): List<ItemDef> {
            if (saved.isEmpty() || current.isEmpty()) return saved
            val sk = lineKeys(saved)
            val ck = lineKeys(current)
            val curSet = ck.toSet()
            if (sk.any { it !in curSet }) return saved
            val have = sk.toSet()
            if (ck.all { it in have }) return saved
            val out = saved.toMutableList()
            val outKeys = sk.toMutableList()
            var pos = -1 // index in out of the last current line seen
            ck.forEachIndexed { i, k ->
                val at = outKeys.indexOf(k)
                if (at >= 0) { pos = at; return@forEachIndexed }
                pos += 1
                out.add(pos, current[i]); outKeys.add(pos, k)
            }
            return out
        }

        /** Data v1.9.1: one free-text item that became two pickers, and the chip that went with it (Meth Test, High Detail). */
        private val LEGACY_SPLITS = mapOf("Test date and time" to listOf("Test date", "Test time"))
        private val LEGACY_SPLIT_COMPANION = mapOf("AM/PM" to "Test date and time")

        private fun upItems(list: List<ItemDef>, now: Map<String, ItemDef>): List<ItemDef> {
            fun splitTargets(i: ItemDef): List<ItemDef>? = i.q?.takeIf { i.type == "text" && it !in now }?.let { LEGACY_SPLITS[it] }
                ?.takeIf { t -> t.all { it in now } }?.map { now[it]!! }
            val splitting = list.mapNotNull { i -> i.q?.takeIf { splitTargets(i) != null } }.toSet()
            return list.flatMap { i ->
                val q = i.q ?: return@flatMap listOf(i)
                splitTargets(i)?.let { return@flatMap it }
                if (q !in now && LEGACY_SPLIT_COMPANION[q] in splitting) return@flatMap emptyList()
                val c = now[q] ?: return@flatMap listOf(i)
                listOf(when {
                    i.type == "text" && (c.type == "date" || c.type == "time") -> i.copy(type = c.type, placeholder = null)
                    i.type == "text" && c.type == "num" -> i.copy(type = "num", placeholder = c.placeholder, integer = c.integer, decimals = c.decimals)
                    i.type == "num" && c.type == "num" && (i.integer != c.integer || i.decimals != c.decimals) -> i.copy(integer = c.integer, decimals = c.decimals)
                    else -> i
                })
            }
        }

        /**
         * Moves answers to the items [upgradePickers] split (data v1.9.1, Meth Test High Detail): a "Test date and time" text such
         * as "10/12/2026 9:30" (+ the "AM/PM" chip) becomes "Test date" 2026-10-12 and "Test time" 09:30. Text that can't be read
         * as a date stays visible in "Test date" exactly as typed (shown and printed as typed until a date is picked). Answers
         * already given for the new items are never overwritten; the old keys are kept. Runs in memory on every load.
         */
        fun upgradeAnswers(defs: Map<String, SectionDef>, answers: Map<String, SectionAnswers>): Map<String, SectionAnswers> {
            if (answers.isEmpty()) return answers
            var changed = false
            val out = answers.mapValues { (section, a) ->
                val d = defs[baseName(section)] ?: return@mapValues a
                var r = a
                listOf(d.items, d.itemsHigh.orEmpty()).forEach { list ->
                    val k = keyed(list)
                    LEGACY_SPLITS.forEach { (from, to) ->
                        // Keys are "header|question", so the old item's key sits under the same header as the new ones.
                        val toKeys = to.map { q -> k.firstOrNull { it.second.q == q }?.first ?: return@forEach }
                        val header = toKeys[0].substringBeforeLast('|')
                        val text = r.inputs["$header|$from"].orEmpty().trim()
                        if (text.isEmpty() || toKeys.any { !r.inputs[it].isNullOrBlank() }) return@forEach
                        val ampm = LEGACY_SPLIT_COMPANION.entries.firstOrNull { it.value == from }?.key?.let { r.values["$header|$it"]?.firstOrNull() }
                        val (date, time) = splitDateTime(text, ampm)
                        r = r.copy(inputs = r.inputs + (toKeys[0] to (date ?: text)) + (if (time != null) mapOf(toKeys[1] to time) else emptyMap()))
                        changed = true
                    }
                }
                r
            }
            return if (changed) out else answers
        }

        private val MONTHS = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")

        /** Reads a free-text "date and time" ("10/12/2026 9:30", "Oct 12, 2026 2 pm", "2026-10-12 14:30") → (ISO date, "HH:mm"). */
        fun splitDateTime(text: String, ampm: String? = null): Pair<String?, String?> {
            val t = text.lowercase(java.util.Locale.US)
            var date: java.time.LocalDate? = null
            fun year(y: String) = y.toInt().let { if (y.length <= 2) 2000 + it else it }
            fun mk(y: Int, m: Int, d: Int) = try { java.time.LocalDate.of(y, m, d) } catch (_: Exception) { null }
            Regex("(\\d{4})-(\\d{1,2})-(\\d{1,2})").find(t)?.let { m -> date = mk(m.groupValues[1].toInt(), m.groupValues[2].toInt(), m.groupValues[3].toInt()) }
            if (date == null) Regex("(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{2,4})").find(t)?.let { m ->
                date = mk(year(m.groupValues[3]), m.groupValues[1].toInt(), m.groupValues[2].toInt())
            }
            if (date == null) Regex("([a-z]{3})[a-z]*\\.?\\s+(\\d{1,2})(st|nd|rd|th)?,?\\s+(\\d{4})").find(t)?.let { m ->
                val mo = MONTHS.indexOf(m.groupValues[1]) + 1
                if (mo > 0) date = mk(m.groupValues[4].toInt(), mo, m.groupValues[2].toInt())
            }
            // The time: "9:30", "9:30 pm", "2 pm", "14:30" — never the date's own numbers.
            val rest = Regex("\\d{4}-\\d{1,2}-\\d{1,2}|\\d{1,2}[/.-]\\d{1,2}[/.-]\\d{2,4}|[a-z]{3}[a-z]*\\.?\\s+\\d{1,2}(st|nd|rd|th)?,?\\s+\\d{4}").replace(t, " ")
            var time: String? = null
            val tm = Regex("\\b(\\d{1,2}):(\\d{2})\\s*([ap])?\\.?m?\\.?").find(rest) ?: Regex("\\b(\\d{1,2})()\\s*([ap])\\.?m\\b").find(rest)
            if (tm != null) {
                var h = tm.groupValues[1].toInt(); val min = tm.groupValues[2].ifEmpty { "0" }.toInt()
                val mer = tm.groupValues[3].ifEmpty { ampm?.trim()?.lowercase(java.util.Locale.US)?.take(1).orEmpty() }
                if (mer == "p" && h in 1..11) h += 12
                if (mer == "a" && h == 12) h = 0
                if (h in 0..23 && min in 0..59) time = String.format(java.util.Locale.US, "%02d:%02d", h, min)
            }
            return date?.toString() to time
        }

        /** [mine] plus any category of [current] it lacks, each inserted after its predecessor in [current] ("Concerns" stays last). */
        private fun mergeCats(mine: List<String>, current: List<String>): List<String> {
            if (mine.isEmpty() || current.all { it in mine }) return mine
            val out = mine.toMutableList()
            current.forEachIndexed { i, c ->
                if (c in out) return@forEachIndexed
                val prev = current.take(i).lastOrNull { it in out }
                out.add(if (prev == null) 0 else out.indexOf(prev) + 1, c)
            }
            return out
        }

        /**
         * `visibleIf` (data v1.8): whether [item] shows, given the section's answers. The rule's `q` is another item of the
         * same list ([keyed]); `atLeast` compares its single answer's leading number ("3" ≥ 2), `includes` checks the answer
         * (single or multi) contains the option. A rule whose question isn't in the list hides the item.
         */
        fun isVisible(item: ItemDef, keyed: List<Pair<String?, ItemDef>>, a: SectionAnswers): Boolean {
            val rule = item.visibleIf ?: return true
            val key = keyed.firstOrNull { (k, it) -> k != null && it.q == rule.q }?.first ?: return false
            val answer = a.values[key].orEmpty()
            rule.atLeast?.let { n ->
                val v = answer.firstOrNull()?.let { Regex("^\\s*(\\d+(\\.\\d+)?)").find(it)?.groupValues?.get(1)?.toDoubleOrNull() } ?: return false
                if (v < n) return false
            }
            rule.includes?.let { o -> if (answer.none { it.equals(o, ignoreCase = true) }) return false }
            return true
        }

        /** [keyed] without the items hidden by `visibleIf` (sub-section headers stay). */
        fun visibleKeyed(keyed: List<Pair<String?, ItemDef>>, a: SectionAnswers): List<Pair<String?, ItemDef>> =
            if (keyed.none { it.second.visibleIf != null }) keyed else keyed.filter { (k, it) -> k == null || isVisible(it, keyed, a) }

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
