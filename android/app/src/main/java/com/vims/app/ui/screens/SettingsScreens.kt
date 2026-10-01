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
import com.vims.app.ui.ReportBccR
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
import com.vims.app.ui.components.VInput
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.rich
import com.vims.app.ui.components.vCard
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Checks
import com.vims.app.ui.components.rememberImageChooser
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.remember
import com.vims.app.util.Filters
import com.vims.app.util.Fmt
import com.vims.app.util.PhoneTransform
import com.vims.app.util.formField
import com.vims.app.util.rememberForm
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
        var signOutAsk by remember { mutableStateOf(false) }
        var deleteAsk by remember { mutableStateOf(false) }
        val photoChooser = rememberImageChooser("Profile photo", vm.userPhoto.collectAsState().value != null, { vm.setUserPhoto(it) }, { vm.removeUserPhoto() })
        if (signOutAsk) SignOutDialog(vm, nav) { signOutAsk = false }
        if (deleteAsk) DeleteAccountDialog(vm, nav) { deleteAsk = false }
        Lbl("Account", first = true)
        VCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp)) {
                // The user's OWN photo (tap to change) — never the company logo.
                Box(Modifier.clip(CircleShape).clickable(role = Role.Button, onClickLabel = "Change profile photo") { photoChooser.open() }) {
                    MyAvatar(vm, 52.dp)
                    Box(Modifier.align(Alignment.BottomEnd).size(20.dp).clip(CircleShape).background(V.paper).padding(2.dp).clip(CircleShape).background(V.brand), contentAlignment = Alignment.Center) {
                        Icon(VIcons.camera, null, tint = Color.White, modifier = Modifier.size(11.dp))
                    }
                }
                Column(Modifier.weight(1f)) {
                    Text(session?.name ?: "Signed out", style = T.ui(15.sp, FontWeight.Bold))
                    Text(session?.email.orEmpty(), style = T.ui(12.5.sp, color = V.ink3), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(listOfNotNull(company.name.ifBlank { null }, if (session?.isAdmin == false) "Inspector" else null).joinToString(" · "), style = T.ui(12.5.sp, FontWeight.SemiBold, V.ink2), modifier = Modifier.padding(top = 2.dp))
                }
            }
        }
        VBtn("Sign out", { signOutAsk = true }, kind = BtnKind.Ghost, icon = VIcons.signOut)
        VBtn("Delete account", { deleteAsk = true }, Modifier.padding(top = 10.dp), BtnKind.GhostDanger, icon = VIcons.trash)

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
        }
        // VIMS platform-owner settings (not per company): only the platform owner sees these.
        if (vm.isPlatformOwner) {
            if (!admin) Lbl("Admin")
            NavRow(VIcons.mail, "Feedback & support", "Change the feedback contact email") { nav.navigate(FeedbackAdminR) }
            val p = vm.platform.collectAsState().value
            NavRow(VIcons.mailPlus, "Report quality copy (BCC)", p.activeBcc?.let { "On · $it" } ?: "Off") { nav.navigate(ReportBccR) }
        }

        Lbl("Help & feedback")
        VCard {
            Text("Questions or feedback?", style = T.ui(14.sp, FontWeight.Bold))
            Text("We'd love to hear from you — send us a note and the VIMS team will get back to you.", style = T.ui(12.5.sp, color = V.ink3, lineHeight = 18.sp), modifier = Modifier.padding(top = 6.dp, bottom = 12.dp))
            VBtn("Send feedback", {
                val fb = vm.platform.value.feedbackEmail
                val i = Intent(Intent.ACTION_SENDTO, Uri.parse("mailto:$fb?subject=" + Uri.encode("VIMS app feedback")))
                try { ctx.startActivity(i) } catch (_: Exception) { vm.toast("No email app — write to $fb") }
            }, kind = BtnKind.Ghost, icon = VIcons.mail)
        }

        Lbl("Company & help")
        NavRow(VIcons.building, "Company profile & logo", "Inspector info, logo, review link") { nav.navigate(CompanyR) }
        NavRow(VIcons.help, "How VIMS works", "Instructions & new-account tutorial") { nav.navigate(InstructionsR) }

        Lbl("Legal")
        NavRow(VIcons.fileText, "End User License Agreement", if (vm.eula.isValid) "Revised ${vm.eula.revised}" else "Couldn't load — tap for details") { nav.navigate(com.vims.app.ui.EulaR) }

        Lbl("Defaults")
        VCard {
            Text("Checklist depth", style = T.ui(14.sp, FontWeight.Bold))
            Text("Applies to new inspections. High Detail asks for measurements; Fast Entry is quick condition & notes.", style = T.ui(12.sp, color = V.ink3, lineHeight = 16.sp), modifier = Modifier.padding(top = 4.dp, bottom = 11.dp))
            SingleChips(vm.config.depths.map { it.label }, vm.config.depthLabel(settings.defaultDepth), { v -> if (v != null) vm.setDefaultDepth(vm.config.depthId(v)) }, required = true)
        }
        ListRow("Report cover", settings.defaultCover.let { "${it.color} · ${it.artLabel()}" })
        ListRow("Photo size", "JPG · up to 2048 px")
        // Version/data line is for developers only — never shown in release builds.
        if (com.vims.app.BuildConfig.DEBUG) Text("Debug build · VIMS ${com.vims.app.BuildConfig.VERSION_NAME} · checklist data v${vm.config.version}", style = T.mono(10.5.sp, color = V.ink3), modifier = Modifier.padding(top = 8.dp, start = 2.dp))
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
    val logoChooser = rememberImageChooser("Company logo", saved.logoFile != null, { vm.importLogo(it) }, { vm.removeLogo() })
    val docPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            val name = ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c -> if (c.moveToFirst()) c.getString(0) else null } ?: "Inspection agreement"
            vm.importAgreement(uri, name)
        }
    }
    fun set(f: (CompanyProfile) -> CompanyProfile) { p = f(p) }
    val form = rememberForm()

    VScreen("Company profile", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Lbl("Company logo", first = true)
        Text("This logo appears on your report covers.", style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, bottom = 10.dp))
        VCard {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                CompanyMark(vm, 76.dp)
                Column(Modifier.weight(1f)) {
                    VBtn(if (saved.logoFile != null) "Change logo" else "Upload logo", { logoChooser.open() }, kind = BtnKind.Ghost, icon = VIcons.upload, minHeight = 48.dp)
                    Text("PNG or JPG, square works best.", style = T.ui(11.5.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, top = 8.dp))
                }
            }
        }
        Lbl("Company details")
        val nameErr = form.check("name", p.name) { Checks.required(p.name, "Enter the company name") }
        val phoneErr = form.check("phone", p.phone) { Checks.phone(p.phone.filter { it.isDigit() }) }
        val emailErr = form.check("email", p.email) { Checks.email(p.email, required = false) }
        val urlErr = form.check("url", p.reviewUrl) { Checks.url(p.reviewUrl) }
        VField("Company name", p.name, { v -> set { it.copy(name = v) } }, Modifier.formField(form, "name"), caps = KeyboardCapitalization.Words, error = nameErr, filter = Filters::companyName, required = true)
        VField("Address", p.address, { v -> set { it.copy(address = v) } }, placeholder = "Street, City, State ZIP", caps = KeyboardCapitalization.Words, filter = Filters::address)
        Lbl("Lead inspector")
        VField("Inspector name", p.inspectorName, { v -> set { it.copy(inspectorName = v) } }, caps = KeyboardCapitalization.Words, filter = Filters::personName)
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            VField("License #", p.license, { v -> set { it.copy(license = v) } }, Modifier.weight(1f), placeholder = "e.g. UT-12345", caps = KeyboardCapitalization.Characters, bottom = 0.dp, filter = Filters::license)
            VField("Phone", p.phone, { v -> set { it.copy(phone = v) } }, Modifier.weight(1f).formField(form, "phone"), placeholder = "(801) 555-0134", keyboard = KeyboardType.Phone, bottom = 0.dp,
                filter = Filters::phone, visual = PhoneTransform, error = phoneErr)
        }
        VField("Email", p.email, { v -> set { it.copy(email = v) } }, Modifier.padding(top = 11.dp).formField(form, "email"), placeholder = "you@company.com", keyboard = KeyboardType.Email, error = emailErr)
        Lbl("Online review link")
        Text("Add the URL where clients can leave a review of the inspection. It's included with the report so clients can rate you.", style = T.ui(12.sp, color = V.ink3, lineHeight = 16.sp), modifier = Modifier.padding(start = 2.dp, bottom = 9.dp))
        VField("Review URL", p.reviewUrl, { v -> set { it.copy(reviewUrl = v) } }, Modifier.formField(form, "url"), placeholder = "https://g.page/r/your-review-link", keyboard = KeyboardType.Uri, error = urlErr)
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
        VBtn("Save profile", { if (form.submit()) vm.saveCompany(p.copy(logoFile = saved.logoFile, agreementName = saved.agreementName, agreementFile = saved.agreementFile)) }, icon = VIcons.check)
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
    if (!vm.isPlatformOwner) { OwnerOnly(vm, nav, "Feedback & support"); return }
    val platform by vm.platform.collectAsState()
    var email by rememberSaveable(platform.feedbackEmail) { mutableStateOf(platform.feedbackEmail) }
    VScreen("Feedback & support", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Hint("Owner admin — set the email address that receives help & feedback messages sent from the app.", Modifier.padding(top = 2.dp, bottom = 14.dp))
        val form = rememberForm()
        val err = form.check("email", email) { Checks.email(email) }
        VField("Feedback contact email", email, { email = it }, Modifier.formField(form, "email"), keyboard = KeyboardType.Email, error = err, required = true)
        VBtn("Save", { if (form.submit()) vm.saveFeedbackEmail(email) }, icon = VIcons.check)
    }
}

