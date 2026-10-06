package com.vims.app.ui.screens

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.navigation.NavHostController
import com.vims.app.data.StateDoc
import com.vims.app.data.WizardSelections
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.AgreementR
import com.vims.app.ui.StateDocR
import com.vims.app.ui.components.FieldError
import com.vims.app.ui.components.FieldLabel
import com.vims.app.ui.components.HdrAction
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.vCard
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.FormState
import com.vims.app.util.formField
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/* State rules (vims-checklists.json v1.3 `states` + `stateRules`) — wizard step 1 State field, the state's note card,
 * required state documents (View / Send to client / "Provided to the client…" acknowledgment) and the in-app viewer. */

const val STATE_KEY = "State"
const val STATE_ACK_KEY = "stateDocsAck"

/** Required "State" dropdown (right after Inspection address) + the selected state's note card and documents. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StateField(vm: AppViewModel, nav: NavHostController, sel: WizardSelections, form: FormState) {
    val cfg = vm.config
    val rule = cfg.stateRule(sel.state)
    val err = form.check(STATE_KEY, sel.state) { if (sel.state.isBlank()) "Select the property's state" else null }
    // Always registered (fresh closure each composition) so a state without documents never keeps a stale check.
    val ackErr = form.check(STATE_ACK_KEY, "${sel.state}:${sel.stateDocsAck}") {
        if (cfg.stateRule(sel.state)?.docs.orEmpty().isNotEmpty() && !sel.stateDocsAck) "Confirm the required state notice was given to the client" else null
    }
    var open by remember { mutableStateOf(false) }
    Column(Modifier.padding(bottom = 13.dp).formField(form, STATE_KEY)) {
        FieldLabel("State", required = true)
        ExposedDropdownMenuBox(expanded = open, onExpandedChange = { open = it }) {
            val shape = RoundedCornerShape(11.dp)
            Row(
                Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable).fillMaxWidth().heightIn(min = 48.dp).clip(shape).background(V.paper)
                    .border(if (err != null || open) (if (open) 2.dp else 1.5.dp) else 1.dp, if (err != null && !open) V.c1 else if (open) V.brand else V.line, shape)
                    .semantics { role = Role.DropdownList }.padding(horizontal = 14.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                val name = if (sel.state.isBlank()) "" else cfg.stateName(sel.state)
                Text(name.ifEmpty { "Select the property’s state…" }, style = T.ui(15.sp, color = if (name.isEmpty()) V.placeholder else V.ink),
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                Icon(VIcons.chevDown, null, tint = V.ink, modifier = Modifier.size(16.dp))
            }
            ExposedDropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = V.paper) {
                cfg.states.forEach { st ->
                    val on = st.code == sel.state
                    DropdownMenuItem(
                        text = { Text(st.name, style = T.ui(14.5.sp, if (on) FontWeight.Bold else FontWeight.Normal, if (on) V.brandDeep else V.ink)) },
                        onClick = { open = false; vm.setInspState(st.code) },
                        trailingIcon = if (on) ({ Icon(VIcons.check, null, tint = V.brand, modifier = Modifier.size(16.dp)) }) else null,
                    )
                }
            }
        }
        FieldError(err)
    }
    // A rule whose note is about the agent copy (agentCopyDefault false, e.g. NH) shows it under the agent checkbox instead.
    val note = rule?.note?.takeIf { rule.agentCopy }
    if (note != null || rule?.docs?.isNotEmpty() == true) StateNoteCard(vm, nav, sel, note, rule.docs, ackErr, Modifier.formField(form, STATE_ACK_KEY))
    // "Inspection agreement: View (shows the selected state's section)" — the VIMS agreement with only this state's disclosures.
    Row(
        Modifier.fillMaxWidth().padding(bottom = 6.dp).heightIn(min = 44.dp).clip(RoundedCornerShape(8.dp))
            .clickable(role = Role.Button, onClickLabel = "View inspection agreement") { nav.navigate(AgreementR(sel.state)) }.padding(horizontal = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(buildAnnotatedString {
            append("Inspection agreement: ")
            withStyle(SpanStyle(color = V.brand, fontWeight = FontWeight.SemiBold)) { append("View") }
            append(" (shows the selected state’s section)")
        }, style = T.ui(12.5.sp, color = V.ink3, lineHeight = 17.sp))
    }
}

/**
 * Step 1 checkbox under Real estate agent email: "Send the report to the real estate agent". Defaults to the state's
 * `agentCopyDefault` (set when the state changes); when that default is false (NH) the state's note is shown beneath it.
 */
