package com.vims.app.ui.screens

import android.app.Activity
import android.app.KeyguardManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.R
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.EulaR
import com.vims.app.ui.ForgotR
import com.vims.app.ui.HomeR
import com.vims.app.ui.JoinR
import com.vims.app.ui.LoginR
import com.vims.app.ui.SignupR
import com.vims.app.ui.back
import com.vims.app.ui.components.Banner
import com.vims.app.ui.components.RequiredHint
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.ContentWidth
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.PasswordField
import com.vims.app.ui.components.TextLink
import com.vims.app.ui.components.TopStrip
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VField
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Checks
import com.vims.app.util.Filters
import com.vims.app.util.formField
import com.vims.app.util.rememberForm

private fun NavHostController.toHomeFromAuth() = navigate(HomeR) { popUpTo(0) { inclusive = true } }

@Composable
fun LoginScreen(vm: AppViewModel, nav: NavHostController) {
    var email by rememberSaveable { mutableStateOf("") }
    var pw by rememberSaveable { mutableStateOf("") }
    val form = rememberForm()
    val emailErr = form.check("email", email) { Checks.email(email) }
    val pwErr = form.check("password", pw) { Checks.passwordSignIn(pw) }
    fun submit() {
        if (!form.submit()) return
        vm.signIn(email, pw, onError = { e -> form.fail(e.field ?: "email", e.message, if (e.field == "password") pw else email) }) { nav.toHomeFromAuth() }
    }
    Column(Modifier.fillMaxSize().background(V.paper2).imePadding().verticalScroll(rememberScrollState())) {
        Column(Modifier.fillMaxWidth().background(V.hdr).statusBarsPadding(), horizontalAlignment = Alignment.CenterHorizontally) {
            TopStrip(net(vm))
            Column(Modifier.padding(start = 24.dp, end = 24.dp, top = 24.dp, bottom = 36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Box(
                    Modifier.size(96.dp).shadow(14.dp, RoundedCornerShape(22.dp)).clip(RoundedCornerShape(22.dp)).background(Color.White),
                    contentAlignment = Alignment.Center,
                ) { Image(painterResource(R.drawable.vims_logo), contentDescription = "VIMS logo", modifier = Modifier.size(74.dp)) }
                Spacer(Modifier.height(16.dp))
                Text("VIMS", style = T.display(30.sp, FontWeight.ExtraBold, Color.White).copy(letterSpacing = 0.02.em))
                Spacer(Modifier.height(4.dp))
                Text("Vision Inspection Management Solutions", style = T.ui(13.sp, color = V.hdrSub, lineHeight = 17.sp), textAlign = TextAlign.Center)
            }
        }
        ContentWidth {
            Column(Modifier.padding(horizontal = 18.dp, vertical = 24.dp).navigationBarsPadding()) {
                VField("Email", email, { email = it }, Modifier.formField(form, "email"), placeholder = "you@company.com", keyboard = KeyboardType.Email, error = emailErr, required = true)
                PasswordField("Password", pw, { pw = it }, placeholder = "Password", error = pwErr, modifier = Modifier.formField(form, "password"), required = true)
                VBtn("Sign in", { submit() })
                VBtn("Create account", { nav.navigate(SignupR) }, Modifier.padding(top = 10.dp), BtnKind.Ghost)
                VBtn("Join a company with a code", { nav.navigate(JoinR) }, Modifier.padding(top = 10.dp), BtnKind.Ghost, icon = VIcons.userPlus)
                TextLink("Forgot password?", { nav.navigate(ForgotR) }, Modifier.padding(top = 4.dp))
            }
        }
    }
}

@Composable
fun SignupScreen(vm: AppViewModel, nav: NavHostController) {
    var name by rememberSaveable { mutableStateOf("") }
    var company by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var pw by rememberSaveable { mutableStateOf("") }
    var pw2 by rememberSaveable { mutableStateOf("") }
    val form = rememberForm()
    val nameErr = form.check("name", name) { Checks.required(name, "Enter your full name") }
    val companyErr = form.check("company", company) { Checks.required(company, "Enter your company name") }
    val emailErr = form.check("email", email) { Checks.email(email) }
    val pwErr = form.check("password", pw) { Checks.passwordNew(pw) }
    val pw2Err = form.check("confirm", pw2) { Checks.confirm(pw, pw2) }
    var agreed by rememberSaveable { mutableStateOf(false) }
    val eulaErr = form.check("eula", agreed.toString()) { if (!agreed) "Accept the End User License Agreement to continue" else null }
    VScreen("Create account", "VIMS", net(vm), backAction(nav)) {
        Lbl("Your details", first = true)
        RequiredHint()
        VField("Full name", name, { name = it }, Modifier.formField(form, "name"), placeholder = "Jeremy Heath", caps = KeyboardCapitalization.Words, error = nameErr, filter = Filters::personName, required = true)
        VField("Company name", company, { company = it }, Modifier.formField(form, "company"), placeholder = "Vision Property Inspections", caps = KeyboardCapitalization.Words, error = companyErr, filter = Filters::companyName, required = true)
        VField("Email", email, { email = it }, Modifier.formField(form, "email"), placeholder = "you@company.com", keyboard = KeyboardType.Email, error = emailErr, required = true)
        PasswordField("Password", pw, { pw = it }, placeholder = "At least 8 characters", error = pwErr, modifier = Modifier.formField(form, "password"), required = true)
        PasswordField("Confirm password", pw2, { pw2 = it }, placeholder = "Re-enter your password", error = pw2Err, modifier = Modifier.formField(form, "confirm"), required = true)
        EulaCheckbox(agreed, { agreed = it }, eulaErr, onOpen = { nav.navigate(EulaR) }, modifier = Modifier.formField(form, "eula"))
        VBtn("Create account & continue", {
            if (form.submit()) vm.createAccount(name, company, email, pw, onError = { e -> form.fail(e.field ?: "email", e.message, email) }) { nav.toHomeFromAuth() }
        })
    }
}

/**
 * Reset password (shared features.passwordReset = "device"): Phase 1 passwords exist only on this device, so no email can be sent.
 * Email → an account for it must be on this device → the device's own screen lock → new password. The password step only opens
 * once the screen lock was confirmed for that email, and the email can't change after that.
 */
@Composable
fun ForgotScreen(vm: AppViewModel, nav: NavHostController) {
    var confirmedEmail by rememberSaveable { mutableStateOf<String?>(null) }
    VScreen("Reset password", "VIMS", net(vm), backAction(nav)) {
        val confirmed = confirmedEmail
        if (confirmed == null) ResetEmailStep(vm) { confirmedEmail = it } else ResetPasswordStep(vm, nav, confirmed)
    }
}

/**
 * KeyguardManager's confirm-credential screen rather than androidx.biometric: no new dependency, MainActivity stays a
 * ComponentActivity (BiometricPrompt needs a FragmentActivity), and it works from minSdk 26 (BiometricPrompt only accepts
 * DEVICE_CREDENTIAL on its own from API 30). Deprecated in API 29 but still supported.
 */
@Suppress("DEPRECATION")
@Composable
private fun ResetEmailStep(vm: AppViewModel, onConfirmed: (String) -> Unit) {
    val ctx = LocalContext.current
    var email by rememberSaveable { mutableStateOf("") }
    var noScreenLock by rememberSaveable { mutableStateOf(false) }
    val form = rememberForm()
    val emailErr = form.check("email", email) { Checks.email(email) }
    // Any result other than OK is a cancel: stay on this screen with no error.
    val confirm = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == Activity.RESULT_OK) onConfirmed(email.trim())
    }
    Text("Your password is stored on this device. Confirm it's you with your device screen lock, then choose a new password.",
        style = T.ui(14.sp, color = V.ink2, lineHeight = 21.sp), modifier = Modifier.padding(top = 4.dp, bottom = 16.dp))
    VField("Email", email, { email = it }, Modifier.formField(form, "email"), placeholder = "you@company.com", keyboard = KeyboardType.Email, error = emailErr, required = true)
    if (noScreenLock) Banner("Set a screen lock in your device Settings first, then try again.", modifier = Modifier.padding(bottom = 13.dp))
    VBtn("Continue", {
        noScreenLock = false
        if (form.submit()) vm.accountOnDevice(email) { found ->
            if (!found) form.fail("email", "No account for that email on this device.", email)
            else {
                val keyguard = ctx.getSystemService(KeyguardManager::class.java)
                val intent = if (keyguard.isDeviceSecure) keyguard.createConfirmDeviceCredentialIntent("Reset password", "Confirm it's you to choose a new VIMS password.") else null
                if (intent == null) noScreenLock = true else confirm.launch(intent)
            }
        }
    })
}

