package com.vims.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.R
import com.vims.app.data.InspStatus
import com.vims.app.data.InspectionBundle
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.SectionsR
import com.vims.app.ui.AdminR
import com.vims.app.ui.CompanyR
import com.vims.app.ui.InspectorsR
import com.vims.app.ui.InstructionsR
import com.vims.app.ui.LoginR
import com.vims.app.ui.PlansR
import com.vims.app.ui.SettingsR
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.rememberDrawerState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.em
import kotlinx.coroutines.launch
import com.vims.app.ui.SubscribeR
import com.vims.app.ui.WizardR
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.HdrAction
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.LeadIcon
import com.vims.app.ui.components.LeadTime
import com.vims.app.ui.components.ListRow
import com.vims.app.ui.components.Pill
import com.vims.app.ui.components.PillKind
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.rich
import com.vims.app.ui.components.vCard
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Fmt
import java.time.LocalDate

fun propertyLabel(structure: String): String = when (structure) {
    "Single Family" -> "Standalone"
    "Mobile / Manufactured" -> "Mobile home"
    else -> structure
}

/** "Ogden, UT 84403" → "Ogden, UT" for compact rows. */
fun shortCity(city: String): String = city.replace(Regex("\\s+\\d{5}(-\\d{4})?$"), "")

@Composable
fun statusPill(b: InspectionBundle) = when (b.inspection.status) {
    InspStatus.DONE -> Pill("Done", PillKind.Done)
    InspStatus.QUEUED -> Pill("Queued", PillKind.Queued)
    InspStatus.SCHEDULED -> Pill("Scheduled", PillKind.New)
    else -> Pill("In progress", PillKind.Prog)
}

