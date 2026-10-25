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
import androidx.compose.runtime.CompositionLocalProvider
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
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.data.WizardFieldDef
import com.vims.app.data.WizardSelections
import com.vims.app.data.sectionTitle
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.SectionsR
import com.vims.app.ui.WizardR
import com.vims.app.ui.back
import com.vims.app.ui.components.RequiredHint
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.BtnRow
import com.vims.app.ui.components.ChipFlow
import com.vims.app.ui.components.Counter
import com.vims.app.ui.components.FieldLabel
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.LocalNoAutofill
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
import com.vims.app.util.Checks
import com.vims.app.util.Filters
import com.vims.app.util.FormState
import com.vims.app.util.GroupedNumberTransform
import com.vims.app.util.Limits
import com.vims.app.util.Fmt
import com.vims.app.util.PhoneTransform
import com.vims.app.util.formField
import com.vims.app.util.rememberForm

@Composable
fun WizardScreen(vm: AppViewModel, nav: NavHostController, inspId: String?) {
    var started by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        // Client Oct 25: no new inspection once the free look has ended without a subscription (any way into the wizard).
        if (inspId == null && !vm.canStartInspection()) { vm.promptSubscribe(); nav.back(); return@LaunchedEffect }
        if (!started) { vm.startWizard(inspId); started = true }
    }
    val w by vm.wizard.collectAsState()
    val cfg = vm.config.wizard
    val editing = inspId != null

    BackHandler(enabled = w.step > 1) { vm.wizardStep(w.step - 1) }

    var form = rememberForm()
    fun next() {
        // Validate the current step (docs/validation-rules.md) before moving on.
        if (!form.submit()) return
        if (w.step < 4) { vm.wizardStep(w.step + 1); return }
        val id = vm.buildChecklist() ?: return
        if (editing) nav.back()
        else nav.navigate(SectionsR(id)) { popUpTo<WizardR> { inclusive = true } }
    }

    // Wizard fields hold the client's / agent's / property's details, never the phone owner's: no Android Autofill here
    // (an autofill pick filled Client email AND Inspection address from the owner's saved profile).
    CompositionLocalProvider(LocalNoAutofill provides true) { key(w.step) {
        form = rememberForm()
        VScreen(
            if (editing) "Inspection info" else "New inspection",
            if (editing) w.sel.street.ifBlank { companyName(vm) } else companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav)),
        ) {
            StepsBar(w.step)
            when (w.step) {
                1 -> {
                    Lbl(cfg.steps.getOrElse(0) { "Client & inspection" }, first = true)
                    RequiredHint()
                    WizardFields(vm, nav, cfg.step1, w.sel, form = form)
                }
                2 -> WizardFields(vm, nav, cfg.step2, w.sel, step2 = true, form = form)
                3 -> {
                    // Client Oct 25 (`wizard.areasLockedTypes`): Phase 1 / Phase 2 / Tests Only / 4 Point don't use the exterior,
                    // interior room or utility options — shown disabled under one short note; the room counts stay editable.
                    // The earlier choices are kept (another type unlocks them as they were) but add no sections while locked.
                    val locked = cfg.areasLocked(w.sel.inspType)
                    Hint("Choose every area to inspect — add or remove anything. This builds the checklist.", Modifier.padding(top = 2.dp, bottom = if (locked) 8.dp else 12.dp))
                    if (locked) com.vims.app.ui.components.LockedNote("Exterior, room and utility areas aren't used for a ${inspectionNoun(w.sel.inspType)}.", Modifier.padding(bottom = 12.dp))
                    Lbl("Exterior areas", first = true)
                    MultiChips(cfg.exteriorOptions, w.sel.exterior, { o -> vm.updateSel { it.copy(exterior = it.exterior.toggle(o)) } }, label = ::sectionTitle, enabled = !locked)
                    Lbl("Room counts")
                    cfg.roomCounts.forEach { rc ->
                        Counter(rc.label, w.sel.count(rc.key),
                            onMinus = { vm.updateSel { it.copy(counts = it.counts + (rc.key to (it.count(rc.key) - 1).coerceAtLeast(0))) } },
                            onPlus = { vm.updateSel { it.copy(counts = it.counts + (rc.key to (it.count(rc.key) + 1).coerceAtMost(Limits.COUNT_MAX))) } },
                            max = Limits.COUNT_MAX)
                    }
                    Lbl("Interior rooms")
                    MultiChips(cfg.roomOptions, w.sel.rooms, { o -> vm.updateSel { it.copy(rooms = it.rooms.toggle(o)) } }, enabled = !locked)
                    Lbl("Utility & systems")
                    MultiChips(cfg.utilityOptions, w.sel.utilOpt, { o -> vm.updateSel { it.copy(utilOpt = it.utilOpt.toggle(o)) } }, label = ::sectionTitle, enabled = !locked)
                }
                else -> {
                    Hint("Add any secondary testing for this inspection.", Modifier.padding(top = 2.dp, bottom = 12.dp))
                    MultiChips(cfg.testOptions, w.sel.tests, { o -> vm.updateSel { it.copy(tests = it.tests.toggle(o)) } }, label = ::sectionTitle)
                }
            }
            BtnRow(Modifier.padding(top = 10.dp)) {
                VBtn("Back", { vm.wizardStep(w.step - 1) }, Modifier.weight(1f).alpha(if (w.step == 1) 0f else 1f), BtnKind.Ghost, enabled = w.step > 1)
                VBtn(if (w.step == 4) (if (editing) "Update checklist" else "Build checklist") else "Next", { next() }, Modifier.weight(1f), icon = if (w.step == 4) VIcons.arrowRight else null)
            }
        }
    } }
}

