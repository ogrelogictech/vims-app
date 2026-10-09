package com.vims.app.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.window.Dialog
import com.vims.app.data.AgreementPiece
import com.vims.app.data.AgreementText
import com.vims.app.ui.back
import com.vims.app.ui.components.BtnRow
import com.vims.app.ui.components.ChooserRow
import com.vims.app.ui.components.ConfirmDialog
import com.vims.app.ui.components.HdrAction
import com.vims.app.ui.components.Hint
import com.vims.app.util.Checks
import com.vims.app.util.Filters
import com.vims.app.util.formField
import com.vims.app.util.rememberForm
import kotlinx.coroutines.launch
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.core.content.FileProvider
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

/* ------------------------------------------------------------------ inspection agreement */

/**
 * "Inspection agreement" viewer. VIMS default agreement (inspection-agreement.json): title, header form lines in a boxed
 * mono block, body paragraphs / bullets, state disclosures (all states when [state] is blank — Company profile; only that
 * state's entry from the wizard), then the closing. A company's edited version is shown whole instead (it can't be
 * filtered by state), under a short note. If the company uses its own uploaded agreement, a note at the top says the VIMS
 * text is shown for reference and offers to open their file. The top bar's Download prints what's shown to a PDF
 * (Share / Save to device) — every user can download.
 */
@Composable
fun AgreementScreen(vm: AppViewModel, nav: NavHostController, state: String) {
    val company by vm.company.collectAsState()
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val a = vm.agreement
    val edited = company.editedAgreement
    val sub = if (state.isBlank()) "All 50 states" else vm.config.stateName(state)
    var pdf by remember { mutableStateOf<AppViewModel.AgreementPdfFile?>(null) }
    var sheet by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    val saveAs = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        val f = pdf?.file
        if (uri != null && f != null) vm.saveAgreementPdf(f, uri)
    }
    val download = HdrAction(VIcons.download, "Download PDF") {
        if (!busy) {
            busy = true
            scope.launch {
                val r = vm.buildAgreementPdf(state)
                busy = false
                if (r == null) vm.toast("Could not create the PDF") else { pdf = r; sheet = true }
            }
        }
    }
    val canDownload = edited != null || a.isValid
    pdf?.takeIf { sheet }?.let { f ->
        Dialog(onDismissRequest = { sheet = false }) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(V.paper).padding(vertical = 14.dp)) {
                Text("Download agreement", style = T.display(17.sp, FontWeight.Bold), modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 2.dp))
                Text("${f.file.name} · ${f.pages} page${if (f.pages == 1) "" else "s"}", style = T.ui(12.5.sp, color = V.ink3, lineHeight = 17.sp),
                    modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 8.dp))
                ChooserRow(VIcons.share, "Share PDF") { sheet = false; shareAgreementPdf(ctx, vm, f.file) }
                ChooserRow(VIcons.download, "Save to device") { sheet = false; saveAs.launch(f.file.name) }
                ChooserRow(null, "Cancel", V.ink3) { sheet = false }
            }
        }
    }
    VScreen("Inspection agreement", sub, net(vm), backAction(nav), if (canDownload) listOf(download) else emptyList()) {
        val ownName = company.uploadedAgreement
        if (ownName != null) {
            AccentCard(V.signal, Modifier.padding(bottom = 12.dp)) {
                Text(buildAnnotatedString {
                    append("Your company uses its own agreement (")
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(ownName) }
                    append("). Below is the VIMS agreement for reference.")
                }, style = T.ui(13.sp, color = V.signalInk, lineHeight = 19.sp))
                Row(
                    Modifier.padding(top = 6.dp).heightIn(min = 44.dp).clip(RoundedCornerShape(8.dp))
                        .clickable(role = Role.Button) { openOwnAgreement(ctx, vm) }.padding(end = 8.dp),
                    verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(VIcons.preview, null, tint = V.brand, modifier = Modifier.size(16.dp))
                    Text("Open your agreement", style = T.ui(13.sp, FontWeight.SemiBold, V.brand))
                }
            }
        }
        if (edited != null) {
            AccentCard(V.brand, Modifier.padding(bottom = 12.dp)) {
                Text("Your company's edited version of the VIMS agreement.", style = T.ui(13.sp, color = V.ink2, lineHeight = 19.sp))
            }
        } else if (!a.isValid) {
            Column(Modifier.fillMaxWidth().vCard(border = V.c1).padding(16.dp)) {
                Text("The inspection agreement couldn't be loaded", style = T.ui(14.sp, FontWeight.Bold, V.c1))
                Text("Please reinstall or update VIMS. If this keeps happening, contact support.", style = T.ui(13.sp, color = V.ink2, lineHeight = 19.sp), modifier = Modifier.padding(top = 6.dp))
                vm.agreementError?.let { Text(it, style = T.mono(11.sp, color = V.ink3), modifier = Modifier.padding(top = 8.dp)) }
            }
            return@VScreen
        }
        val pieces = remember(company, state) { vm.agreementPieces(company, state) }
        Column(Modifier.fillMaxWidth().vCard().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp)) {
            pieces.forEach { AgreementPieceView(it) }
        }
    }
}