@Composable
fun HomeScreen(vm: AppViewModel, nav: NavHostController) {
    val all by vm.inspections.collectAsState()
    val account by vm.account.collectAsState()
    val netState = net(vm)
    val today = remember { LocalDate.now() }
    val list = all.values.sortedWith(compareBy({ it.inspection.selections.date }, { it.inspection.selections.time }))
    fun dateOf(b: InspectionBundle) = Fmt.parseDate(b.inspection.selections.date) ?: today
    val todays = list.filter { dateOf(it) == today }
    val upcoming = list.filter { dateOf(it).isAfter(today) }
    val recent = list.filter { dateOf(it).isBefore(today) }.reversed()

    val drawer = rememberDrawerState(DrawerValue.Closed)
    val scope = rememberCoroutineScope()
    BackHandler(enabled = drawer.isOpen) { scope.launch { drawer.close() } }
    ModalNavigationDrawer(
        drawerState = drawer,
        scrimColor = V.scrim,
        drawerContent = { HomeMenu(vm, nav) { scope.launch { drawer.close() } } },
    ) {
    VScreen(
        "Inspections", companyName(vm), netState,
        left = HdrAction(VIcons.menu, "Menu") { scope.launch { drawer.open() } },
        actions = listOf(HdrAction(VIcons.plus, "New inspection") { nav.navigate(WizardR()) }),
        subtitleLeading = { CompanyMark(vm, 18.dp, bordered = false) },
    ) {
        if (!account.active) {
            Row(
                Modifier.padding(bottom = 14.dp).fillMaxWidth().clip(RoundedCornerShape(13.dp))
                    .background(Brush.horizontalGradient(listOf(V.brand, V.brandBright))).clickable(role = Role.Button) { nav.navigate(SubscribeR) }
                    .padding(horizontal = 16.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(rich("**Free trial** · ${vm.trialDaysLeft()} days left"), style = T.ui(13.5.sp, color = Color.White), modifier = Modifier.weight(1f))
                Text("Subscribe", style = T.ui(13.5.sp, FontWeight.SemiBold, Color.White))
                Icon(VIcons.chevRight, null, tint = Color.White, modifier = Modifier.padding(start = 3.dp).size(16.dp))
            }
        }
        Row(Modifier.padding(bottom = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Stat("${todays.size}", "Inspections today", Modifier.weight(1f))
            Stat("${netState.pending}", "Waiting to sync", Modifier.weight(1f))
        }
        Lbl("Today · ${Fmt.dayHeader(today)}")
        if (todays.isEmpty()) Text("No inspections scheduled today.", style = T.ui(13.sp, color = V.ink3), modifier = Modifier.padding(bottom = 10.dp))
        todays.forEach { InspectionRow(it, nav, showTime = true) }
        if (upcoming.isNotEmpty()) {
            Lbl("Upcoming")
            upcoming.forEach { InspectionRow(it, nav, showTime = true, showDate = true) }
        }
        if (recent.isNotEmpty()) {
            Lbl("Recent")
            recent.forEach { InspectionRow(it, nav, showTime = false) }
        }
        VBtn("New inspection", { nav.navigate(WizardR()) }, Modifier.padding(top = 14.dp), icon = VIcons.plus)
        VBtn("Settings", { nav.navigate(SettingsR) }, Modifier.padding(top = 10.dp), BtnKind.Ghost, icon = VIcons.settings)
    }
    }
}

/** Home side menu (hamburger): identity header, navigation, admin-only tools, Sign out at the bottom. */
@Composable
private fun HomeMenu(vm: AppViewModel, nav: NavHostController, close: () -> Unit) {
    val session by vm.session.collectAsState()
    val ctx = LocalContext.current
    val admin = session?.isAdmin != false
    fun go(route: Any) { close(); nav.navigate(route) }
    var askSignOut by androidx.compose.runtime.saveable.rememberSaveable { androidx.compose.runtime.mutableStateOf(false) }
    if (askSignOut) SignOutDialog(vm, nav) { askSignOut = false }
    ModalDrawerSheet(
        drawerContainerColor = V.paper2, drawerShape = RoundedCornerShape(topEnd = 18.dp, bottomEnd = 18.dp),
        modifier = Modifier.widthIn(max = 320.dp).fillMaxWidth(0.84f), windowInsets = WindowInsets(0),
    ) {
        Column(Modifier.fillMaxWidth().background(V.hdr).statusBarsPadding().padding(start = 18.dp, end = 18.dp, top = 18.dp, bottom = 18.dp)) {
            MyAvatar(vm, 56.dp)
            Spacer(Modifier.height(12.dp))
            Text(session?.name.orEmpty(), style = T.display(16.sp, FontWeight.Bold, Color.White), maxLines = 2)
            Text(session?.email.orEmpty(), style = T.ui(12.sp, color = V.hdrSub), maxLines = 1, overflow = TextOverflow.Ellipsis)
            Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                CompanyMark(vm, 20.dp, bordered = false)
                Text(companyName(vm), style = T.ui(12.5.sp, FontWeight.SemiBold, V.hdrSub), maxLines = 2)
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 10.dp, vertical = 10.dp)) {
            MenuRow(VIcons.home, "Inspections", selected = true) { close() }
            MenuRow(VIcons.plus, "New inspection") { go(WizardR()) }
            MenuRow(VIcons.settings, "Settings") { go(SettingsR) }
            MenuRow(VIcons.building, "Company profile") { go(CompanyR) }
            MenuRow(VIcons.help, "How VIMS works") { go(InstructionsR) }
            MenuRow(VIcons.mail, "Help & feedback") {
                close()
                val fb = vm.platform.value.feedbackEmail
                val i = android.content.Intent(android.content.Intent.ACTION_SENDTO, android.net.Uri.parse("mailto:$fb?subject=" + android.net.Uri.encode("VIMS app feedback")))
                try { ctx.startActivity(i) } catch (_: Exception) { vm.toast("No email app — write to $fb") }
            }
            if (admin) {
                Text("ADMIN", style = T.mono(10.5.sp, color = V.ink3, letterSpacing = 0.12.em), modifier = Modifier.padding(start = 12.dp, top = 16.dp, bottom = 6.dp))
                MenuRow(VIcons.pencil, "Manage checklist") { go(AdminR) }
                MenuRow(VIcons.dollar, "Plans & pricing") { go(PlansR) }
                MenuRow(VIcons.users, "Inspectors") { go(InspectorsR) }
            }
        }
        Box(Modifier.fillMaxWidth().height(1.dp).background(V.line))
        Box(Modifier.navigationBarsPadding().padding(10.dp)) {
            MenuRow(VIcons.signOut, "Sign out") { askSignOut = true }
        }
    }
}

@Composable
private fun MenuRow(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, selected: Boolean = false, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(11.dp)).background(if (selected) V.brand.copy(alpha = .1f) else Color.Transparent)
            .clickable(role = Role.Button, onClick = onClick).padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(32.dp).clip(RoundedCornerShape(8.dp)).background(V.paper3), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = V.brand, modifier = Modifier.size(18.dp))
        }
        Text(label, style = T.ui(14.5.sp, if (selected) FontWeight.SemiBold else FontWeight.Medium, if (selected) V.brandDeep else V.ink))
    }
}

