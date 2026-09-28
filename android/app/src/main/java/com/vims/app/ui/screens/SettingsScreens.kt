package com.vims.app.ui.screens

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.R
import com.vims.app.data.CompanyProfile
import com.vims.app.ui.AdminR
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.BillingR
import com.vims.app.ui.CompanyR
import com.vims.app.ui.FeedbackAdminR
import com.vims.app.ui.InspectorsR
import com.vims.app.ui.InstructionsR
import com.vims.app.ui.LoginR
import com.vims.app.ui.PlansR
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.FieldLabel
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.LeadIcon
import com.vims.app.ui.components.LeadInitials
import com.vims.app.ui.components.ListRow
import com.vims.app.ui.components.SingleChips
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VCard
import com.vims.app.ui.components.VField
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.rich
import com.vims.app.ui.components.vCard
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Fmt
import com.vims.app.util.rememberThumb
import java.io.File

@Composable
fun NavRow(icon: ImageVector, title: String, sub: String, onClick: () -> Unit) =
    ListRow(title, sub, onClick, lead = { LeadIcon(icon) }, chevron = true)

@Composable
fun SettingsScreen(vm: AppViewModel, nav: NavHostController) {
    val session by vm.session.collectAsState()
    val account by vm.account.collectAsState()
    val settings by vm.settings.collectAsState()
    val company by vm.company.collectAsState()
    val netState = net(vm)
    val ctx = LocalContext.current
    val admin = session?.isAdmin != false

    VScreen("Settings", companyName(vm), netState, backAction(nav), listOf(homeAction(nav))) {
        Lbl("Account", first = true)
        VCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp)) {
                LeadInitials(session?.initials ?: "?", 48.dp, circle = true)
                Column {
                    Text(session?.name ?: "Signed out", style = T.ui(15.sp, FontWeight.Bold))
                    Text(listOfNotNull(company.name.ifBlank { null }, if (session?.isAdmin == false) "Inspector" else null).joinToString(" · "), style = T.ui(12.5.sp, color = V.ink3))
                }
            }
        }
        VBtn("Sign out", { vm.signOut { nav.navigate(LoginR) { popUpTo(0) { inclusive = true } } } }, kind = BtnKind.Ghost, icon = VIcons.signOut)

        Lbl("Sync")
        VCard {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("Auto-sync when online", style = T.ui(14.sp, FontWeight.Bold))
                    Text(if (netState.pending == 0) "Everything is saved on this device" else "${netState.pending} inspection${if (netState.pending == 1) "" else "s"} waiting", style = T.ui(12.sp, color = V.ink3))
                }
                Toggle(settings.autoSync) { vm.setAutoSync(it) }
            }
        }
        VBtn("Sync now", { vm.syncNow() }, kind = BtnKind.Ghost, icon = VIcons.sync)

        Lbl("Subscription & licensing")
        NavRow(VIcons.card, "Plan & billing", "${account.plan.name} · ${if (account.active) subTotalLabel(vm) else "trial"}") { nav.navigate(BillingR) }
        NavRow(VIcons.users, "Inspector accounts", "${account.inspectors.size} inspector${if (account.inspectors.size == 1) "" else "s"}") { nav.navigate(InspectorsR) }

        if (admin) {
            Lbl("Admin")
            NavRow(VIcons.pencil, "Manage checklist", "Add & edit sections and items") { nav.navigate(AdminR) }
            NavRow(VIcons.dollar, "Plans & pricing", "Edit subscription plans & prices") { nav.navigate(PlansR) }
            NavRow(VIcons.mail, "Feedback & support", "Change the feedback contact email") { nav.navigate(FeedbackAdminR) }
        }

        Lbl("Help & feedback")
        VCard {
            Text("Questions or feedback?", style = T.ui(14.sp, FontWeight.Bold))
            Text("We'd love to hear from you — send us a note and the VIMS team will get back to you.", style = T.ui(12.5.sp, color = V.ink3, lineHeight = 18.sp), modifier = Modifier.padding(top = 6.dp, bottom = 12.dp))
            VBtn("Send feedback", {
                val i = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:${account.feedbackEmail}?subject=" + Uri.encode("VIMS app feedback")))
                try { ctx.startActivity(i) } catch (_: Exception) { vm.toast("No email app — write to ${account.feedbackEmail}") }
            }, kind = BtnKind.Ghost, icon = VIcons.mail)
        }

        Lbl("Company & help")
        NavRow(VIcons.building, "Company profile & logo", "Inspector info, logo, review link") { nav.navigate(CompanyR) }
        NavRow(VIcons.help, "How VIMS works", "Instructions & new-account tutorial") { nav.navigate(InstructionsR) }

        Lbl("Defaults")
        VCard {
            Text("Checklist depth", style = T.ui(14.sp, FontWeight.Bold))
            Text("Applies to new inspections. High Detail asks for measurements; Fast Entry is quick condition & notes.", style = T.ui(12.sp, color = V.ink3, lineHeight = 16.sp), modifier = Modifier.padding(top = 4.dp, bottom = 11.dp))
            SingleChips(vm.config.depths.map { it.label }, vm.config.depthLabel(settings.defaultDepth), { v -> if (v != null) vm.setDefaultDepth(vm.config.depthId(v)) }, required = true)
        }
        ListRow("Report cover", settings.defaultCover.let { "${it.color} · ${it.artLabel()}" })
        ListRow("Photo size", "JPG · up to 2048 px")
        Text("VIMS ${com.vims.app.BuildConfig.VERSION_NAME} · checklist data v${vm.config.version}", style = T.mono(10.5.sp, color = V.ink3), modifier = Modifier.padding(top = 8.dp, start = 2.dp))
    }
}

