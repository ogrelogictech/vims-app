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
import com.vims.app.ui.components.BinfoRow
import com.vims.app.ui.components.BtnKind
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
    val session by vm.session.collectAsState()
    val ctx = LocalContext.current
    var name by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    val canManage = session?.isAdmin != false
    val focus = androidx.compose.ui.platform.LocalFocusManager.current
    val form = rememberForm()
    VScreen("Inspectors", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Hint("Add inspector accounts under your company license. First inspector is included; each additional is **${Fmt.money(account.extraInspectorMonthly)}/mo**.", Modifier.padding(top = 2.dp, bottom = 12.dp))
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
        Text(rich("You (the account owner) are an **admin** by default. Tap **Make admin** to grant any inspector admin access — admins can manage checklists, plans, the company profile, and settings. Nothing is hard-coded; roles are set here."),
            style = T.ui(12.sp, color = V.ink3, lineHeight = 18.sp), modifier = Modifier.padding(start = 2.dp, end = 2.dp, bottom = 12.dp))
        account.inspectors.forEach { ins ->
            ListRow(
                "${ins.name} · ${ins.roleLabel}", ins.email.ifBlank { "no email yet" }, lead = { LeadInitials(ins.initials) }, titleMaxLines = 2,
                end = {
                    if (ins.owner) Pill("Admin", PillKind.Done)
                    else if (canManage) Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Pill(if (ins.admin) "Admin ✓" else "Make admin", if (ins.admin) PillKind.Prog else PillKind.New, dot = false) { vm.toggleAdmin(ins.id) }
                        Pill("Remove", PillKind.Queued, dot = false) { vm.removeInspector(ins.id) }
                    }
                },
            )
        }
        Text(buildAnnotatedString {
            withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = V.ink)) { append("${account.inspectors.size} inspector${if (account.inspectors.size == 1) "" else "s"}") }
            append(" · monthly total ${Fmt.money(vm.monthlyTotal(account.copy(seats = account.inspectors.size)))}")
        }, style = T.ui(12.5.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, top = 4.dp, bottom = 14.dp))
        if (canManage) AddBox {
            val nameErr = form.check("name", name) { Checks.required(name, "Enter the inspector's name") }
            val emailErr = form.check("email", email) {
                Checks.email(email) ?: if (account.inspectors.any { it.email.equals(email.trim(), true) }) "That email is already on your team" else null
            }
            VInput(name, { name = it }, Modifier.formField(form, "name"), placeholder = "Inspector name", textSize = 14f, caps = KeyboardCapitalization.Words, filter = Filters::personName, error = nameErr)
            VInput(email, { email = it }, Modifier.formField(form, "email"), placeholder = "inspector@email.com", keyboard = KeyboardType.Email, textSize = 14f, error = emailErr)
            VBtn("Add inspector", { if (form.submit() && vm.addInspector(name, email)) { name = ""; email = ""; form.reset(); focus.clearFocus() } }, icon = VIcons.plus, minHeight = 48.dp)
        }
    }
}

