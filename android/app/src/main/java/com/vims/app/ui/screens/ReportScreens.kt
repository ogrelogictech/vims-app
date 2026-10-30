package com.vims.app.ui.screens

import com.vims.app.data.sectionTitle
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import kotlinx.coroutines.launch
import kotlin.math.roundToInt
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import androidx.navigation.NavHostController
import com.vims.app.data.ChecklistConfig
import com.vims.app.data.ChecklistEngine
import com.vims.app.data.CoverChoice
import com.vims.app.data.InspectionBundle
import com.vims.app.data.SecStatus
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.GeneratedR
import com.vims.app.ui.PdfR
import com.vims.app.ui.components.Banner
import com.vims.app.ui.components.BinfoRow
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.BtnRow
import com.vims.app.ui.components.HdrAction
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.Pill
import com.vims.app.ui.components.PillKind
import com.vims.app.ui.components.SuccessBlock
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.vCard
import com.vims.app.ui.goHome
import com.vims.app.ui.openSection
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.Locale

private fun hex(s: String) = Color(android.graphics.Color.parseColor(s))

fun coverBrush(vm: AppViewModel, color: String): Brush {
    val c = vm.config.covers.colors.firstOrNull { it.name == color } ?: vm.config.covers.colors.first()
    return Brush.linearGradient(listOf(hex(c.from), hex(c.to)))
}

/** Rough page estimate before the PDF exists (cover + info + notes + sections + photo pages + summary). */
fun estimatePages(b: InspectionBundle, layout: String = ChecklistConfig.LAYOUT_STANDARD): Int {
    val forms = b.inspection.leafSections.count { b.defs[com.vims.app.data.baseName(it)]?.photosOnly != true }
    val pics = maxOf(1, (b.photos.size + 5) / 6)
    if (layout == ChecklistConfig.LAYOUT_TEXAS) return 3 + forms + pics
    if (layout == ChecklistConfig.LAYOUT_FOUR_POINT) return 4 + pics
    val done = b.inspection.leafSections.filter { b.status(it) == SecStatus.DONE && !b.isNotes(it) }
    val photoPages = done.sumOf { s -> val n = b.photos.count { it.section == s }; (n + 5) / 6 }
    // Data v1.14: Planned Maintenance Recommendations adds a page when a line is written.
    val notes = b.inspection.leafSections.count { b.isNotes(it) && b.notesLines(it).isNotEmpty() }
    return 4 + done.size + photoPages + notes
}

