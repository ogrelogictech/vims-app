package com.vims.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.data.Eula
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.FieldError
import com.vims.app.ui.components.TopStrip
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.vCard
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons

/** The EULA rendered verbatim from eula.json: title, revised date, intro, numbered section headings, paragraphs, footer. */
@Composable
fun EulaBody(eula: Eula, error: String? = null) {
    if (!eula.isValid) {
        // Never a blank card: say what happened (details are also in logcat under VIMS-EULA).
        Column(Modifier.fillMaxWidth().vCard(border = V.c1).padding(16.dp)) {
            Text("The license agreement couldn't be loaded", style = T.ui(14.sp, FontWeight.Bold, V.c1))
            Text("Please reinstall or update VIMS. If this keeps happening, contact support.", style = T.ui(13.sp, color = V.ink2, lineHeight = 19.sp), modifier = Modifier.padding(top = 6.dp))
            if (error != null) Text(error, style = T.mono(11.sp, color = V.ink3), modifier = Modifier.padding(top = 8.dp))
        }
        return
    }
    Column(Modifier.fillMaxWidth().vCard().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 6.dp)) {
        Text(eula.title, style = T.display(17.sp, FontWeight.ExtraBold, lineHeight = 21.sp), modifier = Modifier.padding(bottom = 4.dp))
        Text("Revised ${eula.revised}", style = T.ui(12.sp, color = V.ink3), modifier = Modifier.padding(bottom = 12.dp))
        eula.intro.forEach { EulaPara(it) }
        eula.sections.forEach { s ->
            Text(s.heading, style = T.display(14.sp, FontWeight.Bold, V.brandDeep), modifier = Modifier.padding(top = 16.dp, bottom = 8.dp))
            s.paragraphs.forEach { EulaPara(it) }
        }
        if (eula.footer.isNotBlank()) Text(eula.footer, style = T.ui(11.5.sp, color = V.ink3, lineHeight = 16.sp), modifier = Modifier.padding(top = 14.dp, bottom = 10.dp))
    }
}

@Composable
private fun EulaPara(t: String) { Text(t, style = T.ui(13.sp, color = V.ink2, lineHeight = 20.sp), modifier = Modifier.padding(bottom = 10.dp)) }

/** Settings → Legal → End User License Agreement (also opened from the sign-up checkbox link). */
@Composable
fun EulaScreen(vm: AppViewModel, nav: NavHostController) {
    VScreen("License agreement", companyName(vm), net(vm), backAction(nav)) { EulaBody(vm.eula, vm.eulaError) }
}

/** "I have read and agree to the VIMS End User License Agreement…" — the agreement name opens the viewer. */
@Composable
fun EulaCheckbox(checked: Boolean, onChange: (Boolean) -> Unit, error: String?, onOpen: () -> Unit, modifier: Modifier = Modifier) {
    Column(modifier.padding(start = 2.dp, end = 2.dp, top = 4.dp, bottom = 16.dp)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(RoundedCornerShape(8.dp)).clickable(role = Role.Checkbox) { onChange(!checked) },
            verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            val shape = RoundedCornerShape(5.dp)
            Box(
                Modifier.padding(top = 1.dp).size(22.dp).clip(shape).background(if (checked) V.brand else V.paper)
                    .border(if (error != null) 1.5.dp else 1.5.dp, if (error != null) V.c1 else if (checked) V.brand else V.ink3, shape),
                contentAlignment = Alignment.Center,
            ) { if (checked) Icon(VIcons.checkBold, null, tint = Color.White, modifier = Modifier.size(15.dp)) }
            Text(buildAnnotatedString {
                append("I have read and agree to the ")
                withLink(LinkAnnotation.Clickable("eula", TextLinkStyles(SpanStyle(color = V.brand, fontWeight = FontWeight.SemiBold))) { onOpen() }) {
                    append("VIMS End User License Agreement")
                }
                append(", which governs the free trial and subscription.")
            }, style = T.ui(13.5.sp, color = V.ink2, lineHeight = 19.5.sp))
        }
        FieldError(error)
    }
}

/** Full-screen gate when eula.json's version differs from what the signed-in user accepted. */
@Composable
fun EulaReacceptGate(vm: AppViewModel, onSignOut: () -> Unit) {
    BackHandler {} // must accept or sign out
    Column(Modifier.fillMaxSize().background(V.paper2)) {
        Column(Modifier.fillMaxWidth().background(V.hdr).statusBarsPadding()) {
            TopStrip(net(vm))
            Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 14.dp)) {
                Text("Updated license agreement", style = T.display(17.sp, FontWeight.Bold, Color.White))
                Text("Please review and accept to continue", style = T.ui(12.sp, color = V.hdrSub))
            }
        }
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp)) {
            Text("The VIMS End User License Agreement has been revised (${vm.eula.revised}). Read it below and tap I agree to keep using VIMS.",
                style = T.ui(13.sp, color = V.ink3, lineHeight = 19.sp), modifier = Modifier.padding(bottom = 12.dp))
            EulaBody(vm.eula, vm.eulaError)
        }
        GateButtons(vm, onSignOut)
    }
}

@Composable
private fun ColumnScope.GateButtons(vm: AppViewModel, onSignOut: () -> Unit) {
    Column(Modifier.fillMaxWidth().background(V.paper).navigationBarsPadding().padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 12.dp)) {
        VBtn("I agree", { vm.acceptEula() }, icon = VIcons.check)
        VBtn("Sign out", onSignOut, Modifier.padding(top = 10.dp), BtnKind.Ghost, icon = VIcons.signOut)
    }
}
