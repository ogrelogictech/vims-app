package com.vims.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.data.InspectionBundle
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.rich
import com.vims.app.ui.goHome
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons

/*
 * Delete one inspection from this device (client feedback Oct 11, 2026: testers had no way to free storage).
 * Entry points: Home row "⋯" menu / long-press, the Sections screen and the Report ready screen — all use the same dialog.
 * TODO(backend): once the VIMS server is live, reports are retained server-side (reports 3 yrs, agreements 5 yrs),
 * so deleting only frees device space.
 */

private fun addressOf(b: InspectionBundle): String = b.inspection.selections.let { s -> s.fullAddress.ifBlank { s.street }.ifBlank { "this inspection" } }

/**
 * "Delete this inspection?" (team QA Oct 22: short, explicit buttons) — Save report first (only when a report exists; shares
 * it, does not delete) · Delete (red) · Cancel, stacked full width so no label is cut off at any width or font size.
 */
@Composable
fun DeleteInspectionDialog(vm: AppViewModel, b: InspectionBundle, onDismiss: () -> Unit, onDelete: () -> Unit) {
    val ctx = LocalContext.current
    val report = remember(b.inspection.reportFile, b.inspection.reportGeneratedAt) { vm.reportFile(b.id) }
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(V.paper).verticalScroll(rememberScrollState()).padding(20.dp)) {
            Text("Delete this inspection?", style = T.display(18.sp, FontWeight.Bold, V.ink), modifier = Modifier.padding(bottom = 8.dp))
            Text(
                rich("This removes the checklist, photos and report for **${addressOf(b)}** from this device. " +
                    "Some states require keeping reports for 3–5 years.", V.ink),
                style = T.ui(13.5.sp, color = V.ink2, lineHeight = 20.sp), modifier = Modifier.padding(bottom = 16.dp),
            )
            if (report != null) {
                VBtn("Save report first", { saveOrShareReport(ctx, vm, b, report) }, Modifier.padding(bottom = 10.dp), BtnKind.Ghost, VIcons.share)
            }
            VBtn("Delete", onDelete, kind = BtnKind.Danger, icon = VIcons.trash)
            VBtn("Cancel", onDismiss, Modifier.padding(top = 10.dp), BtnKind.Ghost)
        }
    }
}

/** Destructive ghost button at the bottom of an inspection screen; deleting returns to Home with the inspection's back stack cleared. */
@Composable
fun DeleteInspectionButton(vm: AppViewModel, nav: NavHostController, b: InspectionBundle, modifier: Modifier = Modifier) {
    var ask by rememberSaveable(b.id) { mutableStateOf(false) }
    VBtn("Delete inspection", { ask = true }, modifier, BtnKind.GhostDanger, VIcons.trash)
    if (ask) DeleteInspectionDialog(vm, b, onDismiss = { ask = false }) {
        ask = false
        nav.goHome() // leave the inspection's screens first so they never show "no longer on this device"
        vm.deleteInspection(b.id)
    }
}

/** Trailing "⋯" on a Home inspection row (48dp target); long-pressing the row opens the same menu via [open]. */
@Composable
fun InspectionMoreButton(vm: AppViewModel, b: InspectionBundle, title: String, open: Boolean, onOpenChange: (Boolean) -> Unit) {
    val ctx = LocalContext.current
    var ask by rememberSaveable(b.id) { mutableStateOf(false) }
    val report = remember(open, b.inspection.reportFile, b.inspection.reportGeneratedAt) { if (open) vm.reportFile(b.id) else null }
    Box {
        Box(
            Modifier.size(48.dp).clip(RoundedCornerShape(11.dp)).clickable(role = Role.Button, onClickLabel = "More options") { onOpenChange(true) },
            contentAlignment = Alignment.Center,
        ) { Icon(VIcons.more, contentDescription = "More options for $title", tint = V.ink3, modifier = Modifier.size(20.dp)) }
        DropdownMenu(expanded = open, onDismissRequest = { onOpenChange(false) }, containerColor = V.paper) {
            if (report != null) DropdownMenuItem(
                text = { Text("Save or share report", style = T.ui(14.sp, color = V.ink)) },
                leadingIcon = { Icon(VIcons.share, null, tint = V.brand, modifier = Modifier.size(18.dp)) },
                onClick = { onOpenChange(false); saveOrShareReport(ctx, vm, b, report) },
            )
            DropdownMenuItem(
                text = { Text("Delete inspection", style = T.ui(14.sp, FontWeight.SemiBold, V.c1)) },
                leadingIcon = { Icon(VIcons.trash, null, tint = V.c1, modifier = Modifier.size(18.dp)) },
                onClick = { onOpenChange(false); ask = true },
            )
        }
    }
    if (ask) DeleteInspectionDialog(vm, b, onDismiss = { ask = false }) { ask = false; vm.deleteInspection(b.id) }
}