fun subTotalLabel(vm: AppViewModel): String {
    val a = vm.account.value
    return if (a.plan.perReport) "${Fmt.money(a.plan.price)} / report" else "${Fmt.money(vm.monthlyTotal(a))}/mo"
}

@Composable
fun Toggle(on: Boolean, onChange: (Boolean) -> Unit) {
    Box(
        Modifier.size(width = 52.dp, height = 48.dp).clickable(role = Role.Switch, onClickLabel = "Toggle") { onChange(!on) },
        contentAlignment = Alignment.Center,
    ) {
        Box(Modifier.size(width = 46.dp, height = 28.dp).clip(RoundedCornerShape(20.dp)).background(if (on) V.brand else V.line).padding(3.dp), contentAlignment = if (on) Alignment.CenterEnd else Alignment.CenterStart) {
            Box(Modifier.size(22.dp).clip(CircleShape).background(Color.White))
        }
    }
}

@Composable
fun CompanyScreen(vm: AppViewModel, nav: NavHostController) {
    val saved by vm.company.collectAsState()
    val logoVersion by vm.logoVersion.collectAsState()
    var p by rememberSaveable(saved.logoFile, saved.agreementName, stateSaver = companySaver) { mutableStateOf(saved) }
    val ctx = LocalContext.current
    val logoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) vm.importLogo(uri) }
    val docPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val name = ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: "Inspection agreement"
            vm.importAgreement(uri, name)
        }
    }
    fun set(f: (CompanyProfile) -> CompanyProfile) { p = f(p) }

    VScreen("Company profile", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Lbl("Company logo", first = true)
        Text("This logo appears on your report covers.", style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, bottom = 10.dp))
        VCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                Box(Modifier.size(76.dp).clip(RoundedCornerShape(16.dp)).background(Color.White).border(1.dp, V.line, RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
                    val logoFile = saved.logoFile?.let { File(ctx.filesDir, it) }
                    val thumb = logoFile?.let { rememberThumb(it, logoVersion, 256).value }
                    if (thumb != null) Image(thumb, "Company logo", Modifier.size(64.dp), contentScale = ContentScale.Fit)
                    else Image(painterResource(R.drawable.vims_logo), "Company logo", Modifier.size(64.dp))
                }
                Column(Modifier.weight(1f)) {
                    VBtn("Upload logo", { logoPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, kind = BtnKind.Ghost, icon = VIcons.upload, minHeight = 48.dp)
                    Text("PNG or JPG, square works best.", style = T.ui(11.5.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, top = 8.dp))
                }
            }
        }
        Lbl("Company details")
        VField("Company name", p.name, { v -> set { it.copy(name = v) } }, caps = KeyboardCapitalization.Words)
        VField("Address", p.address, { v -> set { it.copy(address = v) } }, placeholder = "Street, City, State ZIP", caps = KeyboardCapitalization.Words)
        Lbl("Lead inspector")
        VField("Inspector name", p.inspectorName, { v -> set { it.copy(inspectorName = v) } }, caps = KeyboardCapitalization.Words)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            VField("License #", p.license, { v -> set { it.copy(license = v) } }, Modifier.weight(1f), placeholder = "e.g. UT-12345", caps = KeyboardCapitalization.Characters, bottom = 0.dp)
            VField("Phone", p.phone, { v -> set { it.copy(phone = v) } }, Modifier.weight(1f), placeholder = "(801) 555-0134", keyboard = KeyboardType.Phone, bottom = 0.dp)
        }
        VField("Email", p.email, { v -> set { it.copy(email = v) } }, Modifier.padding(top = 11.dp), placeholder = "you@company.com", keyboard = KeyboardType.Email)
        Lbl("Online review link")
        Text("Add the URL where clients can leave a review of the inspection. It's included with the report so clients can rate you.", style = T.ui(12.sp, color = V.ink3, lineHeight = 16.sp), modifier = Modifier.padding(start = 2.dp, bottom = 9.dp))
        VField("Review URL", p.reviewUrl, { v -> set { it.copy(reviewUrl = v) } }, placeholder = "https://g.page/r/your-review-link", keyboard = KeyboardType.Uri)
        Lbl("Inspection agreement")
        Text("Legal requirements vary by state, so use your own agreement. Upload it here and clients sign it before each inspection.", style = T.ui(12.sp, color = V.ink3, lineHeight = 16.sp), modifier = Modifier.padding(start = 2.dp, bottom = 10.dp))
        VCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                LeadIcon(VIcons.fileAgreement)
                Column(Modifier.weight(1f)) {
                    Text(saved.agreementName ?: "No agreement uploaded", style = T.ui(14.sp, FontWeight.Bold), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("PDF or Word document", style = T.ui(12.sp, color = V.ink3))
                }
                VBtn("Upload", { docPicker.launch(arrayOf("application/pdf", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document")) },
                    Modifier.width(104.dp), BtnKind.Ghost, minHeight = 48.dp)
            }
        }
        VBtn("Save profile", { vm.saveCompany(p.copy(logoFile = saved.logoFile, agreementName = saved.agreementName, agreementFile = saved.agreementFile)) }, icon = VIcons.check)
    }
}

