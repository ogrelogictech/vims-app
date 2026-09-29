package com.vims.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.data.BuiltGroup
import com.vims.app.data.InspectionBundle
import com.vims.app.data.SecStatus
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.ReportR
import com.vims.app.ui.SummaryR
import com.vims.app.ui.WizardR
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.Pill
import com.vims.app.ui.components.PillKind
import com.vims.app.ui.components.ProgBar
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VCard
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.vCard
import com.vims.app.ui.goHome
import com.vims.app.ui.openSection
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons

fun statusWord(st: String) = when (st) { SecStatus.DONE -> "Done"; SecStatus.PROG -> "In progress"; else -> "Not started" }
fun statusDot(st: String) = when (st) { SecStatus.DONE -> V.pass; SecStatus.PROG -> V.signal; else -> V.paper3 }

/** Navigates a built-checklist `link` group (Inspection Info → wizard, Summary → summary). */
fun NavHostController.openLink(link: String, inspId: String) = when (link) {
    "inspectionInfo" -> navigate(WizardR(inspId))
    "summary" -> navigate(SummaryR(inspId))
    else -> Unit
}

@Composable
fun SectionsScreen(vm: AppViewModel, nav: NavHostController, inspId: String) {
    val all by vm.inspections.collectAsState()
    val b = all[inspId] ?: run { MissingInspection(vm, nav); return }
    val leaves = b.inspection.leafSections
    val done = leaves.count { b.status(it) == SecStatus.DONE }
    val pct = if (leaves.isEmpty()) 0 else Math.round(done * 100f / leaves.size)
    val open = rememberSaveable(saver = openSaver()) { mutableStateMapOf<String, Boolean>().apply { b.inspection.groups.firstOrNull { it.link == null }?.let { put(it.heading, true) } } }

    VScreen("Sections", b.inspection.selections.street, net(vm), backAction(nav), listOf(homeAction(nav))) {
        VCard(padding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp, vertical = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(bottom = 9.dp)) {
                Text(b.inspection.selections.street, style = T.ui(15.sp, FontWeight.Bold), modifier = Modifier.weight(1f))
                Pill("$pct%", PillKind.Prog)
            }
            ProgBar(pct / 100f)
            Row(Modifier.padding(top = 11.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                CountText("$done", " done", V.ink); CountText("${leaves.size - done}", " left", V.ink); CountText("${b.findings.size}", " findings", V.c1)
            }
        }
        Lbl("Checklist · tap a group")
        b.inspection.groups.forEach { g ->
            GroupCard(g, b, open[g.heading] == true, onToggle = { open[g.heading] = open[g.heading] != true },
                onLink = { nav.openLink(it, inspId) }, onSection = { nav.openSection(inspId, it) })
        }
        if (b.inspection.hasSummary) VBtn("Review summary", { nav.navigate(SummaryR(inspId)) }, Modifier.padding(top = 8.dp), BtnKind.Signal, icon = VIcons.reviewSummary)
        VBtn("Generate report", { nav.navigate(ReportR(inspId)) }, Modifier.padding(top = if (b.inspection.hasSummary) 10.dp else 8.dp), icon = VIcons.file)
    }
}

private fun openSaver() = androidx.compose.runtime.saveable.Saver<androidx.compose.runtime.snapshots.SnapshotStateMap<String, Boolean>, ArrayList<String>>(
    save = { ArrayList(it.filterValues { v -> v }.keys) },
    restore = { l -> mutableStateMapOf<String, Boolean>().apply { l.forEach { put(it, true) } } },
)

@Composable
private fun CountText(n: String, label: String, color: Color) {
    Text(com.vims.app.ui.components.rich("**$n**$label", color), style = T.ui(12.sp, color = V.ink3))
}

@Composable
private fun GroupCard(g: BuiltGroup, b: InspectionBundle, open: Boolean, onToggle: () -> Unit, onLink: (String) -> Unit, onSection: (String) -> Unit) {
    Column(Modifier.padding(bottom = 10.dp).fillMaxWidth().vCard()) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable(role = Role.Button) { if (g.link != null) onLink(g.link) else onToggle() }.padding(horizontal = 15.dp, vertical = 13.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(11.dp),
        ) {
            Box(Modifier.size(30.dp).clip(RoundedCornerShape(8.dp)).background(V.paper3), contentAlignment = Alignment.Center) {
                Icon(VIcons.named(g.icon), null, tint = V.brand, modifier = Modifier.size(17.dp))
            }
            Text(g.heading, style = T.ui(14.5.sp, FontWeight.Bold), modifier = Modifier.weight(1f))
            if (g.link != null) {
                Icon(VIcons.caretRight, null, tint = V.ink3, modifier = Modifier.size(18.dp))
            } else {
                val leaves = g.leaves
                Text("${leaves.count { b.status(it) == SecStatus.DONE }}/${leaves.size}", style = T.mono(11.sp, color = V.ink3))
                Icon(VIcons.chevDown, null, tint = V.ink3, modifier = Modifier.padding(start = 8.dp).size(18.dp).rotate(if (open) 180f else 0f))
            }
        }
        if (g.link == null && open) {
            Box(Modifier.fillMaxWidth().height(1.dp).background(V.line2))
            g.sections.forEachIndexed { i, s -> SecRow(s, b.status(s), last = i == g.sections.lastIndex && g.sub == null) { onSection(s) } }
            g.sub?.let { sub ->
                SubHead(sub.heading)
                sub.sections.forEachIndexed { i, s -> SecRow(s, b.status(s), last = i == sub.sections.lastIndex) { onSection(s) } }
            }
        }
    }
}

