package com.vims.app.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.BillingR
import com.vims.app.ui.InspectorsR
import com.vims.app.ui.SubStartedR
import com.vims.app.ui.SubscribeR
import com.vims.app.ui.components.RequiredHint
import com.vims.app.ui.components.BinfoRow
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.BtnRow
import com.vims.app.ui.components.Counter
import com.vims.app.ui.components.FieldLabel
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.LeadInitials
import com.vims.app.ui.components.ListRow
import com.vims.app.ui.components.Pill
import com.vims.app.ui.components.PillKind
import com.vims.app.ui.components.SuccessBlock
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VCard
import com.vims.app.ui.components.VField
import com.vims.app.ui.components.UserAvatar
import com.vims.app.ui.components.VInput
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.dashedBorder
import com.vims.app.ui.components.rich
import com.vims.app.ui.components.vCard
import com.vims.app.ui.goHome
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.CardBrand
import com.vims.app.util.CardTransform
import com.vims.app.util.Checks
import com.vims.app.util.ExpiryTransform
import com.vims.app.util.Filters
import com.vims.app.util.Fmt
import com.vims.app.util.formField
import com.vims.app.util.rememberForm
import java.time.LocalDate

@Composable
fun InspectorsScreen(vm: AppViewModel, nav: NavHostController) {
    val account by vm.account.collectAsState()
    val pricing = vm.pricing(vm.platform.collectAsState().value)
    val period = pricing.period(account)
    val per = com.vims.app.data.BillingPeriod.unit(period)
    val session by vm.session.collectAsState()
    val ctx = LocalContext.current
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
            "$who becomes the account owner (billing and company). You'll stay an admin. Only the new owner can transfer ownership again.",
            "Make owner", { vm.makeOwner(id); ownerTo = null }, { ownerTo = null },
        )
    }
    // QA Oct 14: removing an inspector is confirmed first.
    var removeId by rememberSaveable { mutableStateOf<String?>(null) }
    removeId?.let { id ->
        val who = account.inspectors.firstOrNull { it.id == id }
        if (who == null) removeId = null else com.vims.app.ui.components.ConfirmDialog(
            "Remove ${who.name}?",
            "They will no longer be able to sign in to your company's VIMS account, and their seat is freed.",
            "Remove", { vm.removeInspector(id); removeId = null }, { removeId = null }, danger = true,
        )
    }
    VScreen("Inspectors", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
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
        Text(rich((if (vm.iAmOwner(account)) "You (the account owner) are" else "The account owner is") + " an **admin** by default. Tap **Make admin** to grant any inspector admin access — admins can manage checklists, inspectors, the company profile, and settings. Nothing is hard-coded; roles are set here."),
            style = T.ui(12.sp, color = V.ink3, lineHeight = 18.sp), modifier = Modifier.padding(start = 2.dp, end = 2.dp, bottom = 12.dp))
        val photos by vm.memberPhotos.collectAsState()
        val photoVersion by vm.logoVersion.collectAsState()
        // Ownership: only the CURRENT owner can transfer it — they see "Make owner" on every other inspector (including a
        // previous owner, so it can be handed back); nobody can take it back themselves.
        val iAmOwner = vm.iAmOwner(account)
        val myEmail = session?.email.orEmpty()
        account.inspectors.forEach { ins ->
            val isMe = ins.email.equals(myEmail, ignoreCase = true)
            ListRow(
                "${ins.name} · ${ins.roleLabel}", ins.email.ifBlank { "no email yet" }, titleMaxLines = 2,
                lead = { UserAvatar(photos[ins.email.lowercase()]?.let { java.io.File(vm.filesDir, it) }, ins.initials, 44.dp, photoVersion) },
                end = {
                    if (ins.owner) Pill("Owner", PillKind.Done)
                    else if (canManage && !isMe) Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Pill(if (ins.admin) "Admin ✓" else "Make admin", if (ins.admin) PillKind.Prog else PillKind.New, dot = false) { vm.toggleAdmin(ins.id) }
                        if (iAmOwner && !isMe) Pill("Make owner", PillKind.Prog, dot = false) { ownerTo = ins.id }
                        Pill("Remove", PillKind.Queued, dot = false) { removeId = ins.id }
                    }
                },
            )
            if (ins.owner && canManage && !iAmOwner) Text("Only the owner can transfer ownership.", style = T.ui(12.sp, color = V.ink3),
                modifier = Modifier.padding(start = 4.dp, top = 0.dp, bottom = 12.dp))
        }
        Text(buildAnnotatedString {
            withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = V.ink)) { append("${account.inspectors.size} inspector${if (account.inspectors.size == 1) "" else "s"}") }
            if (!pricing.plan(account).perReport) append(" · ${if (period == com.vims.app.data.BillingPeriod.YEARLY) "yearly" else "monthly"} total ${Fmt.money(pricing.total(account.copy(seats = account.inspectors.size)))}")
        }, style = T.ui(12.5.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, top = 4.dp, bottom = 14.dp))
        if (canManage) AddBox {
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

@Composable
fun SubscribeScreen(vm: AppViewModel, nav: NavHostController) {
    val account by vm.account.collectAsState()
    val pricing = vm.pricing(vm.platform.collectAsState().value)
    // Client Oct 28: the plan and Monthly / Yearly choice are made here and saved with Start / Update subscription. A "Coming soon"
    // plan can't be chosen (a company still on one starts on the first plan that can be).
    var planId by rememberSaveable(account.planId) { mutableStateOf(pricing.plan(account).let { if (it.selectable) it.id else pricing.selectablePlans.firstOrNull()?.id ?: it.id }) }
    var period by rememberSaveable(account.billingPeriod) { mutableStateOf(account.billingPeriod) }
    val plan = pricing.plan(planId)
    val billed = pricing.period(plan, period)
    val yearly = billed == com.vims.app.data.BillingPeriod.YEARLY
    val total = pricing.total(plan, billed, account.seatCount)
    var card by rememberSaveable { mutableStateOf("") }
    var exp by rememberSaveable { mutableStateOf("") }
    var cvc by rememberSaveable { mutableStateOf("") }
    var holder by rememberSaveable { mutableStateOf("") }
    var zip by rememberSaveable { mutableStateOf("") }
    val form = rememberForm()
    VScreen("Subscription", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Row(Modifier.padding(bottom = 14.dp).fillMaxWidth().clip(RoundedCornerShape(12.dp)).border(1.dp, Color(0xFFC9DEE6), RoundedCornerShape(12.dp)).padding(horizontal = 14.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(11.dp)) {
            Icon(VIcons.clock, null, tint = V.brandDeep, modifier = Modifier.padding(top = 1.dp).size(19.dp))
            Text(
                if (account.active) rich("**Subscription active.** Change your plan or seats below.", V.bannerBold)
                else if (!vm.canStartInspection()) rich(if (account.trialUsedOnDevice) "**This device's free trial has already been used.** Subscribe to start new inspections." else "**Your free trial has ended.** Subscribe to start new inspections — your saved inspections and reports stay available.", V.bannerBold)
                else rich("**Free trial — ${vm.trialDaysLeft()} days left.** Set up your subscription now so access continues automatically when the trial ends.", V.bannerBold),
                style = T.ui(12.5.sp, color = V.brandDeep, lineHeight = 18.sp),
            )
        }
        Lbl("Choose your plan")
        if (pricing.selectablePlans.any { it.hasYearly }) {
            PeriodToggle(period) { period = it }
            Text(if (period == com.vims.app.data.BillingPeriod.YEARLY) "Billed once a year. Pay per report has no yearly option." else "Billed every month. Switch to Yearly to pay once a year.",
                style = T.ui(12.sp, color = V.ink3, lineHeight = 17.sp), modifier = Modifier.padding(start = 2.dp, top = 8.dp, bottom = 12.dp))
        }
        pricing.plans.forEach { p ->
            val on = p.id == planId && p.selectable
            val pPeriod = pricing.period(p, period)
            val price: @Composable () -> Unit = {
                Text(buildAnnotatedString {
                    append(Fmt.money(pricing.price(p, pPeriod)))
                    withStyle(SpanStyle(color = V.ink3, fontWeight = FontWeight.Normal, fontSize = 11.sp)) { append(pricing.unit(p, pPeriod)) }
                }, style = T.mono(15.sp, FontWeight.SemiBold, if (p.selectable) V.ink else V.ink3))
            }
            // Team QA Oct 22: on small phones / large text the price moves under the plan name instead of squeezing the name and
            // description into a narrow column.
            androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxWidth()) {
            val narrow = maxWidth < 380.dp * androidx.compose.ui.platform.LocalDensity.current.fontScale.coerceAtLeast(1f)
            Row(
                Modifier.padding(bottom = 10.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(if (p.selectable) V.paper else V.paper2)
                    .border(if (on) 2.dp else 1.5.dp, if (on) V.brand else V.line, RoundedCornerShape(14.dp))
                    .then(if (p.selectable) Modifier.clickable(role = Role.RadioButton) { planId = p.id } else Modifier.semantics { disabled() })
                    .padding(horizontal = 16.dp, vertical = 15.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp),
            ) {
                Box(Modifier.size(22.dp).clip(CircleShape).border(2.dp, if (on) V.brand else V.line, CircleShape), contentAlignment = Alignment.Center) {
                    if (on) Box(Modifier.size(11.dp).clip(CircleShape).background(V.brand))
                }
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(p.name, style = T.ui(15.sp, FontWeight.Bold, if (p.selectable) V.ink else V.ink2), modifier = Modifier.weight(1f, fill = false))
                        if (p.comingSoon) ComingSoonTag()
                    }
                    if (narrow) price()
                    Text(p.desc, style = T.ui(12.5.sp, color = V.ink3, lineHeight = 17.sp), softWrap = true)
                    if (p.comingSoon) Text("Not available yet — it can be chosen when it launches.", style = T.ui(11.5.sp, color = V.ink3), modifier = Modifier.padding(top = 4.dp))
                    else if (period == com.vims.app.data.BillingPeriod.YEARLY && !p.hasYearly && !p.perReport) Text("Monthly only", style = T.ui(11.5.sp, color = V.ink3), modifier = Modifier.padding(top = 4.dp))
                }
                if (!narrow) price()
            }
            }
        }
        if (!plan.perReport) {
            Lbl("Inspector seats")
            // Seats 1 – 50 (docs "Number limits"); never fewer than the inspectors already on the license.
            Counter("Inspectors on this license", account.seatCount, { vm.setSeats(account.seatCount - 1) }, { vm.setSeats(account.seatCount + 1) },
                min = maxOf(1, account.inspectors.size), max = com.vims.app.util.Limits.SEATS_MAX)
            Text(rich("First inspector included · each additional **${Fmt.money(pricing.extra(billed))}${com.vims.app.data.BillingPeriod.unit(billed)}**"), style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, end = 2.dp, top = 2.dp))
        }
        VCard(Modifier.padding(top = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(if (plan.perReport) "Billing" else if (yearly) "Yearly total" else "Monthly total", style = T.ui(15.sp, FontWeight.Bold))
                    Text(if (plan.perReport) "No monthly fee" else "${plan.name} · billed ${if (yearly) "yearly" else "monthly"}", style = T.ui(12.sp, color = V.ink3))
                }
                Text(if (plan.perReport) "${Fmt.money(plan.price)} / report" else "${Fmt.money(total)}${com.vims.app.data.BillingPeriod.unit(billed)}", style = T.mono(22.sp, FontWeight.SemiBold, V.brand))
            }
        }
        Lbl("Payment — via Square")
        // QA Oct 14: an update remembers the card. Only brand + last 4 + expiry are kept (a stand-in for Square's card on file,
        // TODO(backend): Square Cards API) — the number and CVC are never stored.
        val onFile = account.cardOnFile?.takeIf { !it.expired() }
        var useOnFile by rememberSaveable(onFile?.last4) { mutableStateOf(onFile != null) }
        if (onFile != null) {
            CardChoice(onFile.label, "Card on file", useOnFile) { useOnFile = true }
            CardChoice("Use a different card", "Enter a new card below", !useOnFile) { useOnFile = false }
            Spacer(Modifier.height(4.dp))
        } else account.cardOnFile?.let { expired ->
            Text("${expired.label} has expired — enter a new card.", style = T.ui(12.5.sp, color = V.c1), modifier = Modifier.padding(start = 2.dp, bottom = 10.dp))
        }
        val newCard = onFile == null || !useOnFile
        if (newCard) {
        RequiredHint()
        // TODO(backend): replace with the Square In-App Payments SDK card entry (tokenized); raw card data is never stored.
        val brand = CardBrand.of(card)
        val amex = brand == CardBrand.AMEX
        val cardErr = form.check("card", card) { Checks.cardNumber(card) }
        val expErr = form.check("exp", exp) { Checks.expiry(exp) }
        val cvcErr = form.check("cvc", cvc) { Checks.cvc(cvc, amex) }
        val holderErr = form.check("holder", holder) { Checks.required(holder, "Enter the name on the card") }
        val zipErr = form.check("zip", zip) { Checks.postalCode(zip) }
        Column(Modifier.padding(bottom = 13.dp).formField(form, "card")) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                FieldLabel("Card number", required = true)
                Spacer(Modifier.weight(1f))
                if (brand != CardBrand.UNKNOWN) Text(brand.label, style = T.ui(12.sp, FontWeight.SemiBold, V.brandDeep), modifier = Modifier.padding(bottom = 7.dp))
            }
            VInput(card, { card = it }, placeholder = "1234 5678 9012 3456", keyboard = KeyboardType.Number, visual = CardTransform, filter = Filters::cardNumber, error = cardErr)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f).formField(form, "exp")) { FieldLabel("Expiry", required = true); VInput(exp, { exp = it }, placeholder = "MM/YY", keyboard = KeyboardType.Number, visual = ExpiryTransform, filter = Filters::expiry, error = expErr) }
            Column(Modifier.weight(1f).formField(form, "cvc")) { FieldLabel("CVC", required = true); VInput(cvc, { cvc = it }, placeholder = if (amex) "1234" else "123", keyboard = KeyboardType.NumberPassword, filter = { Filters.cvc(it, amex) }, error = cvcErr) }
        }
        VField("Cardholder name", holder, { holder = it }, Modifier.padding(top = 13.dp).formField(form, "holder"), placeholder = "Name on card", caps = KeyboardCapitalization.Words, filter = Filters::personName, error = holderErr, required = true)
        // US ZIP or a Canadian / UK postal code: letters + digits, uppercase (text keyboard with caps).
        VField("Billing ZIP / postal code", zip, { zip = it }, Modifier.formField(form, "zip"), placeholder = "84015", caps = KeyboardCapitalization.Characters, filter = Filters::postalCode, error = zipErr, bottom = 0.dp, required = true)
        }
        Row(Modifier.padding(start = 2.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(VIcons.lock, null, tint = V.ink3, modifier = Modifier.size(14.dp))
            Text("Secured by Square · ${if (plan.perReport) "charged per report" else "auto-renews ${if (yearly) "yearly" else "monthly"}"} · cancel anytime", style = T.ui(12.sp, color = V.ink3))
        }
        VBtn(if (account.active) "Update subscription" else "Start subscription", {
            if (!newCard || form.submit()) vm.startSubscription(plan.id, billed, if (newCard) card else null, if (newCard) exp else null) {
                card = ""; exp = ""; cvc = ""; nav.navigate(SubStartedR) { popUpTo<SubscribeR> { inclusive = true } }
            }
        }, Modifier.padding(top = 16.dp), icon = VIcons.check)
    }
}