@Composable
private fun Stat(n: String, label: String, modifier: Modifier) {
    Column(modifier.vCard(13.dp).padding(horizontal = 14.dp, vertical = 13.dp)) {
        Text(n, style = T.display(24.sp, FontWeight.ExtraBold, V.ink))
        Spacer(Modifier.height(4.dp))
        Text(label, style = T.ui(11.5.sp, color = V.ink3))
    }
}

@Composable
private fun InspectionRow(b: InspectionBundle, nav: NavHostController, showTime: Boolean, showDate: Boolean = false) {
    val s = b.inspection.selections
    val city = shortCity(s.cityLine)
    val sub = if (showTime) {
        listOf(if (showDate) Fmt.shortDate(s.date) else null, city.ifBlank { null }, propertyLabel(s.structure)).filterNotNull().joinToString(" · ")
    } else {
        "${Fmt.shortDate(s.date)} · ${if (b.inspection.status == InspStatus.DONE) "Report sent" else propertyLabel(s.structure)}"
    }
    ListRow(
        title = s.street.ifBlank { "Untitled inspection" }, subtitle = sub, onClick = { nav.navigate(SectionsR(b.id)) },
        lead = {
            if (showTime) { val (t, ap) = Fmt.timeParts(s.time); LeadTime(t, ap) } else LeadIcon(VIcons.fileLines)
        },
        end = { statusPill(b) },
    )
}

/** Free-look countdown splash — every sign-in during the trial; urgent red at ≤10 days. */
@Composable
fun TrialSplash(vm: AppViewModel, nav: NavHostController) {
    val show by vm.splash.collectAsState()
    AnimatedVisibility(show, enter = fadeIn(), exit = fadeOut()) {
        BackHandler { vm.closeSplash() }
        val d = vm.trialDaysLeft()
        val soon = d <= 10
        val plural = if (d == 1) "" else "s"
        Box(
            Modifier.fillMaxSize().background(Color(0xB80A0F16)).clickable(remember { MutableInteractionSource() }, null) {}.padding(24.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(
                Modifier.widthIn(max = 340.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(V.paper).padding(horizontal = 22.dp, vertical = 26.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box(Modifier.size(72.dp).clip(RoundedCornerShape(18.dp)).background(Color.White).border(1.dp, V.line, RoundedCornerShape(18.dp)), contentAlignment = Alignment.Center) {
                    Image(painterResource(R.drawable.vims_logo), "VIMS", Modifier.size(58.dp))
                }
                Spacer(Modifier.height(14.dp))
                Row(
                    Modifier.clip(RoundedCornerShape(20.dp)).background(if (soon) V.c1Bg else V.c2Bg).padding(horizontal = 14.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.Bottom,
                ) {
                    val fg = if (soon) V.c1 else V.signalDeep
                    Text("$d", style = T.display(22.sp, FontWeight.Bold, fg))
                    Text(" day$plural left", style = T.ui(13.sp, FontWeight.Bold, fg), modifier = Modifier.padding(bottom = 3.dp))
                }
                Spacer(Modifier.height(12.dp))
                Text(if (soon) "Only $d day$plural left in your free look" else "Your free look is counting down",
                    style = T.display(19.sp, FontWeight.Bold, lineHeight = 23.sp), textAlign = TextAlign.Center)
                Spacer(Modifier.height(8.dp))
                Text(
                    if (soon) "You have $d day$plural left to sign up. Set up your subscription so access continues without interruption when the free look ends."
                    else "You are on the 30-day free look — $d days left. Subscribe any time to keep access after it ends.",
                    style = T.ui(13.sp, color = V.ink2, lineHeight = 19.5.sp), textAlign = TextAlign.Center, modifier = Modifier.padding(bottom = 18.dp),
                )
                VBtn("Set up subscription", { vm.closeSplash(); nav.navigate(SubscribeR) })
                VBtn("Continue to app", { vm.closeSplash() }, Modifier.padding(top = 10.dp), BtnKind.Ghost)
            }
        }
    }
}
