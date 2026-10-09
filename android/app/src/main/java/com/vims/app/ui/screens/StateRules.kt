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
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.autofill.ContentDataType
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.contentDataType
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import com.vims.app.data.StateDef
import com.vims.app.util.Filters
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

/* State rules (vims-checklists.json v1.3 `states` + `stateRules`) — wizard step 1 State type-ahead, the state's note card,
 * required state documents (View / Send to client / "Provided to the client…" acknowledgment) and the in-app viewer. */

const val STATE_KEY = "State"
const val STATE_ACK_KEY = "stateDocsAck"

/**
 * Required "State" type-ahead (right after Inspection address) + the selected state's note card and documents.
 * It is a real text field, so the keyboard types into it (before, the read-only dropdown never took focus and the typed
 * letters landed in the still-focused address line). Tapping it clears the box (the current state stays as the
 * placeholder) and lists every state; typing a name or 2-letter code filters the list; tap or keyboard Next picks the
 * best match and Next moves on to the following field. Leaving with an exact / single match picks it, otherwise the
 * previous state is kept.
 */
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
    val focus = LocalFocusManager.current
    val selectedName = if (sel.state.isBlank()) "" else cfg.stateName(sel.state)
    var focused by remember { mutableStateOf(false) }
    var open by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf(TextFieldValue(selectedName)) }
    // Not focused: shows the chosen state's name (also after a pick or an edit-inspection load). Focused: starts empty
    // (current state as the placeholder) — set here, after the tap that focused it has placed its cursor in the old text.
    LaunchedEffect(selectedName, focused) { query = TextFieldValue(if (focused) "" else selectedName); if (focused) open = true }
    val matches = remember(query.text, focused) { if (focused) stateMatches(cfg.states, query.text) else cfg.states }
    fun pick(code: String) { if (code != sel.state) vm.setInspState(code); query = TextFieldValue(cfg.stateName(code)); open = false }
    /** Exact name / code first, then the only (or, for Next, the first) remaining match. */
    fun typedMatch(first: Boolean): String? {
        val t = query.text.trim()
        if (t.isEmpty()) return null
        cfg.states.firstOrNull { it.code.equals(t, true) || it.name.equals(t, true) }?.let { return it.code }
        return if (first || matches.size == 1) matches.firstOrNull()?.code else null
    }
    val shape = RoundedCornerShape(11.dp)
    Column(Modifier.padding(bottom = 13.dp).formField(form, STATE_KEY)) {
        FieldLabel("State", required = true)
        ExposedDropdownMenuBox(expanded = open && focused, onExpandedChange = { open = it }) {
            BasicTextField(
                value = query,
                onValueChange = { v -> query = v.copy(text = Filters.base(v.text, 40)); open = true },
                singleLine = true,
                textStyle = T.ui(15.sp, color = V.ink),
                cursorBrush = SolidColor(V.brand),
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, autoCorrectEnabled = false, imeAction = ImeAction.Next),
                keyboardActions = KeyboardActions(onNext = {
                    typedMatch(first = true)?.let { pick(it) }
                    open = false
                    focus.moveFocus(FocusDirection.Next)
                }),
                modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryEditable).fillMaxWidth()
                    .semantics { contentDataType = ContentDataType.None }
                    .onFocusChanged { f ->
                        if (f.isFocused == focused) return@onFocusChanged
                        focused = f.isFocused
                        if (!f.isFocused) { typedMatch(first = false)?.let { pick(it) }; open = false }
                    },
                decorationBox = { inner ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 48.dp).clip(shape).background(V.paper)
                            .border(if (focused || err != null) (if (err != null && !focused) 1.5.dp else 2.dp) else 1.dp, if (err != null && !focused) V.c1 else if (focused) V.brand else V.line, shape)
                            .padding(start = 14.dp, end = 12.dp, top = 12.dp, bottom = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Box(Modifier.weight(1f)) {
                            if (query.text.isEmpty()) Text(
                                if (focused && selectedName.isNotEmpty()) selectedName else if (focused) "Type the state or its 2-letter code" else "Select the property’s state…",
                                style = T.ui(15.sp, color = V.placeholder), maxLines = 1, overflow = TextOverflow.Ellipsis,
                            )
                            inner()
                        }
                        Icon(VIcons.chevDown, null, tint = V.ink, modifier = Modifier.padding(start = 8.dp).size(16.dp))
                    }
                },
            )
            ExposedDropdownMenu(expanded = open && focused, onDismissRequest = { open = false }, containerColor = V.paper) {
                if (matches.isEmpty()) {
                    DropdownMenuItem(text = { Text("No state matches “${query.text.trim()}”", style = T.ui(14.sp, color = V.ink3)) }, onClick = {}, enabled = false)
                }
                matches.forEach { st ->
                    val on = st.code == sel.state
                    DropdownMenuItem(
                        text = { Text(st.name, style = T.ui(14.5.sp, if (on) FontWeight.Bold else FontWeight.Normal, if (on) V.brandDeep else V.ink)) },
                        onClick = { pick(st.code); focus.clearFocus() },
                        trailingIcon = if (on) ({ Icon(VIcons.check, null, tint = V.brand, modifier = Modifier.size(16.dp)) }) else ({ Text(st.code, style = T.mono(12.sp, color = V.ink3)) }),
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

/** Type-ahead order: 2-letter code, then names starting with the text, then any word of the name ("York", "Dakota"). */
fun stateMatches(states: List<StateDef>, text: String): List<StateDef> {
    val t = text.trim()
    if (t.isEmpty()) return states
    val code = states.filter { it.code.equals(t, true) }
    val prefix = states.filter { it.name.startsWith(t, true) }
    val word = states.filter { st -> st.name.split(' ').any { it.startsWith(t, true) } }
    return (code + prefix + word).distinct()
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