private fun List<String>.toggle(o: String) = if (o in this) this - o else this + o

/** "Tests Only" → "Tests Only inspection"; "4 Point Inspection" stays as it is. */
private fun inspectionNoun(type: String) = if (type.endsWith("inspection", ignoreCase = true)) type else "$type inspection"

/** Form key of the required Type of inspection chips (step 1). */
private const val TYPE_KEY = "Type of inspection"

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
    // Valuation takes cents (team QA Oct 22: at most 2 decimals); Total sq ft stays whole numbers (number pad).
    f.label.startsWith("Valuation") -> KeyboardType.Decimal
    f.label.startsWith("Temperature") -> KeyboardType.Decimal
    step2 -> KeyboardType.Number
    else -> KeyboardType.Text
}

/** Renders a wizard step from `wizard.step1` / `wizard.step2` in vims-checklists.json. */
@Composable
private fun WizardFields(vm: AppViewModel, nav: NavHostController, defs: List<WizardFieldDef>, sel: WizardSelections, step2: Boolean = false, form: FormState) {
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
                    com.vims.app.ui.components.FieldPair(Modifier.padding(bottom = 11.dp),
                        first = { m -> FieldCell(vm, f, sel, m, step2, form) }, second = { m -> FieldCell(vm, pair, sel, m, step2, form) })
                    i += 2; continue
                }
                if (f.label.startsWith("Temperature") && nextDef?.kind == "chips") {
                    // Prototype layout: "Weather & site conditions" label, a narrow temperature field, then the weather chips.
                    Lbl(nextDef.label)
                    Column(Modifier.padding(bottom = 11.dp)) {
                        FieldLabel(f.label)
                        val tv = sel.fields[f.label].orEmpty()
                        val terr = form.check(f.label, tv) { Checks.temperature(tv) }
                        // QA Oct 14: decimals (72.5) and a leading "-" are allowed; −60 to 140 °F.
                        VInput(tv, { v -> vm.updateSel { it.copy(fields = it.fields + (f.label to v)) } }, Modifier.width(if (terr != null) 300.dp else 120.dp).formField(form, f.label),
                            placeholder = f.placeholder.orEmpty(), keyboard = KeyboardType.Decimal, filter = Filters::temperature, error = terr, imeAction = ImeAction.Next)
                    }
                    SingleChips(nextDef.options.orEmpty(), sel.chip(nextDef.label), { v -> vm.updateSel { it.copy(chips = it.chips + (nextDef.label to v.orEmpty())) } }, modifier = Modifier.padding(bottom = 14.dp))
                    i += 2; continue
                }
                Column(Modifier.padding(bottom = 13.dp)) {
                    FieldCell(vm, f, sel, Modifier, step2, form)
                }
                // Client Oct 17: Inspection address (street) → City → State (data v1.3, + state rules) → ZIP code.
                if (f.label == WizardSelections.F_ADDRESS && !step2) {
                    Column(Modifier.padding(bottom = 13.dp)) { FieldCell(vm, cityDef, sel, Modifier, false, form) }
                    StateField(vm, nav, sel, form) {
                        Column(Modifier.padding(bottom = 13.dp)) { FieldCell(vm, zipDef, sel, Modifier, false, form) }
                    }
                }
                if (f.label == WizardSelections.F_AGENT_EMAIL) {
                    SendToAgentCheck(vm, sel)
                    Text("Client & agent emails are used to send the finished report.", style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, end = 2.dp, top = 0.dp, bottom = 12.dp))
                }
                i++
            }
            "chips" -> {
                val selected = sel.chip(f.label)
                when {
                    f.options == listOf("Yes", "No", "Unknown") -> {
                        // Small phones / large text: the label goes above the chips instead of wrapping word by word.
                        com.vims.app.ui.components.InlineOrStacked(Modifier.padding(bottom = 9.dp).fillMaxWidth().vCard(12.dp).padding(horizontal = 14.dp, vertical = 10.dp),
                            label = { Text(f.label, style = T.ui(14.5.sp, FontWeight.Bold)) },
                        ) {
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
                            VInput(sel.storiesOther, { v -> vm.updateSel { it.copy(storiesOther = v) } }, Modifier.padding(top = 10.dp), filter = { Filters.base(it, 300, multiline = true) },
                                placeholder = "Describe what 'other' consists of (e.g. split-level, loft, partial third story)…", multiline = true)
                        }
                    }
                }
                i++
            }
            "dynamic" -> {
                // Data v1.9.1 (team QA Oct 22): nothing is preselected and Type of inspection is required ("required": true).
                val typeErr = if (f.id == "wtype") form.check(TYPE_KEY, sel.inspType) { if (sel.inspType.isBlank()) "Select the type of inspection" else null } else null
                Lbl(f.label, first = step2 && i == 0, required = f.required, modifier = if (f.id == "wtype") Modifier.formField(form, TYPE_KEY) else Modifier)
                when (f.id) {
                    "wtype" -> {
                        // Client Oct 25: tapping the selected type again deselects it (still required: Next shows the message above).
                        // Retired types ("Code") are only offered back to an inspection that was saved with one.
                        val savedType = vm.wizard.collectAsState().value.editingId?.let { vm.bundle(it)?.inspection?.selections?.inspType }
                        SingleChips(cfg.typeOptions(savedType), sel.inspType.ifBlank { null }, { v -> vm.updateSel { it.copy(inspType = v.orEmpty()) } })
                        com.vims.app.ui.components.FieldError(typeErr)
                        if (sel.inspType == "Component") {
                            Lbl("Component(s) to inspect")
                            MultiChips(cfg.componentOptions, sel.component, { o -> vm.updateSel { it.copy(component = it.component.toggle(o)) } })
                        }
                        // Texas (TREC REI 7-6) asks for a sponsor; the 4-Point form asks for the insured and policy #.
                        val typeFields = cfg.typeFieldsFor(sel.inspType)
                        if (typeFields.isNotEmpty()) {
                            Lbl(typeFieldsTitle(sel.inspType))
                            typeFields.forEach { tf ->
                                Column(Modifier.padding(bottom = 13.dp)) {
                                    FieldLabel(tf.label)
                                    VInput(sel.fields[tf.key].orEmpty(), { v -> vm.updateSel { it.copy(fields = it.fields + (tf.key to v)) } },
                                        filter = wizardFilter(tf.key),
                                        placeholder = typeFieldPlaceholder(tf.key, tf.label),
                                        caps = if (tf.key.contains("name", true)) KeyboardCapitalization.Words else KeyboardCapitalization.None, imeAction = ImeAction.Next)
                                }
                            }
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
                                    onPlus = { vm.updateSel { it.copy(unitMix = mix + (k to ((mix[k] ?: 0) + 1).coerceAtMost(Limits.COUNT_MAX))) } },
                                    max = Limits.COUNT_MAX)
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
private fun FieldCell(vm: AppViewModel, f: WizardFieldDef, sel: WizardSelections, modifier: Modifier, step2: Boolean, form: FormState) {
    val ctx = LocalContext.current
    val v = sel.fields[f.label].orEmpty()
    val set: (String) -> Unit = { nv -> vm.updateSel { it.copy(fields = it.fields + (f.label to nv)) } }
    // Inspection date: today or later for new inspections; an edited inspection keeps its saved date valid.
    val w = vm.wizard.collectAsState().value
    val savedDate = w.editingId?.let { vm.bundle(it)?.inspection?.selections?.date }?.let { Fmt.parseDate(it) }
    val minDate = listOfNotNull(java.time.LocalDate.now(), savedDate).minOrNull()!!
    val err = form.check(f.label, v) {
        wizardCheck(f.label, v) ?: if (f.label == WizardSelections.F_DATE && Fmt.parseDate(v)?.isBefore(minDate) == true) "Choose today or a later date" else null
    }
    Column(modifier.formField(form, f.label)) {
        FieldLabel(f.label, required = isWizardRequired(f.label))
        when (f.type) {
            "date" -> PickerField(if (v.isBlank()) "" else Fmt.date(v), "Select date", VIcons.calendar, { pickDate(ctx, v, minDate, set) }, error = err)
            "time" -> PickerField(if (v.isBlank()) "" else Fmt.time(v), "Select time", VIcons.clock, { pickTime(ctx, v, set) }, error = err)
            "textarea" -> VInput(v, set, placeholder = f.placeholder.orEmpty(), multiline = true, filter = { Filters.base(it, 1000, multiline = true) }, error = err)
            else -> VInput(v, set, placeholder = placeholderFor(f), keyboard = if (f.label == WizardSelections.F_ZIP) KeyboardType.Number else keyboardFor(f, step2), error = err, filter = wizardFilter(f.label),
                visual = if (f.type == "tel") PhoneTransform else if (f.label in groupedFields) GroupedNumberTransform else androidx.compose.ui.text.input.VisualTransformation.None,
                caps = if (f.label.contains("name", true) || f.label.contains("address", true) || f.label == WizardSelections.F_CITY) KeyboardCapitalization.Words else KeyboardCapitalization.None,
                // Team QA Oct 22: "2450.5" must never become "24505" — the "." and the digits after it are rejected.
                wholeNumberMax = if (f.label == "Total sq ft") Limits.SQFT_MAX else null,
                // Keyboard "Next" walks the form in order (Inspection address → State → Real estate agent name → …).
                imeAction = ImeAction.Next)
        }
    }
}

/** Client Oct 17: Inspection address is the street only (City, State and ZIP code have their own fields), as in the prototype. */
private fun placeholderFor(f: WizardFieldDef): String = if (f.label == WizardSelections.F_ADDRESS) "Street address" else f.placeholder.orEmpty()

/** The two address fields the shared wizard.step1 doesn't list (client Oct 17, prototype f887cf8). */
private val cityDef = WizardFieldDef(kind = "field", label = WizardSelections.F_CITY, type = "text", placeholder = "City")
private val zipDef = WizardFieldDef(kind = "field", label = WizardSelections.F_ZIP, type = "text", placeholder = "84015")

/** Shown with grouping commas ("450,000") while the stored value is digits. */
private val groupedFields = setOf("Valuation ($)", "Total sq ft")

/** While-typing filters for wizard fields (by JSON label / typeField key) — docs/validation-rules.md. */
private fun wizardFilter(key: String): ((String) -> String)? = when (key) {
    WizardSelections.F_CLIENT, WizardSelections.F_AGENT, "sponsorName", "insuredName" -> Filters::personName
    WizardSelections.F_CLIENT_PHONE -> Filters::phone
    WizardSelections.F_ADDRESS -> Filters::address
    WizardSelections.F_CITY -> Filters::city
    WizardSelections.F_ZIP -> Filters::zip
    WizardSelections.F_LICENSE, "sponsorLicense" -> Filters::license
    "policyNumber" -> Filters::policy
    "Year of construction" -> Filters::year
    // Team QA Oct 22: Total sq ft whole numbers only; Valuation and Lot size at most 2 decimals; nothing past the max.
    "Valuation ($)" -> { v -> Filters.number(v, 2, Limits.VALUATION_MAX) }
    "Total sq ft" -> { v -> Filters.number(v, 0, Limits.SQFT_MAX) }
    "Lot size (acres)" -> { v -> Filters.number(v, 2, Limits.LOT_MAX) }
    "Temperature (°F)" -> Filters::temperature
    else -> null
}

/** On-submit checks for wizard fields. */
/** Required = the field's own validation rejects an empty value (same rules as [wizardCheck]). */
private fun isWizardRequired(label: String) = wizardCheck(label, "") != null

private fun wizardCheck(label: String, v: String): String? = when (label) {
    WizardSelections.F_CLIENT -> Checks.required(v, "Enter the client's name")
    WizardSelections.F_ADDRESS -> Checks.required(v, "Enter the street address")
    WizardSelections.F_CITY -> Checks.required(v, "Enter the city")
    WizardSelections.F_ZIP -> Checks.zip(v)
    WizardSelections.F_DATE -> Checks.required(v, "Choose the inspection date")
    WizardSelections.F_CLIENT_PHONE -> Checks.phone(v)
    WizardSelections.F_CLIENT_EMAIL, WizardSelections.F_AGENT_EMAIL -> Checks.email(v, required = false)
    "Year of construction" -> Checks.year(v)
    // Number limits (docs/validation-rules.md): > 0 and at most the max; "450,000" / "$450,000" read as 450000.
    "Total sq ft" -> Checks.positive(v, "a square footage", Limits.SQFT_MAX)
        ?: if (com.vims.app.util.Num.parse(v)?.let { it != Math.floor(it) } == true) "Enter a whole number of square feet" else null
    "Valuation ($)" -> Checks.positive(v, "a valuation", Limits.VALUATION_MAX)
    "Lot size (acres)" -> Checks.positive(v, "a lot size", Limits.LOT_MAX)
    else -> null
}

private fun typeFieldsTitle(type: String) = when (type) { "Texas" -> "Texas TREC form"; "4 Point Inspection" -> "4-Point form"; else -> type }

private fun typeFieldPlaceholder(key: String, label: String) = when (key) {
    "sponsorName" -> "Sponsor name"
    "sponsorLicense" -> "TREC license #"
    "insuredName" -> "Name on the insurance application"
    "policyNumber" -> "Policy or application number"
    else -> label
}
