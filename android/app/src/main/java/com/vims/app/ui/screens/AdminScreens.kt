package com.vims.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.data.ItemDef
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.EditSecR
import com.vims.app.ui.back
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.ChipFlow
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.SingleChips
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VInput
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.dashedBorder
import com.vims.app.ui.components.vCard
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Checks
import com.vims.app.util.Filters
import com.vims.app.util.Fmt
import com.vims.app.util.formField
import com.vims.app.util.rememberForm
import kotlinx.coroutines.launch

private fun groupIcon(g: String): ImageVector = when (g) {
    "Testing" -> VIcons.flask; "Utility" -> VIcons.bolt; "State & Insurance Forms" -> VIcons.file; "Interior" -> VIcons.sofa; "Phase Inspections" -> VIcons.layers; else -> VIcons.tree
}

@Composable
fun AddBox(content: @Composable () -> Unit) {
    Column(Modifier.padding(bottom = 14.dp).fillMaxWidth().clip(RoundedCornerShape(13.dp)).background(V.paper).dashedBorder(V.brand, 13.dp).padding(14.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) { content() }
}

@Composable
fun AdminScreen(vm: AppViewModel, nav: NavHostController) {
    val engine by vm.engine.collectAsState()
    var name by rememberSaveable { mutableStateOf("") }
    var group by rememberSaveable { mutableStateOf("Exterior") }
    val open = remember { mutableStateMapOf(engine.adminGroups.firstOrNull()?.first.orEmpty() to true) }
    val form = rememberForm()
    VScreen("Manage checklist", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Hint("Add and edit checklist sections and items yourself — changes apply to new inspections.", Modifier.padding(top = 2.dp, bottom = 12.dp))
        AddBox {
            val nameErr = form.check("name", name) { Checks.sectionName(name) { n -> engine.def(n) != null } }
            VInput(name, { name = it }, Modifier.formField(form, "name"), placeholder = "New section name (e.g. Solar Panels)", textSize = 14f, filter = Filters::sectionName, error = nameErr)
            SingleChips(listOf("Exterior", "Interior", "Utility", "Testing"), group, { if (it != null) group = it }, required = true)
            VBtn("Add section", {
                val n = name.trim()
                if (form.submit() && vm.addCustomSection(n, group)) { name = ""; form.reset(); nav.navigate(EditSecR(n)) }
            }, icon = VIcons.plus, minHeight = 48.dp)
        }
        engine.adminGroups.forEach { (g, names) ->
            val isOpen = open[g] == true
            Column(Modifier.padding(bottom = 10.dp).fillMaxWidth().vCard()) {
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button) { open[g] = !isOpen }.padding(horizontal = 15.dp, vertical = 13.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(11.dp),
                ) {
                    Box(Modifier.size(30.dp).clip(RoundedCornerShape(8.dp)).background(V.paper3), contentAlignment = Alignment.Center) { Icon(groupIcon(g), null, tint = V.brand, modifier = Modifier.size(17.dp)) }
                    Text(g, style = T.ui(14.5.sp, FontWeight.Bold), modifier = Modifier.weight(1f))
                    Text("${names.size}", style = T.mono(11.sp, color = V.ink3))
                    Icon(VIcons.chevDown, null, tint = V.ink3, modifier = Modifier.padding(start = 8.dp).size(18.dp).rotate(if (isOpen) 180f else 0f))
                }
                if (isOpen) names.forEach { n ->
                    Box(Modifier.fillMaxWidth().height(1.dp).background(V.line2))
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button) { nav.navigate(EditSecR(n)) }.padding(start = 18.dp, end = 15.dp, top = 12.dp, bottom = 12.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        Text(n, style = T.ui(14.sp, FontWeight.Medium), modifier = Modifier.weight(1f))
                        Text("${engine.def(n)?.items?.count { it.q != null } ?: 0} items", style = T.mono(10.5.sp, FontWeight.SemiBold, V.ink2))
                        Icon(VIcons.chevRight, null, tint = V.chev, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }
}

private class DraftItem(val id: Long, val item: ItemDef)

@Composable
fun EditSectionScreen(vm: AppViewModel, nav: NavHostController, name: String) {
    val engine by vm.engine.collectAsState()
    val def = engine.def(name)
    var high by rememberSaveable { mutableStateOf(false) }
    var seq by remember { mutableStateOf(0L) }
    val draft = remember(name, high) {
        mutableStateListOf<DraftItem>().apply {
            val src = if (high) def?.itemsHigh ?: def?.items.orEmpty() else def?.items.orEmpty()
            src.forEach { add(DraftItem(seq++, it)) }
        }
    }
    fun update(i: Int, f: (ItemDef) -> ItemDef) { draft[i] = DraftItem(draft[i].id, f(draft[i].item)) }
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var showErrors by remember { mutableStateOf(false) }

    VScreen(name, companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav)), scroll = false) {
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 34.dp)) {
            item(key = "tier") {
                Column {
                    if (def?.form == null) {
                        Text("Checklist tier", style = T.ui(12.5.sp, FontWeight.SemiBold, V.ink2), modifier = Modifier.padding(bottom = 7.dp))
                        SingleChips(listOf("Standard", "High Detail"), if (high) "High Detail" else "Standard", { v -> if (v != null) high = v == "High Detail" }, required = true)
                    } else {
                        Text("${vm.config.formLabels[def.form] ?: "State form"} — the same items print at every checklist depth.", style = T.ui(12.sp, color = V.ink3))
                    }
                    if (def?.photosOnly == true) Text("Picture page — photo categories only, no checklist items.", style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(top = 6.dp))
                    if (high && def?.itemsHigh == null) Text("This section has no separate High Detail list yet — saving creates one from these items.", style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(top = 8.dp))
                    Lbl("Checklist items · $name")
                }
            }
            itemsIndexed(draft, key = { _, d -> d.id }) { i, d ->
                EdItem(d.item, i, draft.size, showErrors,
                    onChange = { v -> update(i) { if (it.isHeader) it.copy(header = v) else it.copy(q = v) } },
                    onUp = { if (i > 0) { val x = draft.removeAt(i); draft.add(i - 1, x) } },
                    onDown = { if (i < draft.size - 1) { val x = draft.removeAt(i); draft.add(i + 1, x) } },
                    onDelete = { draft.removeAt(i) },
                    onRemoveOpt = { oi -> update(i) { it.copy(options = it.options.orEmpty().filterIndexed { k, _ -> k != oi }) } },
                    onAddOpt = { o -> update(i) { it.copy(options = it.options.orEmpty() + o) } },
                )
            }
            item(key = "actions") {
                Column {
                    VBtn("Add item", { draft.add(DraftItem(seq++, ItemDef(q = "New item", type = "single", options = listOf("Yes", "No", "N/A")))) }, kind = BtnKind.Ghost, icon = VIcons.plus)
                    VBtn("Save & done", {
                        // Every question / header needs text; scroll to the first empty one.
                        val bad = draft.indexOfFirst { d -> (d.item.header ?: d.item.q).orEmpty().isBlank() }
                        if (bad >= 0) { showErrors = true; scope.launch { listState.animateScrollToItem(bad + 1) }; vm.toast("Fill in the highlighted item") }
                        else { vm.saveSectionItems(name, high, draft.map { it.item }); nav.back() }
                    }, Modifier.padding(top = 10.dp), icon = VIcons.check)
                }
            }
        }
    }
}