@Composable
fun SubscribeScreen(vm: AppViewModel, nav: NavHostController) {
    val account by vm.account.collectAsState()
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
                else rich("**Free trial — ${vm.trialDaysLeft()} days left.** Set up your subscription now so access continues automatically when the trial ends.", V.bannerBold),
                style = T.ui(12.5.sp, color = V.brandDeep, lineHeight = 18.sp),
            )
        }
        Lbl("Choose your plan")
        account.plans.forEach { p ->
            val on = p.id == account.planId
            Row(
                Modifier.padding(bottom = 10.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(V.paper).border(if (on) 2.dp else 1.5.dp, if (on) V.brand else V.line, RoundedCornerShape(14.dp))
                    .clickable(role = Role.RadioButton) { vm.selectPlan(p.id) }.padding(horizontal = 16.dp, vertical = 15.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp),
            ) {
                Box(Modifier.size(22.dp).clip(CircleShape).border(2.dp, if (on) V.brand else V.line, CircleShape), contentAlignment = Alignment.Center) {
                    if (on) Box(Modifier.size(11.dp).clip(CircleShape).background(V.brand))
                }
                Column(Modifier.weight(1f)) {
                    Text(p.name, style = T.ui(15.sp, FontWeight.Bold))
                    Text(p.desc, style = T.ui(12.5.sp, color = V.ink3))
                    if (p.id == "portal") Text("Available when the web portal launches (Phase 2)", style = T.mono(9.sp, color = V.ink3),
                        modifier = Modifier.padding(top = 4.dp).clip(RoundedCornerShape(6.dp)).background(V.paper3).padding(horizontal = 6.dp, vertical = 2.dp))
                }
                Text(buildAnnotatedString {
                    append(Fmt.money(p.price))
                    withStyle(SpanStyle(color = V.ink3, fontWeight = FontWeight.Normal, fontSize = 11.sp)) { append(p.unit ?: "/mo") }
                }, style = T.mono(15.sp, FontWeight.SemiBold))
            }
        }
        Lbl("Inspector seats")
        Counter("Inspectors on this license", account.seatCount, { vm.setSeats(account.seatCount - 1) }, { vm.setSeats(account.seatCount + 1) })
        Text(rich("First inspector included · each additional **${Fmt.money(account.extraInspectorMonthly)}/mo**"), style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(start = 2.dp, end = 2.dp, top = 2.dp))
        VCard(Modifier.padding(top = 14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Monthly total", style = T.ui(15.sp, FontWeight.Bold), modifier = Modifier.weight(1f))
                Text(subTotalLabel(vm), style = T.mono(22.sp, FontWeight.SemiBold, V.brand))
            }
        }
        Lbl("Payment — via Square")
        // TODO(backend): replace with the Square In-App Payments SDK card entry (tokenized); raw card data is never stored.
        val brand = CardBrand.of(card)
        val amex = brand == CardBrand.AMEX
        val cardErr = form.check("card", card) { Checks.cardNumber(card) }
        val expErr = form.check("exp", exp) { Checks.expiry(exp) }
        val cvcErr = form.check("cvc", cvc) { Checks.cvc(cvc, amex) }
        val holderErr = form.check("holder", holder) { Checks.required(holder, "Enter the name on the card") }
        val zipErr = form.check("zip", zip) { Checks.zip(zip) }
        Column(Modifier.padding(bottom = 13.dp).formField(form, "card")) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                FieldLabel("Card number")
                Spacer(Modifier.weight(1f))
                if (brand != CardBrand.UNKNOWN) Text(brand.label, style = T.ui(12.sp, FontWeight.SemiBold, V.brandDeep), modifier = Modifier.padding(bottom = 7.dp))
            }
            VInput(card, { card = it }, placeholder = "1234 5678 9012 3456", keyboard = KeyboardType.Number, visual = CardTransform, filter = Filters::cardNumber, error = cardErr)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(Modifier.weight(1f).formField(form, "exp")) { FieldLabel("Expiry"); VInput(exp, { exp = it }, placeholder = "MM/YY", keyboard = KeyboardType.Number, visual = ExpiryTransform, filter = Filters::expiry, error = expErr) }
            Column(Modifier.weight(1f).formField(form, "cvc")) { FieldLabel("CVC"); VInput(cvc, { cvc = it }, placeholder = if (amex) "1234" else "123", keyboard = KeyboardType.NumberPassword, filter = { Filters.cvc(it, amex) }, error = cvcErr) }
        }
        VField("Cardholder name", holder, { holder = it }, Modifier.padding(top = 13.dp).formField(form, "holder"), placeholder = "Name on card", caps = KeyboardCapitalization.Words, filter = Filters::personName, error = holderErr)
        VField("Billing ZIP", zip, { zip = it }, Modifier.formField(form, "zip"), placeholder = "84015", keyboard = KeyboardType.Number, filter = Filters::zip, error = zipErr, bottom = 0.dp)
        Row(Modifier.padding(start = 2.dp, top = 8.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Icon(VIcons.lock, null, tint = V.ink3, modifier = Modifier.size(14.dp))
            Text("Secured by Square · auto-renews monthly · cancel anytime", style = T.ui(12.sp, color = V.ink3))
        }
        VBtn(if (account.active) "Update subscription" else "Start subscription", { if (form.submit()) vm.startSubscription(card) { card = ""; exp = ""; cvc = ""; nav.navigate(SubStartedR) { popUpTo<SubscribeR> { inclusive = true } } } }, Modifier.padding(top = 16.dp), icon = VIcons.check)
    }
}

@Composable
fun SubStartedScreen(vm: AppViewModel, nav: NavHostController) {
    val account by vm.account.collectAsState()
    VScreen("Subscription active", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        SuccessBlock("Subscription active", "Your **${account.plan.name}** plan is set up with auto-pay through Square. Access continues after your trial with no interruption.") {
            VBtn("View subscription", { nav.navigate(BillingR) { popUpTo<SubStartedR> { inclusive = true } } })
            VBtn("Back to inspections", { nav.goHome() }, Modifier.padding(top = 10.dp), BtnKind.Ghost)
        }
    }
}

@Composable
fun BillingScreen(vm: AppViewModel, nav: NavHostController) {
    val a by vm.account.collectAsState()
    VScreen("Subscription", companyName(vm), net(vm), backAction(nav), listOf(homeAction(nav))) {
        Column(Modifier.padding(bottom = 12.dp).fillMaxWidth().vCard()) {
            BinfoRow({ Text("Status", style = T.ui(14.sp)) }, { if (a.active) Pill("Active · auto-pay", PillKind.Done) else Pill("Trial · ${vm.trialDaysLeft()}d left", PillKind.Queued) })
            BinfoRow("Plan", "${a.plan.name} · ${Fmt.money(a.plan.price)}${a.plan.unit ?: "/mo"}")
            if (!a.plan.perReport) BinfoRow("Inspectors", "${a.seatCount} (${maxOf(0, a.seatCount - 1)} × ${Fmt.money(a.extraInspectorMonthly)})")
            BinfoRow(if (a.plan.perReport) "Billing" else "Monthly total", subTotalLabel(vm))
            BinfoRow("Payment", if (a.active) "Square · Card ····${a.cardLast4 ?: "4242"}" else "Not set up")
            val next = a.subscribedEpochDay?.let { Fmt.date(LocalDate.ofEpochDay(it).plusMonths(1)) }
            BinfoRow(if (a.active) "Next billing" else "Trial ends", if (a.active) next ?: "—" else "in ${vm.trialDaysLeft()} days", last = true)
        }
        VBtn("Manage inspectors", { nav.navigate(InspectorsR) }, kind = BtnKind.Ghost, icon = VIcons.usersSmall)
        VBtn(if (a.active) "Change plan / payment" else "Set up subscription", { nav.navigate(SubscribeR) }, Modifier.padding(top = 10.dp), if (a.active) BtnKind.Ghost else BtnKind.Primary)
    }
}
