package com.vims.app.ui.screens

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
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.data.ChecklistEngine
import com.vims.app.data.ItemDef
import com.vims.app.data.SectionAnswers
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
    Row(Modifier.padding(bottom = 14.dp).fillMaxWidth().vCard(12.dp).padding(horizontal = 13.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(label, style = T.ui(12.sp, FontWeight.Bold, Color.White), modifier = Modifier.clip(RoundedCornerShape(20.dp)).background(bg).padding(horizontal = 11.dp, vertical = 5.dp))
        Text(hint, style = T.ui(11.5.sp, color = V.ink3, lineHeight = 15.sp), modifier = Modifier.weight(1f))
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
    val keyed = remember(def, depth) { if (def == null) emptyList() else ChecklistEngine.keyed(ChecklistEngine.itemsFor(def, depth)) }
    val detail = def != null && ChecklistEngine.showDetailInput(def, depth)
    fun edit(f: (SectionAnswers) -> SectionAnswers) = vm.editSection(inspId, name, f)

    VScreen(
        name, b.inspection.selections.street, net(vm), backAction(nav),
        listOf(HdrAction(VIcons.camera, "Photos") { nav.navigate(PhotosR(inspId, name)) }, HdrAction(VIcons.list, "Sections") { drawer = true }, homeAction(nav)),
        scroll = false,
        overlay = {
            SectionsDrawer(drawer, b, name, onClose = { drawer = false }, onLink = { drawer = false; nav.openLink(it, inspId) }, onSection = { drawer = false; nav.openSection(inspId, it) })
        },
    ) {
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 34.dp)) {
            item(key = "mode") { ModeTile(depth, def?.form, def?.form?.let { vm.config.formLabels[it] }) }
            if (depth == "fast") {
                val quick = def?.items.orEmpty().filter { it.q != null }.map { it.q!! }.distinct()
                if (quick.isNotEmpty()) item(key = "present") {
                    Column {
                        Lbl("Items present", first = true)
                        MultiChips(quick, a.present, { q -> edit { it.copy(present = if (q in it.present) it.present - q else it.present + q) } })
                    }
                }
            } else {
                itemsIndexed(keyed, key = { i, p -> p.first ?: "h$i" }) { _, (key, it) ->
                    if (key == null) LiHead(it.header.orEmpty())
                    else ItemCard(key, it, a, detail, ctx, ::edit)
                }
            }
            item(key = "overall") {
                Column {
                    if (def?.form == null) {
                        Lbl("Overall condition", first = depth != "fast" && keyed.isEmpty())
                        Seg(vm.config.overallCondition, a.overall ?: vm.config.overallConditionDefault, { v -> edit { it.copy(overall = v.orEmpty()) } })
                    }
                    Lbl("Comments")
                    VInput(a.comments, { v -> edit { it.copy(comments = v) } }, placeholder = "Notes for this section…", multiline = true)
                    BtnRow {
                        VBtn("Photos", { nav.navigate(PhotosR(inspId, name)) }, Modifier.weight(1f), BtnKind.Ghost, VIcons.camera)
                        VBtn("Save", {
                            vm.saveSection(inspId, name); vm.toast("Section saved"); nav.toSections(inspId)
                        }, Modifier.weight(1f), BtnKind.Ghost, VIcons.check)
                    }
                    VBtn("Save & next section", {
                        vm.saveSection(inspId, name)
                        val next = vm.nextSection(inspId, name)
                        if (next != null) { vm.toast("Saved — next: $next"); nav.openSection(inspId, next) }
                        else { vm.toast("Saved — last section"); if (b.inspection.hasSummary) nav.navigate(SummaryR(inspId)) else nav.navigate(ReportR(inspId)) }
                    }, Modifier.padding(top = 10.dp), icon = VIcons.checkNext)
                }
            }
        }
    }
}

@Composable
private fun ItemCard(key: String, it: ItemDef, a: SectionAnswers, detail: Boolean, ctx: android.content.Context, edit: ((SectionAnswers) -> SectionAnswers) -> Unit) {
    val q = it.q.orEmpty()
    val input = a.inputs[key].orEmpty()
    val setInput: (String) -> Unit = { v -> edit { s -> s.copy(inputs = s.inputs + (key to v)) } }
    LiCard(q) {
        when (it.type) {
            "single" -> SingleChips(it.options.orEmpty(), a.values[key]?.firstOrNull(), { v -> edit { s -> s.copy(values = s.values + (key to listOfNotNull(v))) } })
            "multi" -> MultiChips(it.options.orEmpty(), a.values[key].orEmpty(), { o ->
                edit { s -> val cur = s.values[key].orEmpty(); s.copy(values = s.values + (key to if (o in cur) cur - o else cur + o)) }
            })
            "date" -> PickerField(if (input.isBlank()) "" else Fmt.date(input), "Select date", VIcons.calendar, { pickDate(ctx, input, setInput) })
            "time" -> PickerField(if (input.isBlank()) "" else Fmt.time(input), "Select time", VIcons.clock, { pickTime(ctx, input, setInput) })
            else -> VInput(input, setInput, placeholder = it.placeholder ?: "Enter a value", keyboard = if (it.type == "num") KeyboardType.Decimal else KeyboardType.Text)
        }
        if (detail && it.isChoice) {
            VInput(input, setInput, Modifier.padding(top = 9.dp), placeholder = "Detail / measurement (optional)", minHeight = 44.dp, textSize = 13f)
        }
    }
}