@Composable
fun SendToAgentCheck(vm: AppViewModel, sel: WizardSelections) {
    val rule = vm.config.stateRule(sel.state)
    val shape = RoundedCornerShape(5.dp)
    Row(
        Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(8.dp))
            .toggleable(sel.sendToAgent, role = Role.Checkbox) { vm.setSendToAgent(it) }.padding(horizontal = 2.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            Modifier.size(22.dp).clip(shape).background(if (sel.sendToAgent) V.brand else V.paper).border(1.5.dp, if (sel.sendToAgent) V.brand else V.ink3, shape),
            contentAlignment = Alignment.Center,
        ) { if (sel.sendToAgent) Icon(VIcons.checkBold, null, tint = Color.White, modifier = Modifier.size(15.dp)) }
        Text("Send the report to the real estate agent", style = T.ui(13.5.sp, color = V.ink2, lineHeight = 18.sp), modifier = Modifier.weight(1f))
    }
    if (rule != null && !rule.agentCopy && rule.note != null) {
        Text(rule.note, style = T.ui(12.sp, FontWeight.Medium, V.signalDeep, lineHeight = 16.sp), modifier = Modifier.padding(start = 2.dp, end = 2.dp, bottom = 6.dp))
    }
}

/** Info card under the State field (prototype: card with a brand left border). */
@Composable
private fun StateNoteCard(vm: AppViewModel, nav: NavHostController, sel: WizardSelections, note: String?, docs: List<StateDoc>, ackErr: String?, modifier: Modifier) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    AccentCard(V.brand, modifier.padding(top = 0.dp, bottom = 14.dp)) {
        if (note != null) Text(note, style = T.ui(13.sp, color = V.ink2, lineHeight = 19.5.sp))
        docs.forEach { d ->
            Text(d.name, style = T.ui(12.5.sp, FontWeight.Bold, V.ink, lineHeight = 17.sp), modifier = Modifier.padding(top = 12.dp))
            Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SmallGhostBtn("View", VIcons.preview) { nav.navigate(StateDocR(d.file, d.name)) }
                SmallGhostBtn("Send to client", VIcons.mail) { scope.launch { sendStateDoc(ctx, vm, sel, d) } }
            }
        }
        if (docs.isNotEmpty()) {
            val shape = RoundedCornerShape(5.dp)
            Row(
                Modifier.fillMaxWidth().padding(top = 12.dp).heightIn(min = 44.dp).clip(RoundedCornerShape(8.dp))
                    .clickable(role = Role.Checkbox, onClickLabel = "Toggle") { vm.ackStateDocs(!sel.stateDocsAck) },
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Box(
                    Modifier.size(22.dp).clip(shape).background(if (sel.stateDocsAck) V.brand else V.paper)
                        .border(1.5.dp, if (ackErr != null) V.c1 else if (sel.stateDocsAck) V.brand else V.ink3, shape),
                    contentAlignment = Alignment.Center,
                ) { if (sel.stateDocsAck) Icon(VIcons.checkBold, null, tint = Color.White, modifier = Modifier.size(15.dp)) }
                Column(Modifier.weight(1f)) {
                    Text("Provided to the client with the inspection agreement", style = T.ui(13.5.sp, color = V.ink, lineHeight = 18.sp))
                    sel.stateDocsAckAt?.takeIf { sel.stateDocsAck }?.let {
                        Text("Confirmed ${ackStamp(it)}", style = T.ui(11.5.sp, color = V.ink3), modifier = Modifier.padding(top = 2.dp))
                    }
                }
            }
            FieldError(ackErr)
        }
    }
}

/** Compact ghost button (prototype `.btn.ghost` at 12.5px, auto width); 44dp tall for touch. */
@Composable
private fun SmallGhostBtn(text: String, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    val shape = RoundedCornerShape(10.dp)
    Row(
        Modifier.heightIn(min = 44.dp).clip(shape).background(V.paper).border(1.dp, V.line, shape)
            .clickable(role = Role.Button, onClick = onClick).padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Icon(icon, null, tint = V.ink, modifier = Modifier.size(16.dp))
        Text(text, style = T.ui(12.5.sp, FontWeight.SemiBold, V.ink))
    }
}

private val ackFmt = DateTimeFormatter.ofPattern("MMM d, yyyy · h:mm a", Locale.US)
private fun ackStamp(ms: Long) = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).format(ackFmt)

/** Card with a 3dp colored left edge (prototype `border-left:3px solid …`). */
@Composable
fun AccentCard(accent: Color, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    Row(modifier.fillMaxWidth().height(IntrinsicSize.Min).vCard(12.dp)) {
        Box(Modifier.width(3.dp).fillMaxHeight().background(accent))
        Column(Modifier.weight(1f).padding(start = 11.dp, end = 14.dp, top = 12.dp, bottom = 12.dp)) { content() }
    }
}