/** One [AgreementPiece] as the viewer shows it ([com.vims.app.report.AgreementPdf] prints the same list). */
@Composable
private fun AgreementPieceView(p: AgreementPiece) {
    when (p) {
        is AgreementPiece.Title -> Text(p.text, style = T.display(18.sp, FontWeight.ExtraBold, lineHeight = 22.sp), modifier = Modifier.padding(bottom = 10.dp))
        is AgreementPiece.Form -> Text(p.lines.joinToString("\n"), style = T.mono(11.5.sp, color = V.ink2).copy(lineHeight = 20.sp),
            modifier = Modifier.fillMaxWidth().padding(bottom = 12.dp).clip(RoundedCornerShape(9.dp)).background(V.paper2)
                .border(1.dp, V.line, RoundedCornerShape(9.dp)).padding(horizontal = 12.dp, vertical = 10.dp))
        is AgreementPiece.Para -> AgreementPara(p.text, if (p.lead) V.ink else if (p.muted) V.ink3 else V.ink2, if (p.lead) FontWeight.SemiBold else FontWeight.Normal)
        is AgreementPiece.Bullet -> Row(Modifier.padding(start = 4.dp, bottom = 9.dp)) {
            Text("•", style = T.ui(13.sp, color = V.ink2, lineHeight = 20.sp), modifier = Modifier.width(12.dp))
            Text(p.text, style = T.ui(13.sp, color = V.ink2, lineHeight = 20.sp), modifier = Modifier.weight(1f))
        }
        is AgreementPiece.Heading -> Text(p.text, style = T.display(14.sp, FontWeight.Bold, V.brandDeep), modifier = Modifier.padding(top = 14.dp, bottom = 8.dp))
        is AgreementPiece.Disclosure -> Text(buildAnnotatedString {
            withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = V.ink)) { append("${p.state}:") }
            append(" "); append(p.text)
        }, style = T.ui(13.sp, color = V.ink2, lineHeight = 20.sp), modifier = Modifier.padding(bottom = 9.dp))
        is AgreementPiece.Note -> Text(p.text, style = T.ui(11.5.sp, color = V.ink3, lineHeight = 16.sp), modifier = Modifier.padding(bottom = 9.dp))
    }
}

@Composable
private fun AgreementPara(t: String, color: Color = V.ink2, weight: FontWeight = FontWeight.Normal) {
    Text(t, style = T.ui(13.sp, weight, color, lineHeight = 20.sp), modifier = Modifier.padding(bottom = 9.dp))
}

/** Download → Share PDF: ACTION_SEND with the generated agreement PDF (FileProvider, cache/agreement/). */
fun shareAgreementPdf(ctx: Context, vm: AppViewModel, f: java.io.File) {
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", f)
    val name = vm.company.value.name
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "application/pdf"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, if (name.isBlank()) "Inspection agreement" else "Inspection agreement — $name")
        clipData = android.content.ClipData.newRawUri(f.name, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    if (com.vims.app.BuildConfig.DEBUG) android.util.Log.d("VIMS-Share", "ACTION_SEND agreement pdf uri=$uri file=${f.name} bytes=${f.length()}")
    try { ctx.startActivity(Intent.createChooser(send, "Share agreement")) } catch (_: ActivityNotFoundException) { vm.toast("No app available to share the PDF") }
}

/**
 * Edit agreement (company admins only — same permission as Upload): the company's own copy of the agreement as plain
 * text, prefilled with their edited version or the whole VIMS agreement (company name filled in). Paragraphs are
 * separated by blank lines; lines starting with "• " are bullets. Save stores it on the company record and makes it the
 * agreement in use (an uploaded file is cleared). Leaving with unsaved changes (header back, Cancel, system back) asks first.
 */