/** Same fields and rules as Create account. */
@Composable
private fun ResetPasswordStep(vm: AppViewModel, nav: NavHostController, email: String) {
    var pw by rememberSaveable { mutableStateOf("") }
    var pw2 by rememberSaveable { mutableStateOf("") }
    val form = rememberForm()
    val pwErr = form.check("password", pw) { Checks.passwordNew(pw) }
    val pw2Err = form.check("confirm", pw2) { Checks.confirm(pw, pw2) }
    Text("Choose a new password for $email.", style = T.ui(14.sp, color = V.ink2, lineHeight = 21.sp), modifier = Modifier.padding(top = 4.dp, bottom = 16.dp))
    PasswordField("New password", pw, { pw = it }, placeholder = "At least 8 characters", error = pwErr, modifier = Modifier.formField(form, "password"), required = true)
    PasswordField("Confirm password", pw2, { pw2 = it }, placeholder = "Re-enter your password", error = pw2Err, modifier = Modifier.formField(form, "confirm"), required = true)
    VBtn("Update password", {
        if (form.submit()) vm.resetPassword(email, pw, onError = { e -> form.fail("password", e.message, pw) }) { nav.navigate(LoginR) { popUpTo(0) { inclusive = true } } }
    })
}

@Composable
fun JoinScreen(vm: AppViewModel, nav: NavHostController) {
    var name by rememberSaveable { mutableStateOf("") }
    var email by rememberSaveable { mutableStateOf("") }
    var pw by rememberSaveable { mutableStateOf("") }
    var code by rememberSaveable { mutableStateOf("") }
    val form = rememberForm()
    val nameErr = form.check("name", name) { Checks.required(name, "Enter your full name") }
    val emailErr = form.check("email", email) { Checks.email(email) }
    val pwErr = form.check("password", pw) { Checks.passwordNew(pw) }
    val codeErr = form.check("code", code) { Checks.joinCode(code) }
    // Inspectors who join are bound by the company's agreement too.
    var agreed by rememberSaveable { mutableStateOf(false) }
    val eulaErr = form.check("eula", agreed.toString()) { if (!agreed) "Accept the End User License Agreement to continue" else null }
    VScreen("Join a company", "VIMS", net(vm), backAction(nav)) {
        Text("Enter the company code your inspection company shared with you. Your account will be linked to their license and billing.",
            style = T.ui(14.sp, color = V.ink2, lineHeight = 21.sp), modifier = Modifier.padding(top = 4.dp, bottom = 16.dp))
        VField("Full name", name, { name = it }, Modifier.formField(form, "name"), placeholder = "Your name", caps = KeyboardCapitalization.Words, error = nameErr, filter = Filters::personName, required = true)
        VField("Email", email, { email = it }, Modifier.formField(form, "email"), placeholder = "you@email.com", keyboard = KeyboardType.Email, error = emailErr, required = true)
        PasswordField("Create a password", pw, { pw = it }, placeholder = "At least 8 characters", error = pwErr, modifier = Modifier.formField(form, "password"), required = true)
        // The full code is typed as shown ("VIS-4827"): uppercase, "-" added after the 3 letters, no suggestions; the keyboard
        // switches to the number pad once the 3 letters are in (and back to letters when one is deleted). Pastes are cleaned up.
        val lettersDone = code.length >= 3 && code.take(3).all { it.isLetter() }
        VField("Company code", code, { code = it }, Modifier.formField(form, "code"), placeholder = "VIS-4827", mono = true, caps = KeyboardCapitalization.Characters,
            error = codeErr, filter = { Filters.joinCode(it, code) }, required = true, autoCorrect = false, keyboard = if (lettersDone) KeyboardType.Number else KeyboardType.Ascii)
        EulaCheckbox(agreed, { agreed = it }, eulaErr, onOpen = { nav.navigate(EulaR) }, modifier = Modifier.formField(form, "eula"))
        VBtn("Link my account", {
            if (form.submit()) vm.joinCompany(name, email, code, pw, onError = { e -> form.fail(e.field ?: "code", e.message, if (e.field == "email") email else code) }) { nav.toHomeFromAuth() }
        }, icon = VIcons.check)
        TextLink("Back to sign in", { nav.back() }, Modifier.padding(top = 4.dp))
    }
}