/** Shown instead of a platform-owner screen to anyone else (company admins included). */
@Composable
fun OwnerOnly(vm: AppViewModel, nav: NavHostController, title: String) {
    VScreen(title, companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Hint("Only the VIMS platform owner can view or change this setting.", Modifier.padding(top = 2.dp))
    }
}

/**
 * VIMS platform-owner setting "Report quality copy (BCC)": every report emailed from the app is also blind-copied to this
 * address for report-quality review (disclosed in the VIMS EULA). Stored app-level, not per company.
 */
@Composable
fun ReportBccScreen(vm: AppViewModel, nav: NavHostController) {
    if (!vm.isPlatformOwner) { OwnerOnly(vm, nav, "Report quality copy"); return }
    val platform by vm.platform.collectAsState()
    var on by rememberSaveable(platform.reportBccOn) { mutableStateOf(platform.reportBccOn) }
    var email by rememberSaveable(platform.reportBccEmail) { mutableStateOf(platform.reportBccEmail) }
    val form = rememberForm()
    val err = form.check("email", email) { if (on || email.isNotBlank()) Checks.email(email) else null }
    VScreen("Report quality copy", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Hint("Owner admin — every inspection report emailed from the app is also sent as a **blind carbon copy (BCC)** to this address, so report quality can be reviewed. Clients and agents don’t see this address. Disclosed in the VIMS EULA.",
            Modifier.padding(top = 2.dp, bottom = 14.dp))
        Row(Modifier.padding(bottom = 14.dp).fillMaxWidth().vCard(12.dp).padding(horizontal = 14.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("BCC every emailed report", style = T.ui(14.5.sp, FontWeight.Bold), modifier = Modifier.weight(1f))
            SingleChips(listOf("On", "Off"), if (on) "On" else "Off", { v -> if (v != null) on = v == "On" }, required = true, modifier = Modifier.width(140.dp))
        }
        VField("BCC address", email, { email = it }, Modifier.formField(form, "email"), placeholder = "you@company.com", keyboard = KeyboardType.Email, error = err, required = on)
        VBtn("Save", { if (form.submit()) vm.saveReportBcc(on, email) }, icon = VIcons.check)
    }
}

/** Delete account (app-store requirement): explains what is removed and requires typing DELETE. */
@Composable
fun DeleteAccountDialog(vm: AppViewModel, nav: NavHostController, onDismiss: () -> Unit) {
    var typed by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    val owner = vm.session.collectAsState().value?.role == com.vims.app.data.Role.OWNER
    com.vims.app.ui.components.ConfirmDialog(
        "Delete your account?",
        "This permanently deletes **your account and your inspections, photos, and reports on this device**." +
            (if (owner) " You own this company: if nobody else is on it, the company, its profile and logo are deleted too and the subscription is cancelled." else "") +
            " A deletion request is also sent to VIMS (completed within 10 working days, per the EULA). Type **DELETE** to confirm.",
        "Delete", danger = true, confirmEnabled = typed == "DELETE",
        onConfirm = { vm.deleteAccount(onError = { error = it }) { onDismiss(); nav.navigate(com.vims.app.ui.LoginR) { popUpTo(0) { inclusive = true } } } },
        onDismiss = onDismiss,
    ) {
        // TODO(backend): POST the deletion request to the server (10 working days per the EULA).
        VInput(typed, { typed = it.uppercase() }, Modifier.padding(bottom = 10.dp), placeholder = "Type DELETE", caps = KeyboardCapitalization.Characters, error = error)
    }
}
