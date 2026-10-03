package com.vims.app.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.data.ChecklistEngine
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.ReportR
import com.vims.app.ui.components.HdrAction
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.vCard
import com.vims.app.ui.openSection
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SummaryScreen(vm: AppViewModel, nav: NavHostController, inspId: String) {
    val all by vm.inspections.collectAsState()
    val b = all[inspId] ?: run { MissingInspection(vm, nav); return }
    var drawer by rememberSaveable { mutableStateOf(false) }
    VScreen(
        "Summary", b.inspection.selections.street, net(vm), backAction(nav), listOf(HdrAction(VIcons.list, "Sections") { drawer = true }, homeAction(nav)),
        overlay = { SectionsDrawer(drawer, b, null, { drawer = false }, { drawer = false; nav.openLink(it, inspId) }, { drawer = false; nav.openSection(inspId, it) }) },
    ) {
        Hint("Every finding you flag lands here automatically, grouped by category. This drives the summary pages of the report.", Modifier.padding(top = 2.dp, bottom = 14.dp))
        // State-required disclosure (stateRules.<STATE>.summaryDisclosure, e.g. Oklahoma) — permanent, always first.
        StateDisclosureCard(vm, b.inspection.selections.state)
        vm.config.findings.categories.forEach { cat ->
            val items = b.findings.filter { it.cat == cat.id }.sortedWith(compareBy({ ChecklistEngine.number(b.defs, it.section) }, { it.createdAt }))
            Column(Modifier.padding(bottom = 12.dp).fillMaxWidth().vCard()) {
                Row(Modifier.padding(horizontal = 15.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(11.dp)) {
                    Box(Modifier.size(34.dp).clip(RoundedCornerShape(9.dp)).background(V.cat(cat.id)), contentAlignment = Alignment.Center) {
                        Text("${cat.id}", style = T.display(16.sp, FontWeight.ExtraBold, Color.White))
                    }
                    Column(Modifier.weight(1f)) {
                        Text("Category ${cat.id} · ${cat.label}", style = T.ui(14.5.sp, FontWeight.Bold))
                        Text(cat.note, style = T.ui(12.sp, color = V.ink3, lineHeight = 15.6.sp), modifier = Modifier.padding(top = 2.dp))
                    }
                    Text("${items.size}", style = T.mono(15.sp, FontWeight.Bold))
                }
                if (items.isEmpty()) {
                    Box(Modifier.fillMaxWidth().height(1.dp).background(V.line2))
                    Text("No findings in this category.", style = T.ui(13.sp, color = V.ink3), modifier = Modifier.padding(horizontal = 15.dp, vertical = 12.dp))
                }
                items.forEach { f ->
                    Box(Modifier.fillMaxWidth().height(1.dp).background(V.line2))
                    Row(
                        Modifier.fillMaxWidth().combinedClickable(onClickLabel = "Open section", onLongClickLabel = "Remove finding",
                            onLongClick = { vm.deleteFinding(inspId, f.id) }, onClick = { nav.openSection(inspId, f.section) }).padding(horizontal = 15.dp, vertical = 11.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Box(Modifier.padding(top = 7.dp).size(7.dp).clip(CircleShape).background(V.cat(cat.id)))
                        Text(buildAnnotatedString {
                            withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = V.ink)) { append(f.section) }
                            append(" — ${f.text}")
                        }, style = T.ui(13.5.sp, color = V.ink2, lineHeight = 18.sp))
                    }
                }
            }
        }
        Hint("Long-press a finding to remove it.", Modifier.padding(start = 2.dp, bottom = 2.dp), size = 12f)
        VBtn("Save and generate report", { nav.navigate(ReportR(inspId)) }, Modifier.padding(top = 14.dp), icon = VIcons.fileCheck)
    }
}
