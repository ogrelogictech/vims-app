package com.vims.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.data.AirQualityDef
import com.vims.app.data.ChecklistEngine
import com.vims.app.data.ItemDef
import com.vims.app.data.SectionAnswers
import com.vims.app.data.sectionTitle
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.PhotosR
import com.vims.app.ui.SectionsR
import com.vims.app.ui.ReportR
import com.vims.app.ui.SummaryR
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.BtnRow
import com.vims.app.ui.components.HdrAction
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.MultiChips
import com.vims.app.ui.components.PickerField
import com.vims.app.ui.components.Seg
import com.vims.app.ui.components.SingleChips
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VInput
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.vCard
import com.vims.app.ui.openSection
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Checks
import com.vims.app.util.Filters
import com.vims.app.util.Limits
import com.vims.app.util.Fmt

/** Returns to the Sections overview if it is on the back stack, otherwise opens it. */
fun NavHostController.toSections(inspId: String) { if (!popBackStack<SectionsR>(inclusive = false)) navigate(SectionsR(inspId)) }

@Composable
fun ModeTile(depth: String, form: String? = null, formLabel: String? = null) {
    val (label, bg) = when {
        form != null -> (formLabel ?: form) to V.brand
        depth == "high" -> "High Detail checklist" to V.brand
        depth == "fast" -> "Fast Entry checklist" to V.signalDeep
        else -> "Standard checklist" to V.ink3
    }
    val hint = when {
        form == "texas" -> "Mark each item I / NI / NP / D and add comments. Same on every checklist depth."
        form != null -> "Complete every line of the form. Same on every checklist depth."
        depth == "fast" -> "Overall condition and notes — no line-by-line. Change depth in Settings."
        else -> "Tap what applies, scroll to the next line — saves in one go."
    }
    // Team QA Oct 22: a long form badge ("Uniform Mitigation Verification Inspection Form") squeezed the hint into a one-word
    // column. The hint now sits beside the badge only while the badge takes at most half the row; otherwise it goes below it.
    BadgeAndHint(
        Modifier.padding(bottom = 14.dp).fillMaxWidth().vCard(12.dp).padding(horizontal = 13.dp, vertical = 11.dp),
        badge = { Text(label, style = T.ui(12.sp, FontWeight.Bold, Color.White, lineHeight = 15.sp), modifier = Modifier.clip(RoundedCornerShape(20.dp)).background(bg).padding(horizontal = 11.dp, vertical = 5.dp)) },
        hint = { Text(hint, style = T.ui(11.5.sp, color = V.ink3, lineHeight = 15.sp)) },
    )
}

/** Badge + hint in one row while the badge fits in half the width (both centered vertically), else stacked (hint full width). */
@Composable
private fun BadgeAndHint(modifier: Modifier, badge: @Composable () -> Unit, hint: @Composable () -> Unit) {
    androidx.compose.ui.layout.Layout(contents = listOf(badge, hint), modifier = modifier) { (b, h), c ->
        val gap = 10.dp.roundToPx()
        val bp = b.first().measure(c.copy(minWidth = 0, minHeight = 0))
        val side = bp.width <= c.maxWidth / 2
        val hp = h.first().measure(c.copy(minWidth = 0, minHeight = 0, maxWidth = if (side) (c.maxWidth - bp.width - gap).coerceAtLeast(0) else c.maxWidth))
        val w = c.maxWidth
        if (side) {
            val ht = maxOf(bp.height, hp.height)
            layout(w, ht) { bp.place(0, (ht - bp.height) / 2); hp.place(bp.width + gap, (ht - hp.height) / 2) }
        } else {
            val gapV = 8.dp.roundToPx()
            layout(w, bp.height + gapV + hp.height) { bp.place(0, 0); hp.place(0, bp.height + gapV) }
        }
    }
}

