package com.vims.app.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.toRoute
import com.vims.app.ui.screens.AdminScreen
import com.vims.app.ui.screens.BillingScreen
import com.vims.app.ui.screens.CameraScreen
import com.vims.app.ui.screens.CompanyScreen
import com.vims.app.ui.screens.EditSectionScreen
import com.vims.app.ui.screens.FeedbackAdminScreen
import com.vims.app.ui.screens.ForgotScreen
import com.vims.app.ui.screens.GeneratedScreen
import com.vims.app.ui.screens.HomeScreen
import com.vims.app.ui.screens.InspectorsScreen
import com.vims.app.ui.screens.InstructionsScreen
import com.vims.app.ui.screens.JoinScreen
import com.vims.app.ui.screens.LoginScreen
import com.vims.app.ui.screens.MarkupScreen
import com.vims.app.ui.screens.PdfPreviewScreen
import com.vims.app.ui.screens.PhotosScreen
import com.vims.app.ui.screens.PlansAdminScreen
import com.vims.app.ui.screens.ReportScreen
import com.vims.app.ui.screens.SectionScreen
import com.vims.app.ui.screens.SectionsScreen
import com.vims.app.ui.screens.SettingsScreen
import com.vims.app.ui.screens.SignupScreen
import com.vims.app.ui.screens.SubStartedScreen
import com.vims.app.ui.screens.SubscribeScreen
import com.vims.app.ui.screens.SummaryScreen
import com.vims.app.ui.screens.TrialSplash
import com.vims.app.ui.screens.WizardScreen
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import kotlinx.coroutines.delay
import kotlinx.serialization.Serializable

// Type-safe routes (one per prototype screen).
@Serializable object LoginR
@Serializable object SignupR
@Serializable object ForgotR
@Serializable object JoinR
@Serializable object HomeR
@Serializable data class WizardR(val inspId: String? = null)
@Serializable data class SectionsR(val inspId: String)
@Serializable data class SectionR(val inspId: String, val name: String)
@Serializable data class PhotosR(val inspId: String, val name: String)
@Serializable data class CameraR(val inspId: String, val name: String, val cat: String)
@Serializable data class MarkupR(val inspId: String, val photoId: String, val finding: Boolean = false)
@Serializable data class SummaryR(val inspId: String)
@Serializable data class ReportR(val inspId: String)
@Serializable data class GeneratedR(val inspId: String)
@Serializable data class PdfR(val inspId: String)
@Serializable object SettingsR
@Serializable object CompanyR
@Serializable object InstructionsR
@Serializable object AdminR
@Serializable data class EditSecR(val name: String)
@Serializable object PlansR
@Serializable object InspectorsR
@Serializable object SubscribeR
@Serializable object SubStartedR
@Serializable object BillingR
@Serializable object FeedbackAdminR
@Serializable object ReportBccR
@Serializable object EulaR

/** Debug-only launch options (adb `--es screen …`), used to open any screen directly for screenshots. */
data class DebugLaunch(val screen: String, val insp: String?, val section: String?, val cat: String?, val photo: String?, val depth: String?, val splash: Boolean, val step: Int = 1, val coverStep: Int = 1, val eulaVersion: String? = null)

fun NavHostController.back() { if (!popBackStack()) goHome() }
fun NavHostController.goHome() = navigate(HomeR) { popUpTo(0) { inclusive = true } }

/** Section → section navigation replaces the current section entry (like the prototype's single section screen). */
fun NavHostController.openSection(inspId: String, name: String) {
    navigate(SectionR(inspId, name)) {
        popUpTo<SectionR> { inclusive = true }
        launchSingleTop = false
    }
}