@Composable
fun ReportScreen(vm: AppViewModel, nav: NavHostController, inspId: String) {
    val all by vm.inspections.collectAsState()
    val b = all[inspId] ?: run { MissingInspection(vm, nav); return }
    val generating by vm.generating.collectAsState()
    var drawer by rememberSaveable { mutableStateOf(false) }
    val cover = b.inspection.cover
    val s = b.inspection.selections

    VScreen(
        "Generate report", s.street, net(vm), backAction(nav), listOf(HdrAction(VIcons.list, "Sections") { drawer = true }, homeAction(nav)),
        overlay = {
            SectionsDrawer(drawer, b, null, { drawer = false }, { drawer = false; nav.openLink(it, inspId) }, { drawer = false; nav.openSection(inspId, it) })
            if (generating) Busy("Generating report…")
        },
    ) {
        // report meta card
        Column(Modifier.padding(bottom = 12.dp).fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(Brush.linearGradient(listOf(Color(0xFF274FB0), Color(0xFF101F45)))).padding(20.dp)) {
            Text("PROPERTY INSPECTION REPORT", style = T.mono(10.5.sp, color = Color(0xFFF2C869), letterSpacing = 0.14.em))
            Text(s.street, style = T.display(20.sp, FontWeight.ExtraBold, Color.White), modifier = Modifier.padding(top = 9.dp, bottom = 3.dp))
            Text(listOf(s.cityLine, "${propertyLabel(s.structure)} dwelling").filter { it.isNotBlank() }.joinToString(" · "), style = T.ui(12.5.sp, color = Color(0xFFCFE2EB)))
            Row(Modifier.padding(top = 15.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                MetaStat(if (b.inspection.reportPages > 0) "${b.inspection.reportPages}" else "~${estimatePages(b, vm.config.reportLayout(s.inspType))}", "PAGES")
                MetaStat("${b.findings.size}", "FINDINGS")
                MetaStat("${b.photos.size}", "PHOTOS")
            }
        }
        Lbl("Report cover")
        CoverPicker(vm, cover) { vm.setCover(inspId, it) }
        Lbl("Report pages")
        Text(reportPagesText(vm.config.reportLayout(s.inspType)), style = T.ui(13.sp, color = V.ink2, lineHeight = 19.5.sp),
            modifier = Modifier.padding(bottom = 12.dp).fillMaxWidth().vCard().padding(horizontal = 14.dp, vertical = 12.dp))
        Lbl("Report contents · in checklist order")
        Text("Completed sections populate the report in the order they're numbered on your master checklist.", style = T.ui(12.sp, color = V.ink3, lineHeight = 16.sp), modifier = Modifier.padding(start = 2.dp, end = 2.dp, bottom = 10.dp))
        // State forms print every system of the form; standard reports include completed sections.
        val formLayout = vm.config.reportLayout(s.inspType) != ChecklistConfig.LAYOUT_STANDARD
        // Data v1.14: a notes section (Planned Maintenance Recommendations) is listed after the checklist sections, only when a
        // line is written (it prints whether or not it was saved Done; a blank one is left out of the report).
        val done = b.inspection.leafSections.filter { !b.isNotes(it) && (formLayout && b.defs[com.vims.app.data.baseName(it)]?.photosOnly != true || b.status(it) == SecStatus.DONE) }
            .sortedWith(compareBy({ ChecklistEngine.number(b.defs, it) }, { it })) +
            (if (formLayout) emptyList() else b.inspection.leafSections.filter { b.isNotes(it) && b.notesLines(it).isNotEmpty() })
        Column(Modifier.padding(bottom = 12.dp).fillMaxWidth().vCard().padding(vertical = 6.dp)) {
            if (done.isEmpty()) BinfoRow({ Text("No sections completed yet", style = T.ui(14.sp, color = V.ink3)) }, {}, last = true)
            done.forEachIndexed { i, n ->
                val num = ChecklistEngine.number(b.defs, n)
                BinfoRow({
                    Text(if (num >= 99) "—" else String.format(Locale.US, "%02d", num), style = T.mono(14.sp, FontWeight.Bold, V.brandDeep), modifier = Modifier.padding(end = 8.dp))
                    Text(sectionTitle(n), style = T.ui(14.sp))
                }, { Pill("Included", PillKind.Done) }, last = i == done.lastIndex)
            }
        }
        VBtn("Preview report format", { vm.generateReport(inspId, markDone = false) { nav.navigate(PdfR(inspId)) } }, Modifier.padding(top = 10.dp), BtnKind.Ghost, VIcons.preview)
        if (vm.syncEnabled) Banner("You're **offline**. The report generates on the device now; it uploads on the next sync.", VIcons.offline, Modifier.padding(top = 16.dp))
        else Spacer(Modifier.height(16.dp))
        VBtn("Generate PDF report", { vm.generateReport(inspId, markDone = true) { nav.navigate(GeneratedR(inspId)) } }, icon = VIcons.download, enabled = !generating)
    }
}

fun reportPagesText(layout: String) = when (layout) {
    ChecklistConfig.LAYOUT_TEXAS -> "Cover · Inspector & property information (TREC REI 7-6) · Checklist (I / NI / NP / D) · Pictures · Summary"
    ChecklistConfig.LAYOUT_FOUR_POINT -> "Cover · 4-Point checklist (Electrical, HVAC, Plumbing, Roof) · Pictures"
    else -> "Cover · Property information · Beginning notes · Checklist sections with their photos · Planned maintenance recommendations (when written) · Summary"
}

@Composable
private fun MetaStat(n: String, l: String) {
    Column {
        Text(n, style = T.display(17.sp, FontWeight.Bold, Color.White))
        Text(l, style = T.mono(10.sp, color = Color(0xFFA9C6D2)))
    }
}

@Composable
fun Busy(text: String) {
    Box(Modifier.fillMaxSize().background(Color(0x800A0F16)).clickable(remember { MutableInteractionSource() }, null) {}, contentAlignment = Alignment.Center) {
        Row(Modifier.clip(RoundedCornerShape(14.dp)).background(V.paper).padding(horizontal = 22.dp, vertical = 18.dp), verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(Modifier.size(22.dp), color = V.brand, strokeWidth = 2.5.dp)
            Spacer(Modifier.width(14.dp))
            Text(text, style = T.ui(14.sp, FontWeight.SemiBold))
        }
    }
}

/**
 * Cover picker on ONE page (client Oct 17, `covers._pickerAbout`): Color, Theme (category + picture, or "No picture") and
 * Style (Shaded, Framed, Solid — `covers.styles` order; Solid can carry a picture), with a live preview tile.
 */
@Composable
fun CoverPicker(vm: AppViewModel, saved: CoverChoice, onChange: (CoverChoice) -> Unit) {
    val cfg = vm.config.covers
    val cover = saved.normalized()
    val noPic = cfg.noThemeOption
    // Theme artwork (shared/covers, data v1.6) for the preview tile, decoded off the main thread.
    val ctx = LocalContext.current
    val artFile = cfg.art(cover)?.file
    val art by produceState<ImageBitmap?>(null, artFile) {
        value = artFile?.let { f ->
            withContext(Dispatchers.IO) {
                try { ctx.assets.open(f).use { android.graphics.BitmapFactory.decodeStream(it, null, android.graphics.BitmapFactory.Options().apply { inSampleSize = 2 }) }?.asImageBitmap() } catch (_: Exception) { null }
            }
        }
    }
    // preview
    Row(Modifier.padding(bottom = 6.dp).fillMaxWidth().vCard().padding(13.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp)) {
        Box(Modifier.width(78.dp).height(104.dp).clip(RoundedCornerShape(9.dp)).background(coverBrush(vm, cover.color))) {
            // The chosen theme's artwork in the corner of the color tile (like the prototype's .coverprev); No picture shows the color name.
            val a = art
            if (artFile != null && a != null) {
                Image(a, "${cover.option} cover artwork", Modifier.align(Alignment.BottomEnd).fillMaxWidth(.92f).fillMaxHeight(.92f), alignment = Alignment.BottomEnd, contentScale = ContentScale.Fit)
            } else if (artFile == null) {
                // Fixed-size art tile: keep the label's size stable under large system font scales.
                val fs = androidx.compose.ui.platform.LocalDensity.current.fontScale
                Text(cover.artLabel(), style = T.display((11f / fs).sp, FontWeight.Bold, Color.White, lineHeight = (12.7f / fs).sp), modifier = Modifier.align(Alignment.BottomStart).padding(8.dp))
            }
        }
        Column(Modifier.weight(1f)) {
            Text(cover.label(), style = T.ui(15.sp, FontWeight.Bold))
            Text("Color, theme and style, all on this page", style = T.ui(12.5.sp, color = V.ink3))
        }
    }
    Lbl("Color")
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        cfg.colors.forEach { c ->
            val on = cover.color == c.name
            Column(
                Modifier.weight(1f).clip(RoundedCornerShape(13.dp)).background(V.paper).border(2.dp, if (on) V.brand else V.line, RoundedCornerShape(13.dp))
                    .clickable(role = Role.RadioButton) { onChange(cover.copy(color = c.name)) },
            ) {
                Box(Modifier.fillMaxWidth().height(48.dp).background(Brush.linearGradient(listOf(hex(c.from), hex(c.to)))))
                Text(c.name, style = T.ui(12.5.sp, FontWeight.SemiBold, if (on) V.brand else V.ink2), textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(vertical = 9.dp))
            }
        }
    }
    Lbl("Theme")
    OptGrid(cfg.categories.keys.toList(), cover.category) { cat ->
        // A new category starts on its first picture; the style is kept (every style can carry a picture).
        onChange(cover.copy(category = cat, option = cfg.categories[cat].orEmpty().firstOrNull() ?: noPic))
    }
    Lbl("Picture")
    OptGrid(listOf(noPic) + cfg.categories[cover.category].orEmpty(), if (cover.hasPicture) cover.option else noPic) { onChange(cover.copy(option = it)) }
    Lbl("Style")
    OptGrid(cfg.styles.ifEmpty { listOf("Shaded", "Framed", "Solid") }, cover.style, columns = 3) { onChange(cover.copy(style = it)) }
}