@Composable
fun SubHead(text: String) {
    Column {
        Box(Modifier.fillMaxWidth().height(1.dp).background(V.line2))
        Text(text.uppercase(), style = T.mono(10.sp, FontWeight.SemiBold, V.brandDeep, 0.11.em),
            modifier = Modifier.fillMaxWidth().background(V.paper2).padding(start = 18.dp, end = 15.dp, top = 12.dp, bottom = 7.dp))
    }
}

@Composable
private fun SecRow(name: String, st: String, last: Boolean, onClick: () -> Unit) {
    Column {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button, onClick = onClick).padding(start = 18.dp, end = 15.dp, top = 12.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Dot(st)
            Text(name, style = T.ui(14.sp, FontWeight.Medium), modifier = Modifier.weight(1f))
            Text(statusWord(st), style = T.mono(10.5.sp, FontWeight.SemiBold, V.ink2))
        }
        if (!last) Box(Modifier.fillMaxWidth().height(1.dp).background(V.line2))
    }
}

@Composable
fun Dot(st: String, size: Int = 9) {
    val m = Modifier.size(size.dp).clip(CircleShape).background(statusDot(st))
    Box(if (st == SecStatus.TODO) m.border(1.dp, V.line, CircleShape) else m)
}

@Composable
fun MissingInspection(vm: AppViewModel, nav: NavHostController) {
    VScreen("Inspection", companyName(vm), net(vm), backAction(nav)) {
        Text("This inspection is no longer on this device.", style = T.ui(14.sp, color = V.ink3))
        VBtn("Back to inspections", { nav.goHome() }, Modifier.padding(top = 16.dp))
    }
}

/** The "Checklist sections" drawer (header list icon on inspection screens). */
@Composable
fun BoxScope.SectionsDrawer(visible: Boolean, b: InspectionBundle?, current: String?, onClose: () -> Unit, onLink: (String) -> Unit, onSection: (String) -> Unit) {
    if (visible) BackHandler(onBack = onClose)
    AnimatedVisibility(visible, enter = fadeIn(), exit = fadeOut()) {
        Box(Modifier.fillMaxSize().background(Color(0x800A0F16)).clickable(remember { MutableInteractionSource() }, null, onClick = onClose))
    }
    AnimatedVisibility(visible, enter = slideInHorizontally { -it }, exit = slideOutHorizontally { -it }) {
        if (b == null) return@AnimatedVisibility
        val openMap = remember(b.id, current) { mutableStateMapOf<String, Boolean>().apply { b.inspection.groups.forEach { g -> if (current != null && current in g.leaves) put(g.heading, true) } } }
        Column(Modifier.fillMaxHeight().fillMaxWidth(.84f).widthIn(max = 340.dp).shadow(24.dp).background(V.paper2)) {
            Column(Modifier.fillMaxWidth().background(V.hdr).statusBarsPadding().padding(18.dp)) {
                Text("Checklist sections", style = T.display(16.sp, FontWeight.Bold, Color.White))
                Text(b.inspection.selections.street, style = T.ui(12.sp, color = V.hdrSub))
            }
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).navigationBarsPadding().padding(10.dp)) {
                b.inspection.groups.forEach { g ->
                    val isOpen = openMap[g.heading] == true
                    Column(Modifier.padding(bottom = 8.dp).fillMaxWidth().vCard(12.dp)) {
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(role = Role.Button) { if (g.link != null) onLink(g.link) else openMap[g.heading] = !isOpen }.padding(horizontal = 13.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Box(Modifier.size(26.dp).clip(RoundedCornerShape(7.dp)).background(V.paper3), contentAlignment = Alignment.Center) {
                                Icon(VIcons.named(g.icon), null, tint = V.brand, modifier = Modifier.size(16.dp))
                            }
                            Text(g.heading, style = T.ui(13.5.sp, FontWeight.SemiBold), modifier = Modifier.weight(1f))
                            if (g.link == null) Text("${g.leaves.size}", style = T.mono(10.sp, color = V.ink3), modifier = Modifier.padding(end = 6.dp))
                            Icon(if (g.link != null) VIcons.caretRight else VIcons.chevDown, null, tint = V.ink3, modifier = Modifier.size(16.dp).rotate(if (isOpen) 180f else 0f))
                        }
                        if (g.link == null && isOpen) {
                            (g.sections).forEach { s -> DrawerRow(s, b.status(s), s == current) { onSection(s) } }
                            g.sub?.let { sub -> SubHead(sub.heading); sub.sections.forEach { s -> DrawerRow(s, b.status(s), s == current) { onSection(s) } } }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DrawerRow(name: String, st: String, on: Boolean, onClick: () -> Unit) {
    Column {
        Box(Modifier.fillMaxWidth().height(1.dp).background(V.line2))
        Row(
            Modifier.fillMaxWidth().heightIn(min = 44.dp).background(if (on) V.brand.copy(alpha = .1f) else Color.Transparent).clickable(role = Role.Button, onClick = onClick)
                .padding(start = 16.dp, end = 13.dp, top = 10.dp, bottom = 10.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Dot(st, 8)
            Text(name, style = T.ui(13.5.sp, if (on) FontWeight.SemiBold else FontWeight.Normal, if (on) V.brandDeep else V.ink2), modifier = Modifier.weight(1f))
        }
    }
}