@Composable
private fun EdItem(it: ItemDef, index: Int, count: Int, showErrors: Boolean, onChange: (String) -> Unit, onUp: () -> Unit, onDown: () -> Unit, onDelete: () -> Unit, onRemoveOpt: (Int) -> Unit, onAddOpt: (String) -> Unit) {
    var newOpt by remember { mutableStateOf("") }
    var optErr by remember { mutableStateOf<String?>(null) }
    val text = it.header ?: it.q.orEmpty()
    val textErr = if (showErrors && text.isBlank()) (if (it.isHeader) "Enter the header text" else Checks.question(text)) else null
    Column(Modifier.padding(bottom = 11.dp).fillMaxWidth().vCard(13.dp, bg = if (it.isHeader) V.brand.copy(alpha = .06f) else V.paper).padding(horizontal = 14.dp, vertical = 13.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Column(Modifier.weight(1f)) {
                if (it.isHeader) Text("SUB-SECTION HEADER", style = T.mono(9.5.sp, FontWeight.SemiBold, V.brandDeep))
                BasicTextField(
                    text, { v -> onChange(Filters.question(v)) }, singleLine = true, textStyle = T.ui(14.5.sp, FontWeight.SemiBold, V.ink), cursorBrush = SolidColor(V.brand),
                    modifier = Modifier.fillMaxWidth(),
                    decorationBox = { inner -> Column { Box(Modifier.padding(vertical = 5.dp)) { inner() }; Box(Modifier.fillMaxWidth().height(1.5.dp).background(if (textErr != null) V.c1 else V.line)) } },
                )
                com.vims.app.ui.components.FieldError(textErr)
            }
            EdBtn(VIcons.chevUp, "Move up", index > 0, onUp)
            EdBtn(VIcons.chevDown, "Move down", index < count - 1, onDown)
            EdBtn(VIcons.trash, "Delete item", true, onDelete)
        }
        if (!it.isHeader) {
            if (it.isChoice) {
                ChipFlow(Modifier.padding(top = 10.dp)) {
                    it.options.orEmpty().forEachIndexed { oi, o ->
                        Row(Modifier.clip(RoundedCornerShape(16.dp)).background(V.paper3).padding(start = 12.dp, end = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(o, style = T.ui(12.5.sp, color = V.ink2))
                            Box(Modifier.size(34.dp).clickable(role = Role.Button, onClickLabel = "Remove option $o") { onRemoveOpt(oi) }, contentAlignment = Alignment.Center) {
                                Text("×", style = T.ui(16.sp, color = V.ink3))
                            }
                        }
                    }
                }
                Row(Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(7.dp), verticalAlignment = Alignment.CenterVertically) {
                    VInput(newOpt, { newOpt = it; optErr = null }, Modifier.weight(1f), placeholder = "Add option…", minHeight = 44.dp, textSize = 13f, filter = Filters::option)
                    Box(
                        Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(9.dp)).background(V.brand).clickable(role = Role.Button) {
                            optErr = Checks.option(newOpt, it.options.orEmpty())
                            if (optErr == null) { onAddOpt(newOpt.trim()); newOpt = "" }
                        }.padding(horizontal = 15.dp),
                        contentAlignment = Alignment.Center,
                    ) { Text("Add", style = T.ui(14.sp, FontWeight.SemiBold, Color.White)) }
                }
                com.vims.app.ui.components.FieldError(optErr)
            } else {
                Text("${when (it.type) { "num" -> "Number"; "date" -> "Date"; "time" -> "Time"; else -> "Text" }} input", style = T.mono(11.sp, color = V.ink3), modifier = Modifier.padding(top = 8.dp))
            }
        }
    }
}