@Composable
fun LiHead(text: String) {
    Row(
        Modifier.padding(top = 8.dp, bottom = 11.dp).fillMaxWidth().shadow(6.dp, RoundedCornerShape(11.dp), ambientColor = V.brand, spotColor = V.brand)
            .clip(RoundedCornerShape(11.dp)).background(V.hdr).padding(horizontal = 13.dp, vertical = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Icon(VIcons.list, null, tint = Color.White.copy(alpha = .9f), modifier = Modifier.size(17.dp))
        Text(text, style = T.display(14.sp, FontWeight.Bold, Color.White))
    }
}

@Composable
fun LiCard(q: String, content: @Composable () -> Unit) {
    Column(Modifier.padding(bottom = 11.dp).fillMaxWidth().vCard().padding(horizontal = 15.dp, vertical = 14.dp)) {
        Text(q, style = T.ui(14.5.sp, FontWeight.SemiBold, V.ink), modifier = Modifier.padding(bottom = 11.dp))
        content()
    }
}

@Composable
fun SectionScreen(vm: AppViewModel, nav: NavHostController, inspId: String, name: String) {
    val all by vm.inspections.collectAsState()
    val b = all[inspId] ?: run { MissingInspection(vm, nav); return }
    val def = vm.sectionDef(inspId, name)
    // Picture pages (photosOnly) open straight to the photo screen.
    if (def?.photosOnly == true) { PhotosScreen(vm, nav, inspId, name); return }
    val depth = ChecklistEngine.effectiveDepth(def, b.inspection.selections.depth)
    val a = b.answers[name] ?: SectionAnswers()
    val ctx = LocalContext.current
    var drawer by rememberSaveable { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val allKeyed = remember(def, depth) { if (def == null) emptyList() else ChecklistEngine.keyed(ChecklistEngine.itemsFor(def, depth)) }
    // Data v1.8 `visibleIf`: e.g. "Sample 2 location" shows once "Samples taken" is 2 or more; hidden items aren't validated or printed.
    val keyed = ChecklistEngine.visibleKeyed(allKeyed, a)
    val detail = def != null && ChecklistEngine.showDetailInput(def, depth)
    val actionPrefix = (def?.airQuality ?: AirQualityDef()).actionPrefix
    fun edit(f: (SectionAnswers) -> SectionAnswers) = vm.editSection(inspId, name, f)
    // Data v1.9 `prefill`: owner / inspector fields start with the inspection's values on first open.
    androidx.compose.runtime.LaunchedEffect(inspId, name) { vm.prefillSection(inspId, name) }
    // Choosing "Concerns" / "Concern" on an item opens the Flag-a-finding sheet for that item (client request Oct 9).
    var concernItem by rememberSaveable { mutableStateOf<String?>(null) }
    BackHandler(enabled = concernItem != null) { concernItem = null }

    VScreen(
        sectionTitle(name), b.inspection.selections.street, net(vm), backAction(nav),
        listOf(HdrAction(VIcons.camera, "Photos") { nav.navigate(PhotosR(inspId, name)) }, HdrAction(VIcons.list, "Sections") { drawer = true }, homeAction(nav)),
        scroll = false,
        overlay = {
            SectionsDrawer(drawer, b, name, onClose = { drawer = false }, onLink = { drawer = false; nav.openLink(it, inspId) }, onSection = { drawer = false; nav.openSection(inspId, it) })
            // Cancel only closes it (the option stays selected); Add saves a finding for this section whose custom comment is
            // "<item>: <description>" (or "<item>") and whose quick comment is the one picked, if any.
            val item = concernItem
            FindingSheet(
                visible = item != null, vm = vm, initialText = "",
                title = "Concern: ${item.orEmpty()}",
                subtitle = "Describe the concern for this item and pick a category. It's added to the summary and the report automatically.",
                onCancel = { concernItem = null },
                onAdd = { cat, custom, quick -> if (item != null) vm.addFinding(inspId, cat, custom, quick, name, null, item = item); concernItem = null },
            )
        },
    ) {
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 34.dp)) {
            item(key = "mode") { ModeTile(depth, def?.form, def?.form?.let { vm.config.formLabels[it] }) }
            if (depth == "fast") {
                val quick = def?.items.orEmpty().filter { it.q != null && it.visibleIf == null }.map { it.q!! }.distinct()
                if (quick.isNotEmpty()) item(key = "present") {
                    Column {
                        Lbl("Items reviewed", first = true)
                        MultiChips(quick, a.present, { q -> edit { it.copy(present = if (q in it.present) it.present - q else it.present + q) } })
                    }
                }
            } else {
                itemsIndexed(keyed, key = { i, p -> p.first ?: "h$i" }) { _, (key, it) ->
                    if (key == null) LiHead(it.header.orEmpty())
                    else ItemCard(key, it, a, detail, ctx, actionPrefix, b.inspection.selections.counts, ::edit) { q -> concernItem = q }
                }
            }
            item(key = "overall") {
                Column {
                    if (def?.form == null) {
                        Lbl("Overall condition", first = depth != "fast" && keyed.isEmpty())
                        Seg(vm.config.overallCondition, a.overall ?: vm.config.overallConditionDefault, { v -> edit { it.copy(overall = v.orEmpty()) } })
                    }
                    Lbl("Comments")
                    VInput(a.comments, { v -> edit { it.copy(comments = v) } }, placeholder = "Notes for this section…", multiline = true, filter = { Filters.base(it, 4000, multiline = true) })
                    BtnRow {
                        VBtn("Photos", { nav.navigate(PhotosR(inspId, name)) }, Modifier.weight(1f), BtnKind.Ghost, VIcons.camera)
                        VBtn("Save", {
                            vm.saveSection(inspId, name); vm.toast("Section saved"); nav.toSections(inspId)
                        }, Modifier.weight(1f), BtnKind.Ghost, VIcons.check)
                    }
                    VBtn("Save & next section", {
                        vm.saveSection(inspId, name)
                        val next = vm.nextSection(inspId, name)
                        if (next != null) { vm.toast("Saved — next: ${sectionTitle(next)}"); nav.openSection(inspId, next) }
                        else { vm.toast("Saved — last section"); if (b.inspection.hasSummary) nav.navigate(SummaryR(inspId)) else nav.navigate(ReportR(inspId)) }
                    }, Modifier.padding(top = 10.dp), icon = VIcons.checkNext)
                }
            }
        }
    }
}