@Composable
fun VimsRoot(vm: AppViewModel, debug: DebugLaunch?) {
    val nav = rememberNavController()
    val start: Any = remember { if (vm.session.value != null) HomeR else LoginR }
    val session by vm.session.collectAsState()

    Box(Modifier.fillMaxSize().background(V.paper2)) {
        NavHost(nav, startDestination = start) {
            composable<LoginR> { LoginScreen(vm, nav) }
            composable<SignupR> { SignupScreen(vm, nav) }
            composable<ForgotR> { ForgotScreen(vm, nav) }
            composable<JoinR> { JoinScreen(vm, nav) }
            composable<HomeR> { HomeScreen(vm, nav) }
            composable<WizardR> { WizardScreen(vm, nav, it.toRoute<WizardR>().inspId) }
            composable<SectionsR> { SectionsScreen(vm, nav, it.toRoute<SectionsR>().inspId) }
            composable<SectionR> { val r = it.toRoute<SectionR>(); SectionScreen(vm, nav, r.inspId, r.name) }
            composable<PhotosR> { val r = it.toRoute<PhotosR>(); PhotosScreen(vm, nav, r.inspId, r.name) }
            composable<CameraR> { val r = it.toRoute<CameraR>(); CameraScreen(vm, nav, r.inspId, r.name, r.cat) }
            composable<MarkupR> { val r = it.toRoute<MarkupR>(); MarkupScreen(vm, nav, r.inspId, r.photoId, r.finding) }
            composable<SummaryR> { SummaryScreen(vm, nav, it.toRoute<SummaryR>().inspId) }
            composable<ReportR> { ReportScreen(vm, nav, it.toRoute<ReportR>().inspId) }
            composable<GeneratedR> { GeneratedScreen(vm, nav, it.toRoute<GeneratedR>().inspId) }
            composable<PdfR> { PdfPreviewScreen(vm, nav, it.toRoute<PdfR>().inspId) }
            composable<SettingsR> { SettingsScreen(vm, nav) }
            composable<CompanyR> { CompanyScreen(vm, nav) }
            composable<InstructionsR> { InstructionsScreen(vm, nav) }
            composable<AdminR> { AdminScreen(vm, nav) }
            composable<EditSecR> { EditSectionScreen(vm, nav, it.toRoute<EditSecR>().name) }
            composable<PlansR> { PlansAdminScreen(vm, nav) }
            composable<InspectorsR> { InspectorsScreen(vm, nav) }
            composable<SubscribeR> { SubscribeScreen(vm, nav) }
            composable<SubStartedR> { SubStartedScreen(vm, nav) }
            composable<BillingR> { BillingScreen(vm, nav) }
            composable<FeedbackAdminR> { FeedbackAdminScreen(vm, nav) }
            composable<EulaR> { com.vims.app.ui.screens.EulaScreen(vm, nav) }
            composable<ReportBccR> { com.vims.app.ui.screens.ReportBccScreen(vm, nav) }
        }

        TrialSplash(vm, nav)
        // Re-acceptance: eula.json version differs from the signed-in user's accepted version.
        val s = session
        if (s != null && s.eulaVersion != vm.currentEulaVersion) {
            var ask by remember { mutableStateOf(false) }
            if (ask) com.vims.app.ui.screens.SignOutDialog(vm, nav) { ask = false }
            com.vims.app.ui.screens.EulaReacceptGate(vm) { ask = true }
        }
        ToastHost(vm)
    }

    LaunchedEffect(debug) { if (debug != null) applyDebug(vm, nav, debug) }
}

private suspend fun applyDebug(vm: AppViewModel, nav: NavHostController, d: DebugLaunch) {
    val id = d.insp ?: "demo-ridgeline"
    if (d.screen != "login") vm.debugSignIn()
    d.depth?.let { vm.debugSetDepth(id, it) }
    vm.debugWizardStep = d.step
    d.eulaVersion?.let { vm.debugEulaVersion = it }
    vm.debugCoverStep = d.coverStep
    val sec = d.section ?: "Roof"
    val route: Any? = when (d.screen) {
        "login" -> null
        "signup" -> SignupR
        "forgot" -> ForgotR
        "join" -> JoinR
        "home" -> HomeR
        "wizard" -> WizardR(d.insp)
        "sections" -> SectionsR(id)
        "section" -> SectionR(id, sec)
        "photos" -> PhotosR(id, sec)
        "camera" -> CameraR(id, sec, d.cat ?: "North Side")
        "markup", "finding" -> MarkupR(id, d.photo ?: vm.bundle(id)?.photos?.firstOrNull { it.section == sec }?.id ?: "", d.screen == "finding")
        "summary" -> SummaryR(id)
        "report" -> ReportR(id)
        "generated" -> GeneratedR(id)
        "pdf" -> PdfR(id)
        "settings" -> SettingsR
        "company" -> CompanyR
        "instructions" -> InstructionsR
        "admin" -> AdminR
        "editsec" -> EditSecR(sec)
        "plans" -> PlansR
        "inspectors" -> InspectorsR
        "subscribe" -> SubscribeR
        "substarted" -> SubStartedR
        "billing" -> BillingR
        "feedbackadmin" -> FeedbackAdminR
        "reportbcc" -> ReportBccR
        "eula" -> EulaR
        else -> HomeR
    }
    if (route != null) {
        nav.navigate(HomeR) { popUpTo(0) { inclusive = true } }
        if (route != HomeR) nav.navigate(route)
    } else {
        nav.navigate(LoginR) { popUpTo(0) { inclusive = true } }
    }
    if (d.splash) vm.maybeShowSplash()
}

@Composable
private fun ToastHost(vm: AppViewModel) {
    val msg by vm.toast.collectAsState()
    var visible by remember { mutableStateOf(false) }
    var text by remember { mutableStateOf("") }
    LaunchedEffect(msg) {
        val m = msg ?: return@LaunchedEffect
        text = m.text; visible = true
        delay(1900); visible = false
    }
    Box(Modifier.fillMaxSize().navigationBarsPadding().padding(bottom = 26.dp), contentAlignment = Alignment.BottomCenter) {
        AnimatedVisibility(visible, enter = fadeIn() + slideInVertically { it / 2 }, exit = fadeOut() + slideOutVertically { it / 2 }) {
            Row(
                Modifier.padding(horizontal = 24.dp).shadow(12.dp, RoundedCornerShape(12.dp)).clip(RoundedCornerShape(12.dp)).background(V.ink).padding(horizontal = 18.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(VIcons.checkBold, null, tint = Color(0xFF7CE0AF), modifier = Modifier.size(17.dp))
                Spacer(Modifier.width(9.dp))
                Text(text, style = T.ui(13.5.sp, FontWeight.Medium, Color.White))
            }
        }
    }
}