@Composable
fun AgreementEditScreen(vm: AppViewModel, nav: NavHostController) {
    val session by vm.session.collectAsState()
    if (session?.isAdmin == false) {
        LaunchedEffect(Unit) { vm.toast("Only company admins can edit the agreement"); nav.back() }
        return
    }
    val key = rememberSaveable { java.util.UUID.randomUUID().toString() }
    val initial = remember { vm.agreementEditorText() }
    val draft = remember(key) { vm.agreementDrafts.getOrPut(key) { mutableStateOf(TextFieldValue(initial)) } }
    val text = draft.value.text
    val dirty = text != initial
    var ask by remember { mutableStateOf(false) }
    val form = rememberForm()
    val max = AgreementText.MAX_CHARS
    val err = form.check("text", text) { Checks.agreement(text, max) }
    fun leave() { vm.agreementDrafts.remove(key); nav.back() }
    fun close() { if (dirty) ask = true else leave() }
    fun save() {
        if (!form.submit()) return
        if (!dirty) { vm.toast("No changes to save"); leave(); return }
        vm.saveAgreementText(text.trim())
        leave()
    }
    BackHandler(enabled = dirty) { ask = true }
    if (ask) ConfirmDialog(
        "Discard changes?", "Your edits to the agreement haven't been saved.", "Discard",
        onConfirm = { ask = false; leave() }, onDismiss = { ask = false }, danger = true,
    )
    VScreen("Edit agreement", companyName(vm), net(vm), HdrAction(VIcons.back, "Back") { close() }, scroll = false) {
        Column(Modifier.fillMaxSize().padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 12.dp)) {
            Hint("Your company's copy of the VIMS agreement. Separate paragraphs with a blank line and start a line with **•** for a bullet. The VIMS agreement itself doesn't change.",
                Modifier.padding(start = 2.dp, bottom = 10.dp), size = 12.5f)
            AgreementTextField(draft.value, { v ->
                val t = Filters.agreement(v.text, max)
                draft.value = if (t == v.text) v else v.copy(text = t, selection = TextRange(v.selection.start.coerceAtMost(t.length), v.selection.end.coerceAtMost(t.length)))
            }, err != null, Modifier.weight(1f).formField(form, "text"))
            Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.weight(1f)) { FieldError(err) }
                Text("${String.format(java.util.Locale.US, "%,d", text.length)} / ${String.format(java.util.Locale.US, "%,d", max)}",
                    style = T.mono(11.sp, color = if (text.length > max) V.c1 else V.ink3), modifier = Modifier.padding(top = 6.dp, end = 2.dp))
            }
            BtnRow {
                VBtn("Cancel", { close() }, Modifier.weight(1f), BtnKind.Ghost)
                VBtn("Save", { save() }, Modifier.weight(1f), icon = VIcons.check)
            }
        }
    }
}

/** Large multi-line field for the agreement text: fills the space it's given and scrolls inside (VInput's look). */
@Composable
private fun AgreementTextField(value: TextFieldValue, onChange: (TextFieldValue) -> Unit, error: Boolean, modifier: Modifier) {
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val shape = RoundedCornerShape(11.dp)
    BasicTextField(
        value, onChange, modifier.fillMaxWidth(), textStyle = T.ui(14.sp, color = V.ink, lineHeight = 21.sp), interactionSource = interaction,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences, autoCorrectEnabled = true),
        cursorBrush = SolidColor(V.brand),
        decorationBox = { inner ->
            Box(
                Modifier.fillMaxSize().clip(shape).background(V.paper)
                    .border(if (focused || error) (if (error && !focused) 1.5.dp else 2.dp) else 1.dp, if (error) V.c1 else if (focused) V.brand else V.line, shape)
                    .padding(horizontal = 14.dp, vertical = 12.dp),
            ) { inner() }
        },
    )
}

/** Opens the company's own uploaded agreement (PDF / Word) in another app via FileProvider. */
fun openOwnAgreement(ctx: Context, vm: AppViewModel) {
    val f = vm.ownAgreementFile()?.takeIf { it.isFile } ?: run { vm.toast("Your agreement file isn't on this device"); return }
    val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(f.extension.lowercase()) ?: "application/octet-stream"
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", f)
    val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    if (com.vims.app.BuildConfig.DEBUG) android.util.Log.d("VIMS-Share", "ACTION_VIEW own agreement uri=$uri type=$mime")
    try { ctx.startActivity(view) } catch (_: ActivityNotFoundException) { vm.toast("No app installed to open ${f.extension.uppercase()} files") }
}