/** Oklahoma-style required disclosure: permanent entry at the top of the Summary screen (signal-colored edge). */
@Composable
fun StateDisclosureCard(vm: AppViewModel, state: String, modifier: Modifier = Modifier) {
    val text = vm.config.stateRule(state)?.summaryDisclosure ?: return
    AccentCard(V.signal, modifier.padding(bottom = 12.dp)) {
        Text("${vm.config.stateName(state)} disclosure", style = T.ui(13.sp, FontWeight.Bold, V.ink), modifier = Modifier.padding(bottom = 3.dp))
        Text(text, style = T.ui(13.sp, color = V.ink2, lineHeight = 19.5.sp))
    }
}

/* ------------------------------------------------------------------ documents */

/** Copies a state document from the APK assets (shared/<file>) to cache/state-docs/ so it can be rendered / shared. */
suspend fun stateDocFile(ctx: Context, assetPath: String): File? = withContext(Dispatchers.IO) {
    try {
        val out = File(ctx.cacheDir, "state-docs/" + assetPath.substringAfterLast('/'))
        if (!out.isFile || out.length() == 0L) {
            out.parentFile?.mkdirs()
            ctx.assets.open(assetPath).use { input -> out.outputStream().use { input.copyTo(it) } }
        }
        out
    } catch (e: Exception) {
        android.util.Log.w("VIMS-State", "State document missing: $assetPath", e); null
    }
}

/** "Send to client": ACTION_SEND email to the client (Client email from step 1) with the PDF attached. */
suspend fun sendStateDoc(ctx: Context, vm: AppViewModel, sel: WizardSelections, doc: StateDoc) {
    val f = stateDocFile(ctx, doc.file) ?: run { vm.toast("Couldn't open ${doc.name}"); return }
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", f)
    val company = vm.company.value
    val body = buildString {
        append("Hi ${sel.clientName.ifBlank { "there" }},\n\nAttached is the ${doc.name}, provided with your inspection agreement")
        if (sel.fullAddress.isNotBlank()) append(" for ${sel.fullAddress}")
        append(".\n\n${company.inspectorName.ifBlank { company.name }}\n${company.name}")
    }
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "application/pdf"
        putExtra(Intent.EXTRA_STREAM, uri)
        if (sel.clientEmail.isNotBlank()) putExtra(Intent.EXTRA_EMAIL, arrayOf(sel.clientEmail))
        putExtra(Intent.EXTRA_SUBJECT, doc.name)
        putExtra(Intent.EXTRA_TEXT, body)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    if (com.vims.app.BuildConfig.DEBUG) android.util.Log.d("VIMS-Share", "ACTION_SEND state doc to=${send.getStringArrayExtra(Intent.EXTRA_EMAIL)?.toList()} subject=${doc.name} file=${f.name}")
    try { ctx.startActivity(Intent.createChooser(send, "Send to client")) } catch (_: ActivityNotFoundException) { vm.toast("No app available to send the document") }
    if (sel.clientEmail.isBlank()) vm.toast("Add the client email to address it automatically")
}

/** In-app viewer for a state document (PdfRenderer), with Send to client / open in another app. */
@Composable
fun StateDocScreen(vm: AppViewModel, nav: NavHostController, file: String, name: String) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val sel = vm.wizard.collectAsState().value.sel
    val pdf by produceState<File?>(null, file) { value = stateDocFile(ctx, file) }
    val renderer = remember(pdf) { pdf?.let { try { PdfRenderer(ParcelFileDescriptor.open(it, ParcelFileDescriptor.MODE_READ_ONLY)) } catch (_: Exception) { null } } }
    DisposableEffect(renderer) { onDispose { renderer?.close() } }
    VScreen(
        "State document", name, net(vm), backAction(nav),
        listOf(
            HdrAction(VIcons.share, "Send to client") { scope.launch { sendStateDoc(ctx, vm, sel, StateDoc(name, file)) } },
            HdrAction(VIcons.preview, "Open in another app") { pdf?.let { openPdfExternally(ctx, vm, it) } },
        ),
        scroll = false,
    ) {
        if (renderer == null) {
            Text(if (pdf == null) "Loading…" else "This document couldn't be opened.", style = T.ui(14.sp, color = V.ink3), modifier = Modifier.padding(16.dp))
            return@VScreen
        }
        Hint("$name · ${renderer.pageCount} page${if (renderer.pageCount == 1) "" else "s"}", Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp), size = 12f)
        LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            items(renderer.pageCount) { i -> PdfPage(renderer, i, "$name page ${i + 1}") }
        }
    }
}

private fun openPdfExternally(ctx: Context, vm: AppViewModel, f: File) {
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", f)
    val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/pdf").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    try { ctx.startActivity(view) } catch (_: ActivityNotFoundException) { vm.toast("No PDF app installed — the document is shown here") }
}
