package com.vims.app.ui.screens

import com.vims.app.data.sectionTitle
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
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
import androidx.compose.ui.draw.alpha
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
import androidx.compose.ui.unit.em
import androidx.navigation.NavHostController
import com.vims.app.data.ItemDef
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.components.keepsKeyboard
import com.vims.app.ui.EditSecR
import com.vims.app.ui.back
import com.vims.app.ui.components.FieldLabel
import com.vims.app.ui.components.VField
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
    // Client Oct 28: Restore entire checklist to original (confirmed first).
    var askRestoreAll by rememberSaveable { mutableStateOf(false) }
    if (askRestoreAll) {
        val added = engine.edits.custom.size
        val edited = engine.edits.overrides.keys.count { engine.isEdited(it) }
        val parts = listOfNotNull(
            if (edited > 0) "your changes to **$edited section${if (edited == 1) "" else "s"}** (renamed, added and removed items)" else null,
            if (added > 0) "the **$added section${if (added == 1) "" else "s"}** your company added" else null,
        ).joinToString(" and ")
        com.vims.app.ui.components.ConfirmDialog(
            "Restore the entire checklist to the original?",
            "This removes $parts, and every section goes back to the VIMS default. Inspections already started keep their saved checklist. This can't be undone.",
            "Restore all", onConfirm = { vm.restoreChecklist(); askRestoreAll = false }, onDismiss = { askRestoreAll = false }, danger = true,
        )
    }
    // Client Oct 28 (2nd email) — "Restore selected checklists" (each section is one checklist): pick from the Edited / Added
    // sections (1 = picker), then one confirm naming them (2).
    val changed = engine.adminGroups.flatMap { it.second }.distinct().filter { engine.isEdited(it) || engine.isCustom(it) }
    var pickStage by rememberSaveable { mutableStateOf(0) }
    var picked by rememberSaveable { mutableStateOf(listOf<String>()) }
    val chosen = changed.filter { it in picked } // in Manage checklist order; drops anything restored meanwhile
    if (pickStage == 1) com.vims.app.ui.components.ConfirmDialog(
        "Restore selected checklists",
        "Choose the checklists to restore to the VIMS original. Only checklists your company edited or added are listed.",
        if (chosen.isEmpty()) "Restore" else "Restore ${chosen.size}", confirmEnabled = chosen.isNotEmpty(),
        onConfirm = { pickStage = 2 }, onDismiss = { pickStage = 0 },
    ) {
        val all = chosen.size == changed.size && changed.isNotEmpty()
        PickRow(all, { picked = if (all) emptyList() else changed }) {
            Text("Select all (${changed.size})", style = T.ui(14.sp, FontWeight.Bold), modifier = Modifier.weight(1f))
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(V.line2))
        changed.forEach { n ->
            val on = n in chosen
            PickRow(on, { picked = if (on) picked - n else picked + n }) {
                Text(sectionTitle(n), style = T.ui(14.sp, FontWeight.Medium), modifier = Modifier.weight(1f))
                EditTag(if (engine.isCustom(n)) "Added" else "Edited")
            }
        }
        Box(Modifier.height(10.dp))
    }
    if (pickStage == 2 && chosen.isNotEmpty()) {
        run {
            val addedNames = chosen.filter { engine.isCustom(it) }
            val editedNames = chosen - addedNames.toSet()
            fun names(l: List<String>) = l.map { "**${sectionTitle(it)}**" }.let { if (it.size <= 1) it.joinToString() else it.dropLast(1).joinToString(", ") + " and " + it.last() }
            val n = chosen.size
            com.vims.app.ui.components.ConfirmDialog(
                "Restore $n checklist${if (n == 1) "" else "s"}?",
                listOfNotNull(
                    if (editedNames.isEmpty()) null else "${names(editedNames)} go${if (editedNames.size == 1) "es" else ""} back to the VIMS original — your company's renamed, added and removed items are dropped.",
                    if (addedNames.isEmpty()) null else "Added section${if (addedNames.size == 1) "" else "s"} ${if (addedNames.size == 1) "is" else "are"} removed: ${names(addedNames)}.",
                    "Inspections already started keep their saved checklist. This can't be undone.",
                ).joinToString(" "),
                "Restore $n", danger = true, onDismiss = { pickStage = 1 },
                onConfirm = { vm.restoreSections(chosen); picked = emptyList(); pickStage = 0 },
            )
        }
    }
    VScreen("Manage checklist", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Hint("Add and edit checklist sections and items yourself — changes apply to new inspections.", Modifier.padding(top = 2.dp, bottom = 12.dp))
        // Client Oct 28 (2nd email): the Restore block sits at the TOP, in the client's words.
        Column(Modifier.padding(bottom = 14.dp).fillMaxWidth().vCard(13.dp).padding(horizontal = 14.dp, vertical = 13.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Icon(VIcons.undo, null, tint = V.brand, modifier = Modifier.size(17.dp))
                Text("Restore to the VIMS original", style = T.ui(14.sp, FontWeight.Bold), modifier = Modifier.weight(1f))
            }
            // Disabled (nothing edited): dimmed so it reads as unavailable — a ghost button's own disabled look is too faint.
            val dim = if (engine.hasCompanyEdits) Modifier else Modifier.alpha(.45f)
            VBtn("Restore all checklists", { askRestoreAll = true }, dim, kind = BtnKind.GhostDanger, icon = VIcons.undo, enabled = engine.hasCompanyEdits, minHeight = 48.dp)
            VBtn("Restore selected checklists", { picked = emptyList(); pickStage = 1 }, dim, kind = BtnKind.Ghost, icon = VIcons.list, enabled = engine.hasCompanyEdits, minHeight = 48.dp)
            Text(if (engine.hasCompanyEdits) "${changed.size} checklist${if (changed.size == 1) " differs" else "s differ"} from the VIMS original (tagged Edited or Added below). Inspections already started keep their saved checklist."
                else "Your checklist matches the VIMS original — nothing to restore.",
                style = T.ui(12.sp, color = V.ink3, lineHeight = 17.sp), modifier = Modifier.padding(start = 2.dp))
        }
        AddBox {
            val nameErr = form.check("name", name) { Checks.sectionName(name) { n -> engine.def(n) != null } }
            VField("Section name", name, { name = it }, Modifier.formField(form, "name"), placeholder = "e.g. Solar Panels", filter = Filters::sectionName, error = nameErr, required = true, bottom = 0.dp)
            FieldLabel("Group", required = true, modifier = Modifier.padding(top = 4.dp))
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
                        Text(sectionTitle(n), style = T.ui(14.sp, FontWeight.Medium), modifier = Modifier.weight(1f))
                        // Client Oct 28: edited / company-added sections are tagged so "Restore original" is easy to find.
                        if (engine.isEdited(n)) EditTag("Edited") else if (engine.isCustom(n)) EditTag("Added")
                        Text("${engine.def(n)?.items?.count { it.q != null } ?: 0} items", style = T.mono(10.5.sp, FontWeight.SemiBold, V.ink2))
                        Icon(VIcons.chevRight, null, tint = V.chev, modifier = Modifier.size(18.dp))
                    }
                }
            }
        }
    }
}

