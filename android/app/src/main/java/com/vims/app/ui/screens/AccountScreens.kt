package com.vims.app.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.components.BinfoRow
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.LeadInitials
import com.vims.app.ui.components.ListRow
import com.vims.app.ui.components.Pill
import com.vims.app.ui.components.PillKind
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VCard
import com.vims.app.ui.components.VField
import com.vims.app.ui.components.UserAvatar
import com.vims.app.ui.components.VInput
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.dashedBorder
import com.vims.app.ui.components.rich
import com.vims.app.ui.components.vCard
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Checks
import com.vims.app.util.Filters
import com.vims.app.util.Fmt
import com.vims.app.util.formField
import com.vims.app.util.rememberForm

@Composable
fun InspectorsScreen(vm: AppViewModel, nav: NavHostController) {
    val account by vm.account.collectAsState()
    val pricing = vm.pricing(vm.platform.collectAsState().value)
    val period = pricing.period(account)
    val per = com.vims.app.data.BillingPeriod.unit(period)
    val session by vm.session.collectAsState()
    val ctx = LocalContext.current
    // features.companyJoin false: no new accounts can reach this company. Accounts already on the device keep working; a list row
    // with no account here (added by an earlier build) can't sign in, so roles on it would mean nothing.
    val joinOn = vm.companyJoinEnabled
    val deviceEmails by vm.memberEmails.collectAsState()
    var name by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    val canManage = session?.isAdmin != false
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    val form = rememberForm()
    var ownerTo by rememberSaveable { mutableStateOf<String?>(null) }
    ownerTo?.let { id ->
        val who = account.inspectors.firstOrNull { it.id == id }?.name ?: "this admin"
        com.vims.app.ui.components.ConfirmDialog(
            "Make $who the owner?",
            "$who becomes the account owner (company and team). You'll stay an admin. Only the new owner can transfer ownership again.",
            "Make owner", { vm.makeOwner(id); ownerTo = null }, { ownerTo = null },
        )
    }
    // QA Oct 14: removing an inspector is confirmed first.
    var removeId by rememberSaveable { mutableStateOf<String?>(null) }
    removeId?.let { id ->
        val who = account.inspectors.firstOrNull { it.id == id }
        if (who == null) removeId = null else com.vims.app.ui.components.ConfirmDialog(
            "Remove ${who.name}?",
            if (joinOn) "They will no longer be able to sign in to your company's VIMS account, and their seat is freed."
            else "They have no account on this device, so this only removes them from this list.",
            "Remove", { vm.removeInspector(id); removeId = null }, { removeId = null }, danger = true,
        )
    }
    VScreen("Inspectors", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        if (!joinOn) Hint("The accounts in your company on this device. An account stays on the device it was created on, so other inspectors use their own VIMS account on their own phone or tablet.", Modifier.padding(top = 2.dp, bottom = 12.dp))
        if (joinOn) {
        Hint("Add inspector accounts under your company license. First inspector is included; each additional is **${Fmt.money(pricing.extra(period))}$per**.", Modifier.padding(top = 2.dp, bottom = 12.dp))
        Column(Modifier.padding(bottom = 14.dp).fillMaxWidth().clip(RoundedCornerShape(13.dp)).background(V.paper).dashedBorder(V.brand, 13.dp).padding(horizontal = 16.dp, vertical = 15.dp)) {
            Text("COMPANY JOIN CODE", style = T.mono(10.5.sp, color = V.ink3, letterSpacing = 0.11.em), modifier = Modifier.padding(bottom = 7.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(account.companyCode, style = T.mono(24.sp, FontWeight.SemiBold, V.brandDeep, 0.18.em), modifier = Modifier.weight(1f))
                Row(
                    Modifier.heightIn(min = 44.dp).clip(RoundedCornerShape(9.dp)).background(V.paper3).clickable(role = Role.Button) {
                        (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager).setPrimaryClip(ClipData.newPlainText("Company code", account.companyCode))
                        vm.toast("Code ${account.companyCode} copied")
                    }.padding(horizontal = 12.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(VIcons.copy, null, tint = V.brandDeep, modifier = Modifier.size(15.dp))
                    Text("Copy", style = T.ui(12.5.sp, FontWeight.SemiBold, V.brandDeep))
                }
            }
            Text(rich("Share this code with an inspector. They download VIMS, tap **Join a company with a code**, and their account links to your license & billing."),
                style = T.ui(12.sp, color = V.ink3, lineHeight = 17.sp), modifier = Modifier.padding(top = 9.dp))
        }
        }
        if (joinOn || account.inspectors.size > 1) Text(rich((if (vm.iAmOwner(account)) "You (the account owner) are" else "The account owner is") + " an **admin** by default. Tap **Make admin** to grant any inspector admin access — admins can manage checklists, inspectors, the company profile, and settings. Nothing is hard-coded; roles are set here."),
            style = T.ui(12.sp, color = V.ink3, lineHeight = 18.sp), modifier = Modifier.padding(start = 2.dp, end = 2.dp, bottom = 12.dp))
        val photos by vm.memberPhotos.collectAsState()
        val photoVersion by vm.logoVersion.collectAsState()
        // Ownership: only the CURRENT owner can transfer it — they see "Make owner" on every other inspector (including a
        // previous owner, so it can be handed back); nobody can take it back themselves.
        val iAmOwner = vm.iAmOwner(account)
        val myEmail = session?.email.orEmpty()
        account.inspectors.forEach { ins ->
            val isMe = ins.email.equals(myEmail, ignoreCase = true)
            val hasAccount = joinOn || ins.email.lowercase() in deviceEmails
            ListRow(
                "${ins.name} · ${ins.roleLabel}", ins.email.ifBlank { "no email yet" } + if (hasAccount) "" else " · no account on this device", titleMaxLines = 2,
                lead = { UserAvatar(photos[ins.email.lowercase()]?.let { java.io.File(vm.filesDir, it) }, ins.initials, 44.dp, photoVersion) },
                end = {
                    if (ins.owner) Pill("Owner", PillKind.Done)
                    else if (canManage && !isMe) Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        if (hasAccount) Pill(if (ins.admin) "Admin ✓" else "Make admin", if (ins.admin) PillKind.Prog else PillKind.New, dot = false) { vm.toggleAdmin(ins.id) }
                        if (hasAccount && iAmOwner && !isMe) Pill("Make owner", PillKind.Prog, dot = false) { ownerTo = ins.id }
                        // Remove never ended an account's sign-in, so with no way to rejoin it's only for rows with no account here.
                        if (joinOn || !hasAccount) Pill("Remove", PillKind.Queued, dot = false) { removeId = ins.id }
                    }
                },
            )
            if (ins.owner && canManage && !iAmOwner) Text("Only the owner can transfer ownership.", style = T.ui(12.sp, color = V.ink3),
                modifier = Modifier.padding(start = 4.dp, top = 0.dp, bottom = 12.dp))
        }
        Text(buildAnnotatedString {
            withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = V.ink)) { append("${account.inspectors.size} inspector${if (account.inspectors.size == 1) "" else "s"}") }
            if (joinOn && !pricing.plan(account).perReport) append(" · ${if (period == com.vims.app.data.BillingPeriod.YEARLY) "yearly" else "monthly"} total ${Fmt.money(pricing.total(account.copy(seats = account.inspectors.size)))}")
        }, style = T.ui(12.5.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, top = 4.dp, bottom = 14.dp))
        if (canManage && joinOn) AddBox {
            val nameErr = form.check("name", name) { Checks.required(name, "Enter the inspector's name") }
            val emailErr = form.check("email", email) {
                Checks.email(email) ?: if (account.inspectors.any { it.email.equals(email.trim(), true) }) "That email is already on your team"
                else if (account.inspectors.size >= com.vims.app.util.Limits.SEATS_MAX) "A license has up to ${com.vims.app.util.Limits.SEATS_MAX} inspectors" else null
            }
            VField("Inspector name", name, { name = it }, Modifier.formField(form, "name"), placeholder = "Full name", caps = KeyboardCapitalization.Words, filter = Filters::personName, error = nameErr, required = true, bottom = 0.dp)
            VField("Email", email, { email = it }, Modifier.formField(form, "email"), placeholder = "inspector@email.com", keyboard = KeyboardType.Email, error = emailErr, required = true, bottom = 0.dp)
            VBtn("Add inspector", { if (form.submit() && vm.addInspector(name, email)) { name = ""; email = ""; form.reset(); focus.clearFocus() } }, icon = VIcons.plus, minHeight = 48.dp)
        }
    }
}