@Composable
private fun ItemCard(key: String, it: ItemDef, a: SectionAnswers, detail: Boolean, ctx: android.content.Context, actionPrefix: String, counts: Map<String, Int>, edit: ((SectionAnswers) -> SectionAnswers) -> Unit, onConcern: (String) -> Unit) {
    if (it.isAirReading) { AirReadingCard(key, it, a, actionPrefix, edit); return }
    val q = it.q.orEmpty()
    val input = a.inputs[key].orEmpty()
    val setInput: (String) -> Unit = { v -> edit { s -> s.copy(inputs = s.inputs + (key to v)) } }
    LiCard(q) {
        when (it.type) {
            // Data v1.12 `optionsFromCount`: Bathroom No. / Bedroom No. offer 1..n for this inspection's room count (live, so
            // a count changed later in Inspection info is followed); `defaultFromRoomNumber` pre-answers it (AppViewModel.prefillSection).
            "single" -> SingleChips(ChecklistEngine.choiceOptions(it, counts, a.values[key].orEmpty()), a.values[key]?.firstOrNull(), { v ->
                edit { s -> s.copy(values = s.values + (key to listOfNotNull(v))) }
                // Selecting (not deselecting) Concern(s) asks for the concern; deselecting never deletes a finding.
                if (v != null && v != a.values[key]?.firstOrNull() && isConcern(v)) onConcern(q)
            })
            "multi" -> MultiChips(it.options.orEmpty(), a.values[key].orEmpty(), { o ->
                val on = o !in a.values[key].orEmpty()
                edit { s -> val cur = s.values[key].orEmpty(); s.copy(values = s.values + (key to if (o in cur) cur - o else cur + o)) }
                if (on && isConcern(o)) onConcern(q)
            })
            "date" -> PickerField(if (input.isBlank()) "" else Fmt.date(input), "Select date", VIcons.calendar, { pickDate(ctx, input, onPick = setInput) })
            "time" -> PickerField(if (input.isBlank()) "" else Fmt.time(input), "Select time", VIcons.clock, { pickTime(ctx, input, setInput) })
            else -> {
                // `num` items (team QA Oct 22): limits enforced while typing — `integer: true` = number pad, whole numbers only;
                // otherwise decimal keypad with at most 2 decimals (`decimals: n` overrides, Radon level 1). A value above the max
                // (room counts like "Number of kitchens" 20, Septic "System number" 99, everything else 99,999) isn't accepted;
                // an older answer that breaks a rule shows the error inline. Text items stay free text.
                val num = it.type == "num"
                val max = Limits.checklistMax(q)
                val numErr = if (num) Checks.upTo(input, max, Limits.checklistMin(q), integer = it.integer == true, decimals = it.numDecimals) else null
                VInput(input, setInput, placeholder = it.placeholder ?: "Enter a value",
                    keyboard = if (!num) KeyboardType.Text else if (it.numDecimals == 0) KeyboardType.Number else KeyboardType.Decimal,
                    filter = if (num) { v -> Filters.number(v, it.numDecimals, max) } else { v -> Filters.base(v, 500) }, error = numErr,
                    wholeNumberMax = if (num && it.numDecimals == 0) max else null)
            }
        }
        if (detail && it.isChoice) {
            VInput(input, setInput, Modifier.padding(top = 9.dp), placeholder = "Detail / measurement (optional)", minHeight = 44.dp, textSize = 13f)
        }
    }
}