/** "Visa •••• 4242 (exp 08/28) — Use this card" / "Use a different card" radio row. */
@Composable
private fun CardChoice(title: String, sub: String, on: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.padding(bottom = 10.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(V.paper).border(if (on) 2.dp else 1.5.dp, if (on) V.brand else V.line, RoundedCornerShape(14.dp))
            .clickable(role = Role.RadioButton, onClick = onClick).padding(horizontal = 16.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp),
    ) {
        Box(Modifier.size(22.dp).clip(CircleShape).border(2.dp, if (on) V.brand else V.line, CircleShape), contentAlignment = Alignment.Center) {
            if (on) Box(Modifier.size(11.dp).clip(CircleShape).background(V.brand))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = T.ui(14.5.sp, FontWeight.Bold))
            Text(if (sub == "Card on file") "Use this card" else sub, style = T.ui(12.5.sp, color = V.ink3))
        }
        if (sub == "Card on file") Icon(VIcons.card, null, tint = V.ink3, modifier = Modifier.size(20.dp))
    }
}

@Composable
fun SubStartedScreen(vm: AppViewModel, nav: NavHostController) {
    val account by vm.account.collectAsState()
    val pricing = vm.pricing(vm.platform.collectAsState().value)
    val plan = pricing.plan(account)
    val period = pricing.period(account)
    // Client Oct 28: the confirmation names the billing period and the amount charged each period.
    val what = if (plan.perReport) "**${plan.name}** plan (${Fmt.money(plan.price)} per report)"
        else "**${plan.name}** plan, billed **${if (period == com.vims.app.data.BillingPeriod.YEARLY) "yearly" else "monthly"}** (${Fmt.money(pricing.total(account))}${com.vims.app.data.BillingPeriod.unit(period)})"
    VScreen("Subscription active", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        SuccessBlock("Subscription active", "Your $what is set up with auto-pay through Square. Access continues after your trial with no interruption.") {
            VBtn("View subscription", { nav.navigate(BillingR) { popUpTo<SubStartedR> { inclusive = true } } })
            VBtn("Back to inspections", { nav.goHome() }, Modifier.padding(top = 10.dp), BtnKind.Ghost)
        }
    }
}

