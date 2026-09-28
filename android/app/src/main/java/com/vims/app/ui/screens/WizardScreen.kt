package com.vims.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.data.WizardFieldDef
import com.vims.app.data.WizardSelections
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.SectionsR
import com.vims.app.ui.WizardR
import com.vims.app.ui.back
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.BtnRow
import com.vims.app.ui.components.ChipFlow
import com.vims.app.ui.components.Counter
import com.vims.app.ui.components.FieldLabel
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.MultiChips
import com.vims.app.ui.components.PickerField
import com.vims.app.ui.components.SingleChips
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VChip
import com.vims.app.ui.components.VInput
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.vCard
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Fmt

@Composable
fun WizardScreen(vm: AppViewModel, nav: NavHostController, inspId: String?) {
    var started by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) { if (!started) { vm.startWizard(inspId); started = true } }
    val w by vm.wizard.collectAsState()
    val cfg = vm.config.wizard
    val editing = inspId != null

    BackHandler(enabled = w.step > 1) { vm.wizardStep(w.step - 1) }

    fun next() {
        if (w.step < 4) { vm.wizardStep(w.step + 1); return }
        val id = vm.buildChecklist() ?: return
        if (editing) nav.back()
        else nav.navigate(SectionsR(id)) { popUpTo<WizardR> { inclusive = true } }
    }

    key(w.step) {
        VScreen(
            if (editing) "Inspection info" else "New inspection",
            if (editing) w.sel.street.ifBlank { companyName(vm) } else companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav)),
        ) {
            StepsBar(w.step)
            when (w.step) {
                1 -> {
                    Lbl(cfg.steps.getOrElse(0) { "Client & inspection" }, first = true)
                    WizardFields(vm, cfg.step1, w.sel)
                }
                2 -> WizardFields(vm, cfg.step2, w.sel, step2 = true)
                3 -> {
                    Hint("Choose every area to inspect — add or remove anything. This builds the checklist.", Modifier.padding(top = 2.dp, bottom = 12.dp))
                    Lbl("Exterior areas", first = true)
                    MultiChips(cfg.exteriorOptions, w.sel.exterior, { o -> vm.updateSel { it.copy(exterior = it.exterior.toggle(o)) } })
                    Lbl("Room counts")
                    cfg.roomCounts.forEach { rc ->
                        Counter(rc.label, w.sel.count(rc.key),
                            onMinus = { vm.updateSel { it.copy(counts = it.counts + (rc.key to (it.count(rc.key) - 1).coerceAtLeast(0))) } },
                            onPlus = { vm.updateSel { it.copy(counts = it.counts + (rc.key to (it.count(rc.key) + 1).coerceAtMost(12))) } })
                    }
                    Lbl("Interior rooms")
                    MultiChips(cfg.roomOptions, w.sel.rooms, { o -> vm.updateSel { it.copy(rooms = it.rooms.toggle(o)) } })
                    Lbl("Utility & systems")
                    MultiChips(cfg.utilityOptions, w.sel.utilOpt, { o -> vm.updateSel { it.copy(utilOpt = it.utilOpt.toggle(o)) } })
                }
                else -> {
                    Hint("Add any secondary testing for this inspection.", Modifier.padding(top = 2.dp, bottom = 12.dp))
                    MultiChips(cfg.testOptions, w.sel.tests, { o -> vm.updateSel { it.copy(tests = it.tests.toggle(o)) } })
                }
            }
            BtnRow(Modifier.padding(top = 10.dp)) {
                VBtn("Back", { vm.wizardStep(w.step - 1) }, Modifier.weight(1f).alpha(if (w.step == 1) 0f else 1f), BtnKind.Ghost, enabled = w.step > 1)
                VBtn(if (w.step == 4) (if (editing) "Update checklist" else "Build checklist") else "Next", { next() }, Modifier.weight(1f), icon = if (w.step == 4) VIcons.arrowRight else null)
            }
        }
    }
}

private fun List<String>.toggle(o: String) = if (o in this) this - o else this + o

@Composable
private fun StepsBar(step: Int) {
    Row(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 16.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        for (i in 1..4) {
            Box(Modifier.weight(1f).height(5.dp).clip(RoundedCornerShape(4.dp)).background(if (i == step) V.brand else if (i < step) V.brandBright else V.paper3))
        }
    }
}

private fun keyboardFor(f: WizardFieldDef, step2: Boolean): KeyboardType = when {
    f.type == "tel" -> KeyboardType.Phone
    f.type == "email" -> KeyboardType.Email
    f.label.startsWith("Lot size") -> KeyboardType.Decimal
    step2 || f.label.startsWith("Temperature") -> KeyboardType.Number
    else -> KeyboardType.Text
}