/**
 * Plans (shared subscription.store.plansScreen): App only Monthly and Yearly and Pay per report at store prices, Portal + App
 * Coming soon, Restore Purchases, Manage subscription, the license agreement and the privacy policy.
 */
@Composable
fun SubscribeScreen(vm: AppViewModel, nav: NavHostController) {
    val store by vm.billing.status.collectAsState()
    val plans by vm.billing.plans.collectAsState()
    val session by vm.session.collectAsState()
    val ctx = LocalContext.current
    val activity = androidx.activity.compose.LocalActivity.current
    val ids = vm.config.subscription.store.android
    LaunchedEffect(Unit) { vm.loadPlans(); vm.billing.refreshAsync() }
    VScreen("Plans", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        PlanStatus(vm, store, session?.platformOwner == true)
        when (val p = plans) {
            com.vims.app.services.PlansState.Loading -> Hint("Loading plans…", Modifier.padding(bottom = 12.dp))
            com.vims.app.services.PlansState.Unavailable -> PlansCantLoad(vm)
            is com.vims.app.services.PlansState.Loaded -> {
                val subs = p.options.filter { it.kind != com.vims.app.services.PlanKind.CREDIT }
                if (subs.isNotEmpty()) Lbl(vm.pricing().plans.firstOrNull { it.id == "app" }?.name ?: "App only")
                subs.forEach { o ->
                    val plan = if (o.kind == com.vims.app.services.PlanKind.MONTHLY) ids.monthlyBasePlan else ids.yearlyBasePlan
                    val label = com.vims.app.data.BillingPeriod.label(plan)
                    val current = store.active && store.basePlan == plan
                    PlanOptionCard(o, "Renews automatically every ${if (plan == ids.yearlyBasePlan) "year" else "month"}",
                        when { current -> "Current plan"; store.active -> "Switch to $label"; else -> "Subscribe $label" },
                        // On hold, Play refuses a new purchase of the same subscription: the fix is on its own page.
                        enabled = !current && !store.onHold && !store.pendingSub) { activity?.let { vm.buy(it, o.kind) } }
                }
                p.options.firstOrNull { it.kind == com.vims.app.services.PlanKind.CREDIT }?.let { o ->
                    Lbl(vm.pricing().plans.firstOrNull { it.perReport }?.name ?: "Pay per report")
                    PlanOptionCard(o, "No subscription. Pay for a report when you need it.", "Buy 1 report credit", enabled = !store.pendingCredit) { activity?.let { vm.buy(it, o.kind) } }
                }
                Text("Payment is charged to your Google Play account. Subscriptions renew automatically unless canceled at least 24 hours before the end of the current period. Manage or cancel in your account settings.",
                    style = T.ui(12.sp, color = V.ink3, lineHeight = 17.sp), modifier = Modifier.padding(start = 2.dp, end = 2.dp, top = 2.dp, bottom = 14.dp))
            }
        }
        vm.pricing().plans.filter { it.comingSoon }.forEach { c ->
            Column(Modifier.padding(bottom = 14.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(V.paper2).border(1.5.dp, V.line, RoundedCornerShape(14.dp)).padding(horizontal = 16.dp, vertical = 15.dp)
                .semantics { disabled() }) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(c.name, style = T.ui(15.sp, FontWeight.Bold, V.ink2), modifier = Modifier.weight(1f, fill = false))
                    ComingSoonTag()
                }
                Text(c.desc, style = T.ui(12.5.sp, color = V.ink3, lineHeight = 17.sp), modifier = Modifier.padding(top = 4.dp))
            }
        }
        VBtn("Restore Purchases", { vm.restorePurchases() }, kind = BtnKind.Ghost)
        VBtn("Manage subscription", { openUrl(ctx, vm, vm.manageSubscriptionUrl()) }, Modifier.padding(top = 10.dp), BtnKind.Ghost)
        Row(Modifier.padding(top = 6.dp).fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            com.vims.app.ui.components.TextLink("License agreement", { nav.navigate(com.vims.app.ui.EulaR) }, Modifier.weight(1f))
            com.vims.app.ui.components.TextLink("Privacy Policy", { openUrl(ctx, vm, "https://vimsinspect.com/privacy.html") }, Modifier.weight(1f))
        }
    }
}