private val companySaver = androidx.compose.runtime.saveable.Saver<CompanyProfile, String>(
    save = { com.vims.app.data.ChecklistLoader.json.encodeToString(CompanyProfile.serializer(), it) },
    restore = { com.vims.app.data.ChecklistLoader.json.decodeFromString(CompanyProfile.serializer(), it) },
)

@Composable
fun InstructionsScreen(vm: AppViewModel, nav: NavHostController) {
    VScreen("How VIMS works", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        com.vims.app.ui.components.Banner("**Everything saves on your device.** All inspection data and photos are stored locally and work fully offline — they upload automatically the next time you are online.", VIcons.bolt, blue = true)
        HowCard(VIcons.info, "Getting started", "**New account:** tap **Create account** on sign-in and enter your details, or tap **Join a company with a code** if your company gave you one. New companies start on a **30-day free look** — set up your company profile and logo in Settings first.")
        HowCard(VIcons.list, "Run an inspection", "Tap **New inspection**, then step through: inspection info → property details → the areas to inspect. On each section, tap the answers that apply, add photos, mark them up, and flag any concern into a category. Use **Save & next section** to move through quickly.")
        HowCard(VIcons.flask, "Checklist depth", "Pick **High Detail**, **Standard**, or **Fast Entry** per inspection (or set a default in Settings). High Detail asks the most; Fast Entry is a quick condition-and-notes pass.")
        HowCard(VIcons.file, "Photos & findings", "Tap **Add** to capture a photo, then tap it to draw on it or add a quick comment. Flagging a photo as a concern adds it to the **Summary** under Category 1 Safety, 2 Functional, or 3 Items to monitor.")
        HowCard(VIcons.file, "Generate the report", "From the Summary tap **Save and generate report**, choose a cover (color → theme → style), and the app builds your branded PDF. It queues to send when you are back online.")
        HowCard(VIcons.bolt, "Subscription & inspectors", "Your free look counts down at every sign-in. Subscribe through **Square** any time. Add inspectors under your company license and share your **company code** so they can join.")
        VCard {
            Text("Need a hand? Contact your VIMS setup team", style = T.ui(13.sp, color = V.ink3), modifier = Modifier.fillMaxWidth(), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            Text("support@ogrelogic.com", style = T.mono(13.sp, color = V.brandDeep), modifier = Modifier.fillMaxWidth().padding(top = 4.dp), textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        }
    }
}

@Composable
private fun HowCard(icon: ImageVector, title: String, body: String) {
    VCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.padding(bottom = 8.dp)) {
            LeadIcon(icon, 30.dp, 17.dp, radius = 8.dp)
            Text(title, style = T.display(15.sp, FontWeight.Bold))
        }
        Text(rich(body), style = T.ui(13.sp, color = V.ink2, lineHeight = 20.sp))
    }
}

@Composable
fun FeedbackAdminScreen(vm: AppViewModel, nav: NavHostController) {
    val account by vm.account.collectAsState()
    var email by rememberSaveable(account.feedbackEmail) { mutableStateOf(account.feedbackEmail) }
    VScreen("Feedback & support", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Hint("Owner admin — set the email address that receives help & feedback messages sent from the app.", Modifier.padding(top = 2.dp, bottom = 14.dp))
        VField("Feedback contact email", email, { email = it }, keyboard = KeyboardType.Email)
        VBtn("Save", { vm.saveFeedbackEmail(email) }, icon = VIcons.check)
    }
}