/**
 * Indoor Air Quality reading (data v1.7 `airReading`): optional "Level (<unit>)" on the decimal keypad + 1–6 rating chips
 * (tap again to deselect), then the reference levels and the corrective action in small text (prototype `it.t==='air'`).
 * Stored under the item key: rating in `values`, level in `inputs` (see SectionAnswers).
 */
@Composable
private fun AirReadingCard(key: String, it: ItemDef, a: SectionAnswers, actionPrefix: String, edit: ((SectionAnswers) -> SectionAnswers) -> Unit) {
    val level = a.inputs[key].orEmpty()
    val unit = it.unit.orEmpty()
    LiCard(it.q.orEmpty()) {
        VInput(level, { v -> edit { s -> s.copy(inputs = s.inputs + (key to v)) } },
            placeholder = if (unit.isBlank()) "Level measured" else "Level ($unit)", keyboard = KeyboardType.Decimal,
            filter = { v -> Filters.number(v, it.numDecimals, Limits.CHECKLIST_NUM) }, error = Checks.level(level), imeAction = ImeAction.Done)
        SingleChips(it.options.orEmpty().ifEmpty { (1..6).map { n -> "$n" } }, a.airRating(key), { v ->
            edit { s -> s.copy(values = s.values + (key to listOfNotNull(v))) }
        }, modifier = Modifier.padding(top = 10.dp))
        val ref = it.reference.orEmpty().trim()
        val act = it.action.orEmpty().trim()
        if (ref.isNotEmpty() || act.isNotEmpty()) {
            Text(listOfNotNull(ref.ifEmpty { null }, act.ifEmpty { null }?.let { x -> actionPrefix + x }).joinToString("\n"),
                style = T.ui(11.5.sp, color = V.ink3, lineHeight = 16.sp), modifier = Modifier.padding(top = 9.dp))
        }
    }
}

/** Standard / High Detail "Concerns" / "Concern" option (opens the concern finding sheet). */
private fun isConcern(option: String) = option.trim().matches(Regex("Concerns?", RegexOption.IGNORE_CASE))