@Composable
private fun OptGrid(options: List<String>, selected: String, columns: Int = 2, onPick: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(9.dp)) {
        options.chunked(columns).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                row.forEach { o ->
                    val on = o == selected
                    Row(
                        Modifier.weight(1f).heightIn(min = 48.dp).clip(RoundedCornerShape(12.dp)).background(if (on) V.brand.copy(alpha = .06f) else V.paper)
                            .border(1.5.dp, if (on) V.brand else V.line, RoundedCornerShape(12.dp)).clickable(role = Role.RadioButton) { onPick(o) }.padding(horizontal = 12.dp, vertical = 13.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(o, style = T.ui(13.5.sp, FontWeight.SemiBold, if (on) V.brandDeep else V.ink2), modifier = Modifier.weight(1f))
                        if (on) Icon(VIcons.check, null, tint = V.brand, modifier = Modifier.size(16.dp))
                    }
                }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** The signed-in user's own email, CC'd on every emailed report when `support.ccInspector` is in the data (v1.3). */
fun reportCc(vm: AppViewModel): String? = vm.session.value?.email?.trim()?.takeIf { vm.config.support.ccInspectorOn && it.isNotEmpty() }

/** Report recipients (To): client + agent, or the client only when the inspection's send-to-agent box is unchecked. */
fun reportTo(s: com.vims.app.data.WizardSelections): List<String> = listOfNotNull(s.clientEmail, s.agentEmail.takeIf { s.sendToAgent }).filter { it.isNotBlank() }

fun shareReport(ctx: Context, vm: AppViewModel, b: InspectionBundle, file: File) {
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", file)
    val s = b.inspection.selections
    val review = vm.company.value.reviewUrl
    val body = buildString {
        append("Hi ${s.clientName.ifBlank { "there" }},\n\nAttached is your inspection report for ${s.fullAddress.ifBlank { s.street }}.")
        if (review.isNotBlank()) append("\n\nIf you have a moment, we'd appreciate a review: $review")
        append("\n\n${vm.company.value.inspectorName.ifBlank { vm.company.value.name }}\n${vm.company.value.name}")
    }
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "application/pdf"
        putExtra(Intent.EXTRA_STREAM, uri)
        // To: the client, plus the agent unless "Send the report to the real estate agent" is off (step 1; off by default in NH).
        putExtra(Intent.EXTRA_EMAIL, reportTo(s).toTypedArray())
        // support.ccInspector (data v1.3): the signed-in inspector gets a CC (archive copy).
        reportCc(vm)?.let { putExtra(Intent.EXTRA_CC, arrayOf(it)) }
        // Client Oct 30 (shared v1.13.0): NO Bcc on this compose — the phone's mail app shows the Bcc line to the inspector.
        // The platform "Report quality copy" (vm.platform.value.activeBcc) is sent separately by the VIMS server.
        // TODO(backend): when the report is emailed, POST it to the VIMS API so the server mails the quality copy to
        // PlatformSettings.activeBcc; until that endpoint exists no quality copy is sent.
        putExtra(Intent.EXTRA_SUBJECT, "Inspection report — ${s.street}")
        putExtra(Intent.EXTRA_TEXT, body)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    if (com.vims.app.BuildConfig.DEBUG) android.util.Log.d("VIMS-Share", "ACTION_SEND extras=${send.extras?.keySet()?.sorted()} to=${send.getStringArrayExtra(Intent.EXTRA_EMAIL)?.toList()} cc=${send.getStringArrayExtra(Intent.EXTRA_CC)?.toList()} bcc=${send.getStringArrayExtra(Intent.EXTRA_BCC)?.toList()} subject=${send.getStringExtra(Intent.EXTRA_SUBJECT)}")
    try { ctx.startActivity(Intent.createChooser(send, "Send report")) } catch (_: Exception) { vm.toast("No app available to send the report") }
}

/** Save or share the report PDF (Drive, Files, email to yourself…) — no client recipients prefilled. */
fun saveOrShareReport(ctx: Context, vm: AppViewModel, b: InspectionBundle, file: File) {
    val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", file)
    val send = Intent(Intent.ACTION_SEND).apply {
        type = "application/pdf"
        putExtra(Intent.EXTRA_STREAM, uri)
        putExtra(Intent.EXTRA_SUBJECT, "Inspection report — ${b.inspection.selections.street}")
        clipData = android.content.ClipData.newRawUri(file.name, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    try { ctx.startActivity(Intent.createChooser(send, "Save or share report")) } catch (_: Exception) { vm.toast("No app available to save the report") }
}

@Composable
fun GeneratedScreen(vm: AppViewModel, nav: NavHostController, inspId: String) {
    val all by vm.inspections.collectAsState()
    val b = all[inspId] ?: run { MissingInspection(vm, nav); return }
    val ctx = LocalContext.current
    val s = b.inspection.selections
    VScreen("Report ready", s.street, net(vm), backAction(nav), listOf(homeAction(nav))) {
        SuccessBlock("Report generated", "${b.inspection.reportPages}-page report for ${s.street} is saved on this device${if (vm.syncEnabled) " and queued to sync to the portal" else ""}.") {
            VBtn("Email to client", {
                val f = vm.reportFile(inspId)
                if (f != null) shareReport(ctx, vm, b, f) else vm.generateReport(inspId, markDone = true) { shareReport(ctx, vm, b, it) }
            }, icon = VIcons.mail)
            // CC = the inspector's own address (shown). The report-quality copy is sent by the VIMS server (client Oct 30), so it
            // is not on the compose and not mentioned here.
            val cc = reportCc(vm)
            val note = listOfNotNull(
                when {
                    !s.sendToAgent -> "Goes to the client only — sending to the real estate agent is off for this inspection."
                    s.agentEmail.isNotBlank() -> "Goes to the client and the real estate agent."
                    else -> null
                },
                cc?.let { "A copy goes to you ($it)." },
                if (cc != null) "Some email apps may drop copies." else null,
            ).joinToString(" ")
            if (note.isNotEmpty()) Text(note, style = T.ui(11.5.sp, color = V.ink3, lineHeight = 15.sp), textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
            VBtn("Preview PDF", { nav.navigate(PdfR(inspId)) }, Modifier.padding(top = 10.dp), BtnKind.Ghost, VIcons.preview)
            VBtn("Back to inspections", { nav.goHome() }, Modifier.padding(top = 10.dp), BtnKind.Ghost)
            DeleteInspectionButton(vm, nav, b, Modifier.padding(top = 10.dp))
        }
    }
}

/** In-app PDF preview (PdfRenderer) of the generated report. */
@Composable
fun PdfPreviewScreen(vm: AppViewModel, nav: NavHostController, inspId: String) {
    val all by vm.inspections.collectAsState()
    val b = all[inspId] ?: run { MissingInspection(vm, nav); return }
    val ctx = LocalContext.current
    val file = remember(b.inspection.reportFile, b.inspection.reportGeneratedAt) { vm.reportFile(inspId) }
    val renderer = remember(file) {
        file?.let { try { PdfRenderer(ParcelFileDescriptor.open(it, ParcelFileDescriptor.MODE_READ_ONLY)) } catch (_: Exception) { null } }
    }
    DisposableEffect(renderer) { onDispose { renderer?.close() } }
    VScreen(
        "Report preview", b.inspection.selections.street, net(vm), backAction(nav),
        listOf(HdrAction(VIcons.share, "Share report") { file?.let { shareReport(ctx, vm, b, it) } }, homeAction(nav)), scroll = false,
    ) {
        if (renderer == null) {
            Text("No report generated yet.", style = T.ui(14.sp, color = V.ink3), modifier = Modifier.padding(16.dp))
            return@VScreen
        }
        Hint("${renderer.pageCount} pages · US Letter · saved on this device", Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp), size = 12f)
        val listState = rememberLazyListState()
        Box(Modifier.fillMaxSize()) {
            // End padding leaves a gutter for the fast-scroll thumb.
            LazyColumn(Modifier.fillMaxSize(), state = listState, contentPadding = PaddingValues(start = 16.dp, top = 16.dp, end = 22.dp, bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                items(renderer.pageCount) { i -> PdfPage(renderer, i, "Report page ${i + 1}") }
            }
            PageFastScroller(listState, renderer.pageCount)
        }
    }
}

/**
 * Fast-scroll bar on the right edge of the report preview (client, Oct 16): the thumb follows normal scrolling, drags to
 * jump through the report, and shows a "Page X of N" bubble while it is dragged. Only the thumb takes touches, so the
 * pages still scroll under the rest of the edge. Every page has the same height (US Letter at the list's width).
 */
@Composable
private fun PageFastScroller(state: LazyListState, pageCount: Int) {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    val thumbH = 56.dp; val hitW = 44.dp; val inset = 6.dp
    val thumbPx = with(density) { thumbH.toPx() }
    var trackPx by remember { mutableIntStateOf(0) }
    var dragging by remember { mutableStateOf(false) }
    var dragFrac by remember { mutableFloatStateOf(0f) }
    // (page stride, max scroll, viewport) in px from the laid-out list; null until a page is laid out or when it all fits.
    val metrics by remember(state, pageCount) {
        derivedStateOf {
            val info = state.layoutInfo
            val first = info.visibleItemsInfo.firstOrNull() ?: return@derivedStateOf null
            val stride = first.size + info.mainAxisItemSpacing
            val viewport = info.viewportSize.height
            val max = info.beforeContentPadding + pageCount * stride - info.mainAxisItemSpacing + info.afterContentPadding - viewport
            if (pageCount < 2 || max <= 0) null else Triple(stride, max, viewport)
        }
    }
    val m = metrics ?: return
    val scrolled = state.firstVisibleItemIndex * m.first + state.firstVisibleItemScrollOffset
    val frac = if (dragging) dragFrac else (scrolled / m.second.toFloat()).coerceIn(0f, 1f)
    // Page under the middle of the screen (first / last page at the ends of the range).
    fun pageAt(f: Float): Int = when {
        f <= 0f -> 1
        f >= 1f -> pageCount
        else -> ((f * m.second + m.third / 2f - state.layoutInfo.beforeContentPadding) / m.first).toInt().coerceIn(0, pageCount - 1) + 1
    }
    val thumbY = ((trackPx - thumbPx).coerceAtLeast(0f) * frac).roundToInt()
    Box(Modifier.fillMaxSize().padding(vertical = inset).onSizeChanged { trackPx = it.height }) {
        // faint track so it reads as a scroll bar
        Box(Modifier.align(Alignment.TopEnd).padding(end = 8.dp).width(4.dp).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(V.ink.copy(alpha = .08f)))
        Row(Modifier.align(Alignment.TopEnd).offset { IntOffset(0, thumbY) }, verticalAlignment = Alignment.CenterVertically) {
            if (dragging) {
                Text("Page ${pageAt(frac)} of $pageCount", style = T.ui(13.sp, FontWeight.SemiBold, Color.White),
                    modifier = Modifier.shadow(4.dp, RoundedCornerShape(8.dp)).clip(RoundedCornerShape(8.dp)).background(V.ink).padding(horizontal = 12.dp, vertical = 7.dp))
            }
            Box(
                Modifier.size(hitW, thumbH)
                    .semantics { contentDescription = "Page ${pageAt(frac)} of $pageCount. Drag to jump through the report." }
                    .pointerInput(pageCount) {
                        detectVerticalDragGestures(
                            onDragStart = { dragFrac = (scrollFrac(state, metrics)); dragging = true },
                            onDragEnd = { dragging = false }, onDragCancel = { dragging = false },
                        ) { change, dy ->
                            change.consume()
                            val mm = metrics ?: return@detectVerticalDragGestures
                            val range = (trackPx - thumbPx).coerceAtLeast(1f)
                            dragFrac = (dragFrac + dy / range).coerceIn(0f, 1f)
                            val target = dragFrac * mm.second
                            val idx = (target / mm.first).toInt().coerceIn(0, pageCount - 1)
                            scope.launch { state.scrollToItem(idx, (target - idx * mm.first).roundToInt()) }
                        }
                    },
                contentAlignment = Alignment.CenterEnd,
            ) {
                Box(
                    Modifier.padding(end = 6.dp).width(if (dragging) 10.dp else 8.dp).height(thumbH - 8.dp).shadow(2.dp, RoundedCornerShape(5.dp))
                        .clip(RoundedCornerShape(5.dp)).background(if (dragging) V.brand else V.brand.copy(alpha = .78f))
                        .border(1.dp, Color.White.copy(alpha = .7f), RoundedCornerShape(5.dp)),
                )
            }
        }
    }
}

private fun scrollFrac(state: LazyListState, m: Triple<Int, Int, Int>?): Float =
    if (m == null) 0f else ((state.firstVisibleItemIndex * m.first + state.firstVisibleItemScrollOffset) / m.second.toFloat()).coerceIn(0f, 1f)

private val pdfLock = Any()

/** One rendered PDF page (report preview and state documents). */
@Composable
fun PdfPage(renderer: PdfRenderer, index: Int, description: String) {
    val img by produceState<ImageBitmap?>(null, renderer, index) {
        value = withContext(Dispatchers.IO) {
            synchronized(pdfLock) {
                try {
                    renderer.openPage(index).use { p ->
                        val w = 1100; val h = (w * p.height / p.width.toFloat()).toInt()
                        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                        bmp.eraseColor(android.graphics.Color.WHITE)
                        p.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                        bmp.asImageBitmap()
                    }
                } catch (_: Exception) { null }
            }
        }
    }
    Box(Modifier.fillMaxWidth().aspectRatio(8.5f / 11f).shadow(6.dp, RoundedCornerShape(4.dp)).background(Color.White), contentAlignment = Alignment.Center) {
        img?.let { Image(it, description, Modifier.fillMaxSize(), contentScale = ContentScale.Fit) } ?: CircularProgressIndicator(Modifier.size(24.dp), color = V.brand)
    }
}