/** A checkbox row in the Restore selected checklists picker (48dp+ tap target, whole row toggles). */
@Composable
private fun PickRow(checked: Boolean, onToggle: () -> Unit, content: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).clip(RoundedCornerShape(8.dp))
            .toggleable(checked, role = Role.Checkbox) { onToggle() }.padding(horizontal = 4.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val shape = RoundedCornerShape(5.dp)
        Box(
            Modifier.size(22.dp).clip(shape).background(if (checked) V.brand else V.paper).border(1.5.dp, if (checked) V.brand else V.ink3, shape),
            contentAlignment = Alignment.Center,
        ) { if (checked) Icon(VIcons.checkBold, null, tint = Color.White, modifier = Modifier.size(15.dp)) }
        content()
    }
}

/** "Edited" / "Added" tag on a Manage checklist row (client Oct 28). */
@Composable
fun EditTag(text: String) {
    Text(text.uppercase(), style = T.mono(9.5.sp, FontWeight.SemiBold, V.brandDeep, 0.08.em),
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(V.brand.copy(alpha = .12f)).padding(horizontal = 7.dp, vertical = 3.dp))
}

private class DraftItem(val id: Long, val item: ItemDef)

@Composable
fun EditSectionScreen(vm: AppViewModel, nav: NavHostController, name: String) {
    val engine by vm.engine.collectAsState()
    val def = engine.def(name)
    var high by rememberSaveable { mutableStateOf(false) }
    var seq by remember { mutableStateOf(0L) }
    // Re-read from the effective definition when it changes (e.g. after Restore original).
    val draft = remember(name, high, def) {
        mutableStateListOf<DraftItem>().apply {
            val src = if (high) def?.itemsHigh ?: def?.items.orEmpty() else def?.items.orEmpty()
            src.forEach { add(DraftItem(seq++, it)) }
        }
    }
    fun update(i: Int, f: (ItemDef) -> ItemDef) { draft[i] = DraftItem(draft[i].id, f(draft[i].item)) }
    val listState = androidx.compose.foundation.lazy.rememberLazyListState()
    val scope = androidx.compose.runtime.rememberCoroutineScope()
    var showErrors by remember { mutableStateOf(false) }
    // Trash asks first (team QA Oct 13): the item is removed from the draft only after Delete.
    var deleteId by remember { mutableStateOf<Long?>(null) }
    deleteId?.let { id ->
        val d = draft.firstOrNull { it.id == id }
        if (d == null) deleteId = null else {
            val label = (d.item.header ?: d.item.q).orEmpty().trim().ifEmpty { "This item" }
            com.vims.app.ui.components.ConfirmDialog(
                if (d.item.isHeader) "Delete this header?" else "Delete this item?",
                "“$label”${if (d.item.isChoice) " and its options" else ""} will no longer be on new inspections. Inspections already started keep it.",
                "Delete", onConfirm = { draft.removeAll { it.id == id }; deleteId = null }, onDismiss = { deleteId = null }, danger = true,
            )
        }
    }

    // Client Oct 28: Restore original (edited VIMS section) / remove a company-added section — confirmed first.
    val edited = engine.isEdited(name)
    val custom = engine.isCustom(name)
    var askRestore by rememberSaveable { mutableStateOf(false) }
    if (askRestore) com.vims.app.ui.components.ConfirmDialog(
        if (custom) "Remove “${sectionTitle(name)}”?" else "Restore “${sectionTitle(name)}” to the original?",
        if (custom) "This section was added by your company and isn't part of the VIMS checklist, so restoring the original removes it from new inspections. Inspections already started keep their saved checklist."
        else "This removes your company's changes to this section — renamed, added and removed items — and brings back the VIMS default. Inspections already started keep their saved checklist.",
        if (custom) "Remove section" else "Restore original", danger = true, onDismiss = { askRestore = false },
        onConfirm = { askRestore = false; vm.restoreSection(name); if (custom) nav.back() },
    )

    VScreen(sectionTitle(name), companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav)), scroll = false) {
        LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 34.dp)) {
            if (edited || custom) item(key = "restore") {
                Column(Modifier.padding(bottom = 14.dp).fillMaxWidth().vCard(13.dp, bg = V.brand.copy(alpha = .05f)).padding(horizontal = 14.dp, vertical = 13.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        EditTag(if (custom) "Added" else "Edited")
                        Text(if (custom) "Added by your company" else "Changed by your company", style = T.ui(13.5.sp, FontWeight.Bold), modifier = Modifier.weight(1f))
                    }
                    Text(if (custom) "Not part of the VIMS checklist." else "This section differs from the VIMS original.",
                        style = T.ui(12.sp, color = V.ink3, lineHeight = 17.sp), modifier = Modifier.padding(top = 6.dp, bottom = 10.dp))
                    VBtn(if (custom) "Remove section" else "Restore original", { askRestore = true }, kind = BtnKind.GhostDanger, icon = if (custom) VIcons.trash else VIcons.undo, minHeight = 48.dp)
                }
            }
            item(key = "tier") {
                Column {
                    if (def?.form == null) {
                        FieldLabel("Checklist tier")
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
                    onDelete = { deleteId = d.id },
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
                val field = com.vims.app.ui.components.rememberFieldText()
                BasicTextField(
                    field.shown(text), { v -> onChange(field.change(v, Filters::question)) }, singleLine = true, textStyle = T.ui(14.5.sp, FontWeight.SemiBold, V.ink), cursorBrush = SolidColor(V.brand),
                    modifier = Modifier.fillMaxWidth().keepsKeyboard().onFocusChanged { f -> field.focus(f.isFocused, text) },
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
                Text(if (it.isAirReading) "Air reading · level${it.unit?.let { u -> " ($u)" }.orEmpty()} + 1–6 rating" else "${when (it.type) { "num" -> "Number"; "date" -> "Date"; "time" -> "Time"; else -> "Text" }} input", style = T.mono(11.sp, color = V.ink3), modifier = Modifier.padding(top = 8.dp))
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
fun PriceField(value: Double, onCommit: (Double) -> Unit, modifier: Modifier = Modifier, onError: (String?) -> Unit = {}, blankWhenZero: Boolean = false) {
    var text by remember(value) { mutableStateOf(if (blankWhenZero && value == 0.0) "" else Fmt.price(value)) }
    var bad by remember { mutableStateOf(false) }
    fun commit() {
        if (blankWhenZero && text.isBlank()) { bad = false; onError(null); return } // optional and still empty
        val e = Checks.price(text); bad = e != null; onError(e); if (e == null) { val v = com.vims.app.util.Num.parse(text) ?: return; if (v != value) onCommit(v) }
    }
    val field = com.vims.app.ui.components.rememberFieldText()
    BasicTextField(
        field.shown(text), { text = field.change(it, Filters::price); if (bad) { val e = Checks.price(text); bad = e != null; onError(e) } }, singleLine = true, textStyle = T.ui(15.sp, color = V.ink), cursorBrush = SolidColor(V.brand),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal, imeAction = ImeAction.Done), keyboardActions = KeyboardActions(onDone = { commit() }),
        modifier = modifier.width(130.dp).keepsKeyboard().onFocusChanged { field.focus(it.isFocused, text); if (!it.isFocused) commit() },
        decorationBox = { inner -> Box(Modifier.heightIn(min = 48.dp).clip(RoundedCornerShape(11.dp)).background(V.paper).border(if (bad) 1.5.dp else 1.dp, if (bad) V.c1 else V.line, RoundedCornerShape(11.dp)).padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) { inner() } },
    )
}

@Composable
fun PlansAdminScreen(vm: AppViewModel, nav: NavHostController) {
    // Client Oct 28: VIMS plans and prices belong to the master admins (support.platformOwners), not to company admins.
    val session by vm.session.collectAsState()
    if (session?.platformOwner != true) { OwnerOnly(vm, nav, "Plans & pricing"); return }
    val platform by vm.platform.collectAsState()
    val pricing = vm.pricing(platform)
    var n by rememberSaveable { mutableStateOf("") }
    var p by rememberSaveable { mutableStateOf("") }
    var y by rememberSaveable { mutableStateOf("") }
    var d by rememberSaveable { mutableStateOf("") }
    val form = rememberForm()
    var deleteId by rememberSaveable { mutableStateOf<String?>(null) }
    deleteId?.let { id ->
        val plan = pricing.plans.firstOrNull { it.id == id }
        if (plan == null) deleteId = null else {
            val next = pricing.plans.firstOrNull { it.id != id && it.selectable }
            com.vims.app.ui.components.ConfirmDialog(
                "Delete the “${plan.name}” plan?",
                "It will no longer be offered on the Subscription screen of any company." + if (next != null) " Companies on it move to **${next.name}**." else "",
                "Delete", onConfirm = { vm.deletePlan(id); deleteId = null }, onDismiss = { deleteId = null }, danger = true,
            )
        }
    }
    VScreen("Plans & pricing", "Master admin · VIMS", net(vm), backAction(nav), listOf(homeAction(nav))) {
        Hint("Master admin — VIMS subscription plans and prices for **every company**. Edit the monthly and yearly prices, add or delete a plan, or set the additional-inspector rates. Changes apply to the Subscription screen.", Modifier.padding(top = 2.dp, bottom = 12.dp))
        // Delete: at least one plan always stays (no Delete on the last one); the Additional inspector rate isn't a plan.
        val canDelete = pricing.plans.size > 1
        pricing.plans.forEach { plan ->
            PlanCard(plan.name, plan.price, plan.unit ?: "/mo", plan.desc, comingSoon = plan.comingSoon,
                yearly = if (plan.perReport) null else plan.priceYearly, onYearly = if (plan.perReport) null else ({ v -> vm.setPlanYearly(plan.id, v) }),
                onDelete = if (canDelete) ({ deleteId = plan.id }) else null) { vm.setPlanPrice(plan.id, it) }
        }
        // Client Oct 28 (2nd email): the rate isn't a plan — it applies to every plan, so it has no Delete (the card says why).
        PlanCard("Additional inspector", pricing.extraMonthly, "/mo each", "Follows the company's billing period.", yearly = pricing.extra(com.vims.app.data.BillingPeriod.YEARLY),
            onYearly = { vm.setExtraYearly(it) }, note = "Applies to every plan, so it can't be deleted.") { vm.setExtraRate(it) }
        AddBox {
            val nErr = form.check("n", n) { Checks.required(n, "Enter a plan name") }
            val pErr = form.check("p", p) { Checks.price(p) }
            val yErr = form.check("y", y) { if (y.isBlank()) null else Checks.price(y) }
            VField("Plan name", n, { n = it }, Modifier.formField(form, "n"), placeholder = "e.g. Team", filter = { Filters.base(it, 40) }, error = nErr, required = true, bottom = 0.dp)
            VField("Monthly price", p, { p = it }, Modifier.formField(form, "p"), placeholder = "e.g. 99.00", keyboard = KeyboardType.Decimal, filter = Filters::price, error = pErr, required = true, bottom = 0.dp)
            VField("Yearly price (optional)", y, { y = it }, Modifier.formField(form, "y"), placeholder = "e.g. 990.00", keyboard = KeyboardType.Decimal, filter = Filters::price, error = yErr, bottom = 0.dp)
            // QA Oct 14: the short description is multi-line (wraps as typed, line breaks kept) and wraps on the plan cards.
            VField("Description", d, { d = it }, placeholder = "Short description", multiline = true, filter = { Filters.base(it, 200, multiline = true) }, bottom = 0.dp)
            VBtn("Add plan", { if (form.submit() && vm.addPlan(n, p, y, d)) { n = ""; p = ""; y = ""; d = ""; form.reset() } }, icon = VIcons.plus, minHeight = 48.dp)
        }
    }
}

@Composable
private fun PlanCard(name: String, price: Double, unit: String, desc: String?, comingSoon: Boolean = false, yearly: Double? = null, onYearly: ((Double) -> Unit)? = null,
                     onDelete: (() -> Unit)? = null, note: String? = null, onCommit: (Double) -> Unit) {
    var err by remember { mutableStateOf<String?>(null) }
    var yErr by remember { mutableStateOf<String?>(null) }
    Column(Modifier.padding(bottom = 11.dp).fillMaxWidth().vCard(13.dp).padding(horizontal = 14.dp, vertical = 13.dp)) {
        Row(Modifier.padding(bottom = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(name, style = T.ui(14.5.sp, FontWeight.Bold), modifier = Modifier.weight(1f, fill = false))
                if (comingSoon) ComingSoonTag()
            }
            if (onDelete != null) Row(
                Modifier.heightIn(min = 40.dp).clip(RoundedCornerShape(9.dp)).clickable(role = Role.Button, onClickLabel = "Delete plan $name", onClick = onDelete).padding(horizontal = 10.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Icon(VIcons.trash, null, tint = V.c1, modifier = Modifier.size(15.dp))
                Text("Delete", style = T.ui(12.5.sp, FontWeight.SemiBold, V.c1))
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(if (onYearly != null) "Monthly $" else "Price $", style = T.ui(13.sp, color = V.ink2), modifier = Modifier.width(78.dp))
            PriceField(price, onCommit, onError = { err = it })
            Text(unit, style = T.ui(12.5.sp, color = V.ink3))
        }
        com.vims.app.ui.components.FieldError(err)
        if (onYearly != null) {
            Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Yearly $", style = T.ui(13.sp, color = V.ink2), modifier = Modifier.width(78.dp))
                if (yearly != null) PriceField(yearly, onYearly, onError = { yErr = it })
                else PriceField(0.0, onYearly, onError = { yErr = it }, blankWhenZero = true)
                Text(if (unit.endsWith("each")) "/yr each" else "/yr", style = T.ui(12.5.sp, color = V.ink3))
            }
            com.vims.app.ui.components.FieldError(yErr)
        }
        if (desc != null) Text(desc, style = T.ui(12.sp, color = V.ink3, lineHeight = 16.5.sp), softWrap = true, modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
        if (note != null) Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Icon(VIcons.lock, null, tint = V.ink3, modifier = Modifier.size(13.dp))
            Text(note, style = T.ui(12.sp, FontWeight.Medium, V.ink2, lineHeight = 16.5.sp), softWrap = true, modifier = Modifier.weight(1f))
        }
    }
}

/** "Coming soon" label (data v1.11 `comingSoon`): Portal + App is shown but can't be chosen until Phase 2. */
@Composable
fun ComingSoonTag() {
    Text("COMING SOON", style = T.mono(9.5.sp, FontWeight.SemiBold, Color(0xFF7A5200), 0.08.em),
        modifier = Modifier.clip(RoundedCornerShape(6.dp)).background(V.c2Bg).padding(horizontal = 7.dp, vertical = 3.dp))
}