/** Shared plansScreen, when the store can't give prices. No reference prices: only the store's are ever shown. */
@Composable
fun PlansCantLoad(vm: AppViewModel) {
    VCard {
        Text("Plans can't load right now. Check your connection and try again.", style = T.ui(14.sp, color = V.ink, lineHeight = 20.sp))
        VBtn("Try again", { vm.loadPlans(); vm.billing.refreshAsync() }, Modifier.padding(top = 12.dp), BtnKind.Ghost)
    }
}

/** Opens Play's subscription page or the privacy policy in whatever handles the link. */
fun openUrl(ctx: Context, vm: AppViewModel, url: String) {
    try { ctx.startActivity(android.content.Intent(android.content.Intent.ACTION_VIEW, android.net.Uri.parse(url))) }
    catch (_: Exception) { vm.toast("Couldn't open that. Check that a browser or Google Play is set up.") }
}

@Composable
private fun PlanStatus(vm: AppViewModel, store: com.vims.app.services.BillingStatus, masterAdmin: Boolean) {
    val account by vm.account.collectAsState()
    val days = vm.trialDaysLeft()
    val canStart = vm.canStartInspection()
    Column(Modifier.padding(bottom = 12.dp).fillMaxWidth().vCard()) {
        BinfoRow({ Text("Status", style = T.ui(14.sp)) }, {
            when {
                masterAdmin -> Pill("Master admin", PillKind.Done, dot = false)
                store.active && store.cached -> Pill("Active · last verified", PillKind.Done)
                store.active -> Pill("Active", PillKind.Done)
                store.onHold -> Pill("Payment problem", PillKind.Queued)
                days > 0 -> Pill("Trial · ${days}d left", PillKind.Queued)
                store.ended -> Pill("Subscription ended", PillKind.Queued)
                else -> Pill("Trial ended", PillKind.Queued)
            }
        })
        if (masterAdmin) BinfoRow("Subscription", "No subscription needed", last = store.credits == 0 && !store.active)
        if (store.active) BinfoRow("Plan", vm.planName(store), last = store.credits == 0 && store.autoRenewing)
        if (store.active && !store.autoRenewing) BinfoRow("Renewal", "Off · ends about ${store.expiryMillis?.let { Fmt.date(java.time.Instant.ofEpochMilli(it).atZone(java.time.ZoneId.systemDefault()).toLocalDate()) } ?: "the end of the period"}", last = store.credits == 0)
        if (store.credits > 0 || (!store.active && !masterAdmin)) BinfoRow("Report credits", "${store.credits}", last = true)
    }
    val note = when {
        store.onHold -> "**Your payment didn't go through.** Open **Manage subscription** to fix it on Google Play, and access comes back. Your saved inspections and reports stay available."
        store.pendingSub || store.pendingCredit -> "**Payment pending.** Access starts once Google Play confirms it."
        masterAdmin || store.active -> null
        !canStart && account.trialUsedOnDevice && !store.ended -> "**This device's free trial has already been used.** Choose a plan to start new inspections."
        !canStart -> "**${if (store.ended) "Your subscription has ended." else "Your free trial has ended."}** Choose a plan to start new inspections. Your saved inspections and reports stay available."
        else -> null
    }
    if (note != null) Row(Modifier.padding(bottom = 14.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).border(1.dp, Color(0xFFC9DEE6), RoundedCornerShape(12.dp)).padding(horizontal = 14.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(11.dp)) {
        Icon(VIcons.clock, null, tint = V.brandDeep, modifier = Modifier.padding(top = 1.dp).size(19.dp))
        Text(rich(note, V.bannerBold), style = T.ui(12.5.sp, color = V.brandDeep, lineHeight = 18.sp))
    }
}

/** One purchasable option: title, length and price before buying (shared plansScreen). */
@Composable
private fun PlanOptionCard(o: com.vims.app.services.PlanOption, sub: String, action: String, enabled: Boolean, onBuy: () -> Unit) {
    Column(Modifier.padding(bottom = 10.dp).fillMaxWidth().vCard(14.dp).padding(horizontal = 16.dp, vertical = 15.dp)) {
        Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Column(Modifier.weight(1f)) {
                Text(o.title, style = T.ui(15.sp, FontWeight.Bold))
                Text(o.length, style = T.ui(13.sp, FontWeight.Medium, V.ink2), modifier = Modifier.padding(top = 2.dp))
            }
            Text(o.price, style = T.mono(17.sp, FontWeight.SemiBold, V.brand))
        }
        Text(sub, style = T.ui(12.5.sp, color = V.ink3, lineHeight = 17.sp), modifier = Modifier.padding(top = 4.dp, bottom = 10.dp))
        VBtn(action, onBuy, kind = if (enabled) BtnKind.Primary else BtnKind.Ghost, enabled = enabled, minHeight = 48.dp)
    }
}