@Composable
fun BillingScreen(vm: AppViewModel, nav: NavHostController) {
    val a by vm.account.collectAsState()
    val pricing = vm.pricing(vm.platform.collectAsState().value)
    val plan = pricing.plan(a)
    val period = pricing.period(a)
    val yearly = period == com.vims.app.data.BillingPeriod.YEARLY
    val session by vm.session.collectAsState()
    var confirmCancel by rememberSaveable { mutableStateOf(false) }
    val endDate = a.periodEndEpochDay?.let { Fmt.date(LocalDate.ofEpochDay(it)) } ?: "the end of the billing period"
    VScreen("Subscription", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Column(Modifier.padding(bottom = 12.dp).fillMaxWidth().vCard()) {
            BinfoRow({ Text("Status", style = T.ui(14.sp)) }, {
                when {
                    a.active && a.cancelled -> Pill("Cancelled · active until $endDate", PillKind.Queued)
                    a.active -> Pill("Active · auto-pay", PillKind.Done)
                    !vm.canStartInspection() -> Pill("Trial ended", PillKind.Queued)
                    else -> Pill("Trial · ${vm.trialDaysLeft()}d left", PillKind.Queued)
                }
            })
            BinfoRow("Plan", "${plan.name} · ${Fmt.money(pricing.price(plan, period))}${pricing.unit(plan, period)}")
            if (!plan.perReport) BinfoRow("Billing period", if (yearly) "Yearly" else "Monthly")
            if (!plan.perReport) BinfoRow("Inspectors", "${a.seatCount} (${maxOf(0, a.seatCount - 1)} × ${Fmt.money(pricing.extra(period))}${com.vims.app.data.BillingPeriod.unit(period)})")
            BinfoRow(if (plan.perReport) "Billing" else if (yearly) "Yearly total" else "Monthly total", subTotalLabel(vm))
            BinfoRow("Payment", if (a.active) "Square · ${a.cardOnFile?.label ?: "Card"}" else "Not set up")
            val next = a.periodEndEpochDay?.let { Fmt.date(LocalDate.ofEpochDay(it)) }
            BinfoRow(if (a.active && a.cancelled) "Access ends" else if (a.active) "Next billing" else if (!vm.canStartInspection()) "Trial" else "Trial ends",
                if (a.active) next ?: "—" else if (!vm.canStartInspection()) "Ended" else "in ${vm.trialDaysLeft()} days", last = true)
        }
        VBtn("Manage inspectors", { nav.navigate(InspectorsR) }, kind = BtnKind.Ghost, icon = VIcons.usersSmall)
        VBtn(if (a.active) "Change plan / payment" else "Set up subscription", { nav.navigate(SubscribeR) }, Modifier.padding(top = 10.dp), if (a.active) BtnKind.Ghost else BtnKind.Primary)
        // Cancel (EULA 12.3): active subscriptions only, owner / admins only. TODO(backend): Square cancel / resume.
        if (a.active && session?.isAdmin != false) {
            when {
                a.cancelled -> {
                    VCard(Modifier.padding(top = 14.dp), bottom = 0.dp) {
                        Text(rich("Your subscription is cancelled and stays active until **$endDate**. Download anything you need within 30 days after it ends.", V.ink),
                            style = T.ui(13.sp, color = V.ink2, lineHeight = 19.5.sp))
                    }
                    VBtn("Undo cancellation", { vm.resumeSubscription() }, Modifier.padding(top = 10.dp), BtnKind.Ghost)
                }
                confirmCancel -> {
                    Column(Modifier.padding(top = 14.dp).fillMaxWidth().vCard(border = V.c1).padding(horizontal = 16.dp, vertical = 15.dp)) {
                        Text("Cancel your subscription?", style = T.ui(13.sp, FontWeight.Bold, V.ink))
                        Text(rich("It stays active until the end of the current billing period (**$endDate**), then stops renewing. There are no refunds or prorated charges. Download anything you need within 30 days after it ends.", V.ink),
                            style = T.ui(13.sp, color = V.ink2, lineHeight = 19.5.sp))
                    }
                    BtnRow(Modifier.padding(top = 0.dp)) {
                        VBtn("Keep subscription", { confirmCancel = false }, Modifier.weight(1f), BtnKind.Ghost)
                        VBtn("Yes, cancel", { confirmCancel = false; vm.cancelSubscription() }, Modifier.weight(1f), BtnKind.Danger)
                    }
                }
                else -> VBtn("Cancel subscription", { confirmCancel = true }, Modifier.padding(top = 10.dp), BtnKind.GhostDanger)
            }
        }
    }
}

/** Monthly / Yearly choice on Subscribe (data v1.11 `subscription.billingPeriods`). */
@Composable
private fun PeriodToggle(period: String, onChange: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(V.paper3).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        listOf(com.vims.app.data.BillingPeriod.MONTHLY, com.vims.app.data.BillingPeriod.YEARLY).forEach { p ->
            val on = p == period
            Box(
                Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(9.dp)).background(if (on) V.paper else Color.Transparent)
                    .then(if (on) Modifier.border(1.dp, V.line, RoundedCornerShape(9.dp)) else Modifier)
                    .clickable(role = Role.RadioButton, onClickLabel = com.vims.app.data.BillingPeriod.label(p)) { onChange(p) },
                contentAlignment = Alignment.Center,
            ) {
                Text(com.vims.app.data.BillingPeriod.label(p), style = T.ui(14.sp, if (on) FontWeight.Bold else FontWeight.Medium, if (on) V.brandDeep else V.ink2))
            }
        }
    }
}