@Composable
private fun EdBtn(icon: ImageVector, label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(
        Modifier.size(40.dp).clip(RoundedCornerShape(8.dp)).background(V.paper2).border(1.dp, V.line, RoundedCornerShape(8.dp)).clickable(enabled = enabled, role = Role.Button, onClickLabel = label, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, label, tint = if (enabled) V.ink3 else V.line, modifier = Modifier.size(15.dp)) }
}

/** Price input that commits on Done / focus loss (like the prototype's onchange). */
@Composable
fun PriceField(value: Double, onCommit: (Double) -> Unit, modifier: Modifier = Modifier, onError: (String?) -> Unit = {}) {
    var text by remember(value) { mutableStateOf(Fmt.price(value)) }
    var bad by remember { mutableStateOf(false) }
    fun commit() { val e = Checks.price(text); bad = e != null; onError(e); if (e == null) { val v = text.toDouble(); if (v != value) onCommit(v) } }
    BasicTextField(
        text, { text = Filters.price(it); if (bad) { val e = Checks.price(text); bad = e != null; onError(e) } }, singleLine = true, textStyle = T.ui(15.sp, color = V.ink), cursorBrush = SolidColor(V.brand),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { commit() }),
        modifier = modifier.width(130.dp).onFocusChanged { if (!it.isFocused) commit() },
        decorationBox = { inner -> Box(Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(11.dp)).background(V.paper).border(if (bad) 1.5.dp else 1.dp, if (bad) V.c1 else V.line, RoundedCornerShape(11.dp)).padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) { inner() } },
    )
}

@Composable
fun PlansAdminScreen(vm: AppViewModel, nav: NavHostController) {
    val account by vm.account.collectAsState()
    var n by rememberSaveable { mutableStateOf("") }
    var p by rememberSaveable { mutableStateOf("") }
    var d by rememberSaveable { mutableStateOf("") }
    val form = rememberForm()
    VScreen("Plans & pricing", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Hint("Owner admin — edit plan prices, add a plan, or set the per-inspector rate. Changes apply to the subscribe screen.", Modifier.padding(top = 2.dp, bottom = 12.dp))
        account.plans.forEach { plan ->
            PlanCard(plan.name, plan.price, plan.unit ?: "/mo", plan.desc) { vm.setPlanPrice(plan.id, it) }
        }
        PlanCard("Additional inspector", account.extraInspectorMonthly, "/mo each", null) { vm.setExtraRate(it) }
        AddBox {
            val nErr = form.check("n", n) { Checks.required(n, "Enter a plan name") }
            val pErr = form.check("p", p) { Checks.price(p) }
            VInput(n, { n = it }, Modifier.formField(form, "n"), placeholder = "Plan name (e.g. Team)", textSize = 14f, filter = { Filters.base(it, 40) }, error = nErr)
            VInput(p, { p = it }, Modifier.formField(form, "p"), placeholder = "Monthly price (e.g. 99.00)", keyboard = KeyboardType.Decimal, textSize = 14f, filter = Filters::price, error = pErr)
            VInput(d, { d = it }, placeholder = "Short description", textSize = 14f, filter = { Filters.base(it, 80) })
            VBtn("Add plan", { if (form.submit() && vm.addPlan(n, p, d)) { n = ""; p = ""; d = ""; form.reset() } }, icon = VIcons.plus, minHeight = 48.dp)
        }
    }
}

@Composable
private fun PlanCard(name: String, price: Double, unit: String, desc: String?, onCommit: (Double) -> Unit) {
    var err by remember { mutableStateOf<String?>(null) }
    Column(Modifier.padding(bottom = 11.dp).fillMaxWidth().vCard(13.dp).padding(horizontal = 14.dp, vertical = 13.dp)) {
        Text(name, style = T.ui(14.5.sp, FontWeight.Bold), modifier = Modifier.padding(bottom = 10.dp))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Price $", style = T.ui(13.sp, color = V.ink2))
            PriceField(price, onCommit, onError = { err = it })
            Text(unit, style = T.ui(12.5.sp, color = V.ink3))
        }
        com.vims.app.ui.components.FieldError(err)
        if (desc != null) Text(desc, style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(top = 8.dp))
    }
}