/** Renders a wizard step from `wizard.step1` / `wizard.step2` in vims-checklists.json. */
@Composable
private fun WizardFields(vm: AppViewModel, defs: List<WizardFieldDef>, sel: WizardSelections, step2: Boolean = false) {
    val cfg = vm.config.wizard
    var i = 0
    var shownDetailsLbl = false
    while (i < defs.size) {
        val f = defs[i]
        val nextDef = defs.getOrNull(i + 1)
        when (f.kind) {
            "field" -> {
                val pair = nextDef?.takeIf { n -> (f.type == "date" && n.type == "time") || (step2 && f.type == "text" && n.kind == "field" && n.type == "text") }
                if (step2 && !shownDetailsLbl) { Lbl("Property details"); shownDetailsLbl = true }
                if (pair != null) {
                    Row(Modifier.padding(bottom = 11.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        FieldCell(vm, f, sel, Modifier.weight(1f), step2)
                        FieldCell(vm, pair, sel, Modifier.weight(1f), step2)
                    }
                    i += 2; continue
                }
                if (f.label.startsWith("Temperature") && nextDef?.kind == "chips") {
                    // Prototype layout: "Weather & site conditions" label, a narrow temperature field, then the weather chips.
                    Lbl(nextDef.label)
                    Column(Modifier.padding(bottom = 11.dp)) {
                        FieldLabel(f.label)
                        VInput(sel.fields[f.label].orEmpty(), { v -> vm.updateSel { it.copy(fields = it.fields + (f.label to v)) } }, Modifier.width(120.dp), placeholder = f.placeholder.orEmpty(), keyboard = KeyboardType.Number)
                    }
                    SingleChips(nextDef.options.orEmpty(), sel.chip(nextDef.label), { v -> vm.updateSel { it.copy(chips = it.chips + (nextDef.label to v.orEmpty())) } }, modifier = Modifier.padding(bottom = 14.dp))
                    i += 2; continue
                }
                Column(Modifier.padding(bottom = 13.dp)) {
                    FieldCell(vm, f, sel, Modifier, step2)
                }
                if (f.label == WizardSelections.F_AGENT_EMAIL) {
                    Text("Client & agent emails are used to send the finished report.", style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, end = 2.dp, top = 0.dp, bottom = 12.dp))
                }
                i++
            }
            "chips" -> {
                val selected = sel.chip(f.label)
                when {
                    f.options == listOf("Yes", "No", "Unknown") -> {
                        Row(Modifier.padding(bottom = 9.dp).fillMaxWidth().vCard(12.dp).padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(f.label, style = T.ui(14.5.sp, FontWeight.Bold), modifier = Modifier.weight(1f))
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                f.options.forEach { o -> VChip(o, o == selected, { vm.updateSel { it.copy(chips = it.chips + (f.label to if (o == selected) "" else o)) } }) }
                            }
                        }
                        if (nextDef?.options != listOf("Yes", "No", "Unknown")) Spacer(Modifier.height(5.dp))
                    }
                    f.id == "wdepth" -> {
                        Lbl(f.label)
                        Text("Changes how much detail each section asks for. You can also set a default in Settings.", style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, end = 2.dp, top = 0.dp, bottom = 9.dp))
                        SingleChips(f.options.orEmpty(), vm.config.depthLabel(sel.depth), { v -> if (v != null) vm.updateSel { it.copy(depth = vm.config.depthId(v)) } }, required = true)
                    }
                    else -> {
                        Lbl(f.label)
                        SingleChips(f.options.orEmpty(), selected, { v -> vm.updateSel { it.copy(chips = it.chips + (f.label to v.orEmpty())) } })
                        if (f.id == "wstories" && selected == "Other") {
                            VInput(sel.storiesOther, { v -> vm.updateSel { it.copy(storiesOther = v) } }, Modifier.padding(top = 10.dp),
                                placeholder = "Describe what 'other' consists of (e.g. split-level, loft, partial third story)…", multiline = true)
                        }
                    }
                }
                i++
            }
            "dynamic" -> {
                Lbl(f.label, first = step2 && i == 0)
                when (f.id) {
                    "wtype" -> {
                        SingleChips(cfg.inspectionTypes, sel.inspType, { v -> if (v != null) vm.updateSel { it.copy(inspType = v) } }, required = true)
                        if (sel.inspType == "Component") {
                            Lbl("Component(s) to inspect")
                            MultiChips(cfg.componentOptions, sel.component, { o -> vm.updateSel { it.copy(component = it.component.toggle(o)) } })
                        }
                    }
                    "wstruct" -> {
                        SingleChips(cfg.structureTypes, sel.structure, { v ->
                            if (v != null) vm.updateSel { s ->
                                val add = cfg.structureSideEffects[v]?.get("exterior")
                                s.copy(structure = v, exterior = if (add != null && add !in s.exterior) s.exterior + add else s.exterior)
                            }
                        }, required = true)
                        if (sel.structure == "Multi-Unit") {
                            Lbl("Unit mix")
                            val mix = sel.unitMix.ifEmpty { cfg.unitMixDefault }
                            mix.keys.forEach { k ->
                                Counter(k, mix[k] ?: 0,
                                    onMinus = { vm.updateSel { it.copy(unitMix = mix + (k to ((mix[k] ?: 0) - 1).coerceAtLeast(0))) } },
                                    onPlus = { vm.updateSel { it.copy(unitMix = mix + (k to (mix[k] ?: 0) + 1)) } })
                            }
                        }
                    }
                }
                i++
            }
            else -> i++
        }
    }
}

@Composable
private fun FieldCell(vm: AppViewModel, f: WizardFieldDef, sel: WizardSelections, modifier: Modifier, step2: Boolean) {
    val ctx = LocalContext.current
    val v = sel.fields[f.label].orEmpty()
    val set: (String) -> Unit = { nv -> vm.updateSel { it.copy(fields = it.fields + (f.label to nv)) } }
    Column(modifier) {
        FieldLabel(f.label)
        when (f.type) {
            "date" -> PickerField(if (v.isBlank()) "" else Fmt.date(v), "Select date", VIcons.calendar, { pickDate(ctx, v, set) })
            "time" -> PickerField(if (v.isBlank()) "" else Fmt.time(v), "Select time", VIcons.clock, { pickTime(ctx, v, set) })
            "textarea" -> VInput(v, set, placeholder = f.placeholder.orEmpty(), multiline = true)
            else -> VInput(v, set, placeholder = f.placeholder.orEmpty(), keyboard = keyboardFor(f, step2),
                caps = if (f.label.contains("name", true) || f.label.contains("address", true)) KeyboardCapitalization.Words else KeyboardCapitalization.None)
        }
    }
}
