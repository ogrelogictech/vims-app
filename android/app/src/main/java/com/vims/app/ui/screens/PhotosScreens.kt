package com.vims.app.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.navigation.NavHostController
import com.vims.app.data.ChecklistEngine
import com.vims.app.data.Photo
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.CameraR
import com.vims.app.ui.MarkupR
import com.vims.app.ui.ReportR
import com.vims.app.ui.SectionR
import com.vims.app.ui.SummaryR
import com.vims.app.ui.back
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.BtnRow
import com.vims.app.ui.components.FieldLabel
import com.vims.app.ui.components.HdrAction
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.SelectBox
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VInput
import com.vims.app.ui.components.VScreen
import com.vims.app.ui.components.dashedBorder
import com.vims.app.ui.openSection
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Images
import com.vims.app.util.rememberThumb
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/* ================================================================ Photos by category */

@Composable
fun PhotosScreen(vm: AppViewModel, nav: NavHostController, inspId: String, name: String) {
    val all by vm.inspections.collectAsState()
    val b = all[inspId] ?: run { MissingInspection(vm, nav); return }
    val version by vm.photoVersion.collectAsState()
    val def = vm.sectionDef(inspId, name)
    val cats = ChecklistEngine.photoCategories(def, b.inspection.selections.depth)
    val picturesPage = def?.photosOnly == true
    val photos = b.photos.filter { it.section == name }
    var drawer by rememberSaveable { mutableStateOf(false) }

    VScreen(
        if (picturesPage) name else "$name photos", b.inspection.selections.street, net(vm), backAction(nav),
        listOf(HdrAction(VIcons.list, "Sections") { drawer = true }, homeAction(nav)),
        overlay = { SectionsDrawer(drawer, b, name, { drawer = false }, { drawer = false; nav.openLink(it, inspId) }, { drawer = false; nav.openSection(inspId, it) }) },
    ) {
        Hint((if (picturesPage) "These pictures print on the picture pages after the checklist. " else "") +
            "Tap **Add** to capture a photo, tap a photo to mark it up or flag it, or tap **×** to delete one.", Modifier.padding(top = 2.dp, bottom = 14.dp))
        (cats + photos.map { it.category }.filter { it !in cats }.distinct()).forEach { cat ->
            val list = photos.filter { it.category == cat }
            Column(Modifier.padding(bottom = 16.dp)) {
                Row(Modifier.fillMaxWidth().padding(bottom = 9.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(cat, style = T.ui(14.sp, FontWeight.SemiBold), modifier = Modifier.weight(1f))
                    Text("${list.size} photo${if (list.size == 1) "" else "s"}", style = T.mono(11.sp, color = V.ink3))
                }
                val tiles: List<Photo?> = list + listOf(null)
                tiles.chunked(3).forEach { row ->
                    Row(Modifier.fillMaxWidth().padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        row.forEach { p ->
                            Box(Modifier.weight(1f).aspectRatio(1f)) {
                                if (p == null) AddTile { nav.navigate(CameraR(inspId, name, cat)) }
                                else PhotoTile(vm.repo.photoFile(p), p.flag, version, onOpen = { nav.navigate(MarkupR(inspId, p.id)) }, onDelete = { vm.deletePhoto(inspId, p.id) })
                            }
                        }
                        repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
        if (picturesPage) {
            val toSummary = b.inspection.hasSummary
            VBtn("Save & continue to ${if (toSummary) "summary" else "report"}", {
                vm.saveSection(inspId, name); vm.toast("Pictures saved")
                if (toSummary) nav.navigate(SummaryR(inspId)) else nav.navigate(ReportR(inspId))
            }, Modifier.padding(top = 6.dp), icon = VIcons.checkNext)
        } else {
            VBtn("Done", { if (!nav.popBackStack<SectionR>(inclusive = false)) nav.openSection(inspId, name) }, Modifier.padding(top = 6.dp))
        }
    }
}

@Composable
private fun AddTile(onClick: () -> Unit) {
    Column(
        Modifier.fillMaxSize().clip(RoundedCornerShape(11.dp)).background(V.paper).dashedBorder(V.brand, 11.dp, 1.5.dp).clickable(role = Role.Button, onClickLabel = "Add photo", onClick = onClick),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
    ) {
        Icon(VIcons.camera, null, tint = V.brand, modifier = Modifier.size(22.dp))
        Spacer(Modifier.height(3.dp))
        Text("Add", style = T.ui(10.5.sp, FontWeight.SemiBold, V.brand))
    }
}

@Composable
private fun PhotoTile(file: File, flag: Int, version: Int, onOpen: () -> Unit, onDelete: () -> Unit) {
    val img by rememberThumb(file, version)
    Box(Modifier.fillMaxSize().clip(RoundedCornerShape(11.dp)).background(V.paper3).border(1.dp, V.line, RoundedCornerShape(11.dp)).clickable(role = Role.Image, onClickLabel = "Mark up photo", onClick = onOpen)) {
        img?.let { Image(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
        Box(Modifier.size(48.dp).clickable(role = Role.Button, onClickLabel = "Delete photo", onClick = onDelete).padding(4.dp)) {
            Box(Modifier.size(26.dp).clip(RoundedCornerShape(7.dp)).background(Color(0x9E0C1119)), contentAlignment = Alignment.Center) {
                Text("×", style = T.ui(17.sp, color = Color.White))
            }
        }
        if (flag > 0) Box(
            Modifier.align(Alignment.TopEnd).padding(5.dp).size(22.dp).clip(RoundedCornerShape(6.dp)).background(V.cat(flag)), contentAlignment = Alignment.Center,
        ) { Text("$flag", style = T.mono(11.sp, FontWeight.Bold, Color.White)) }
    }
}

/* ================================================================ Camera (CameraX) */

@Composable
fun CameraScreen(vm: AppViewModel, nav: NavHostController, inspId: String, name: String, cat: String) {
    val ctx = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    var granted by remember { mutableStateOf(ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var asked by rememberSaveable { mutableStateOf(false) }
    var cameraError by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var ready by remember { mutableStateOf(false) }
    val capture = remember { ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY).build() }

    fun openMarkup(p: Photo) = nav.navigate(MarkupR(inspId, p.id)) { popUpTo<CameraR> { inclusive = true } }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted = it }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch { vm.importPhoto(inspId, name, cat, uri)?.let { vm.toast("Photo added"); openMarkup(it) } ?: vm.toast("Could not read that photo") }
    }
    LaunchedEffect(Unit) { if (!granted && !asked) { asked = true; permission.launch(Manifest.permission.CAMERA) } }

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        if (granted && !cameraError) {
            AndroidView(
                factory = { c ->
                    PreviewView(c).apply {
                        scaleType = PreviewView.ScaleType.FILL_CENTER
                        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
                        val future = ProcessCameraProvider.getInstance(c)
                        future.addListener({
                            try {
                                val provider = future.get()
                                val preview = Preview.Builder().build().also { it.surfaceProvider = surfaceProvider }
                                provider.unbindAll()
                                provider.bindToLifecycle(lifecycle, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture)
                                ready = true
                            } catch (_: Exception) { cameraError = true }
                        }, ContextCompat.getMainExecutor(c))
                    }
                },
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Column(Modifier.align(Alignment.Center).padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(VIcons.camera, null, tint = Color.White, modifier = Modifier.size(40.dp))
                Spacer(Modifier.height(12.dp))
                Text(if (cameraError) "The camera isn't available on this device." else "Allow camera access to capture inspection photos, or choose one from your library.",
                    style = T.ui(14.sp, color = Color.White, lineHeight = 20.sp), textAlign = TextAlign.Center)
                Spacer(Modifier.height(16.dp))
                if (!cameraError) VBtn("Allow camera", { permission.launch(Manifest.permission.CAMERA) }, Modifier.width(220.dp))
                VBtn("Choose from library", { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, Modifier.padding(top = 10.dp).width(220.dp), BtnKind.Ghost, VIcons.image)
            }
        }
        // top bar
        Row(
            Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color(0xCC000000), Color.Transparent))).statusBarsPadding().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            DarkBtn(VIcons.close, "Close") { nav.back() }
            Text("$name — $cat", style = T.ui(14.sp, FontWeight.SemiBold, Color.White), modifier = Modifier.weight(1f))
        }
        // bottom controls
        if (granted && !cameraError) Row(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().background(Color(0x99000000)).navigationBarsPadding().padding(horizontal = 28.dp, vertical = 22.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            DarkBtn(VIcons.image, "Choose from library") { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
            Spacer(Modifier.weight(1f))
            Box(
                Modifier.size(76.dp).clip(CircleShape).border(4.dp, Color.White, CircleShape).padding(7.dp).clip(CircleShape)
                    .background(if (busy || !ready) Color.White.copy(alpha = .5f) else Color.White)
                    .clickable(enabled = !busy && ready, role = Role.Button, onClickLabel = "Take photo") {
                        busy = true
                        val (pid, file) = vm.newPhotoFile(inspId)
                        capture.takePicture(ImageCapture.OutputFileOptions.Builder(file).build(), ContextCompat.getMainExecutor(ctx),
                            object : ImageCapture.OnImageSavedCallback {
                                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                                    scope.launch {
                                        withContext(Dispatchers.IO) { Images.normalizeJpeg(file) }
                                        val p = vm.addPhoto(inspId, name, cat, pid, file)
                                        vm.toast("Photo captured")
                                        openMarkup(p)
                                    }
                                }
                                override fun onError(exception: ImageCaptureException) { busy = false; vm.toast("Couldn't capture — try again") }
                            })
                    },
            )
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.size(48.dp))
        }
    }
    DisposableEffect(Unit) { onDispose { try { ProcessCameraProvider.getInstance(ctx).get().unbindAll() } catch (_: Exception) {} } }
}

@Composable
private fun DarkBtn(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, onClick: () -> Unit) {
    Box(Modifier.size(48.dp).clip(RoundedCornerShape(10.dp)).background(Color.White.copy(alpha = .12f)).clickable(role = Role.Button, onClickLabel = label, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = Color.White, modifier = Modifier.size(19.dp))
    }
}

/* ================================================================ Photo markup viewer */

private data class Mark(val color: Color, val points: List<Offset> = emptyList(), val stamp: String? = null)

@Composable
fun MarkupScreen(vm: AppViewModel, nav: NavHostController, inspId: String, photoId: String, openFinding: Boolean) {
    val all by vm.inspections.collectAsState()
    val b = all[inspId]
    val photo = b?.photos?.firstOrNull { it.id == photoId }
    if (b == null || photo == null) { MissingInspection(vm, nav); return }
    val version by vm.photoVersion.collectAsState()
    val file = vm.repo.photoFile(photo)
    val img by rememberThumb(file, version, 2048)
    val pens = listOf(Color(0xFFE5483B), Color(0xFFF0C020), Color(0xFF3D8BF0))
    var pen by remember { mutableStateOf(pens[0]) }
    var stamp by remember { mutableStateOf<String?>(null) }
    val marks = remember { mutableStateListOf<Mark>() }
    var current by remember { mutableStateOf<Mark?>(null) }
    var quick by rememberSaveable { mutableStateOf(photo.quickComment) }
    var custom by rememberSaveable { mutableStateOf(photo.customComment) }
    var sheet by rememberSaveable { mutableStateOf(openFinding) }
    val geo = remember { floatArrayOf(1f) } // display scale (view px per image px), for flattening
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val quickComments = vm.config.findings.quickComments

    fun save(then: () -> Unit) {
        val bmp = img
        scope.launch {
            val k = 1f / geo[0].coerceAtLeast(0.01f)
            val flat = if (marks.isNotEmpty() && bmp != null) withContext(Dispatchers.Default) { flatten(bmp, marks.toList(), with(density) { 4.dp.toPx() } * k, with(density) { 34.sp.toPx() } * k) } else null
            vm.saveMarkup(inspId, photoId, flat, quick, custom) { then() }
        }
    }

    BackHandler(enabled = sheet) { sheet = false }

    Box(Modifier.fillMaxSize().background(V.viewerBg)) {
        Column(Modifier.fillMaxSize().imePadding()) {
            Row(Modifier.fillMaxWidth().statusBarsPadding().padding(start = 14.dp, end = 14.dp, top = 10.dp, bottom = 10.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                DarkBtn(VIcons.close, "Close") { nav.back() }
                Text("${photo.section} — ${photo.category}", style = T.ui(14.sp, FontWeight.SemiBold, Color.White), modifier = Modifier.weight(1f), maxLines = 1)
                DarkBtn(VIcons.flag, "Flag a finding") { sheet = true }
            }
            // stage
            BoxWithConstraints(Modifier.weight(1f).fillMaxWidth()) {
                val bmp = img
                if (bmp != null) {
                    val cw = constraints.maxWidth.toFloat(); val ch = constraints.maxHeight.toFloat()
                    val s = minOf(cw / bmp.width, ch / bmp.height)
                    val dw = bmp.width * s; val dh = bmp.height * s
                    val left = (cw - dw) / 2; val top = (ch - dh) / 2
                    geo[0] = s
                    fun toImg(o: Offset) = Offset(((o.x - left) / dw).coerceIn(0f, 1f), ((o.y - top) / dh).coerceIn(0f, 1f))
                    fun toView(o: Offset) = Offset(left + o.x * dw, top + o.y * dh)
                    Image(bmp, "Inspection photo", Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                    Canvas(
                        Modifier.fillMaxSize().pointerInput(stamp, pen, bmp) {
                            awaitEachGesture {
                                val down = awaitFirstDown()
                                val st = stamp
                                if (st != null) { marks.add(Mark(pen, listOf(toImg(down.position)), st)); return@awaitEachGesture }
                                var m = Mark(pen, listOf(toImg(down.position)))
                                current = m
                                while (true) {
                                    val ev = awaitPointerEvent()
                                    val c = ev.changes.firstOrNull() ?: break
                                    if (!c.pressed) break
                                    c.consume()
                                    m = m.copy(points = m.points + toImg(c.position)); current = m
                                }
                                marks.add(m); current = null
                            }
                        },
                    ) {
                        val strokeW = 4.dp.toPx()
                        (marks + listOfNotNull(current)).forEach { mk ->
                            if (mk.stamp != null) {
                                val p = toView(mk.points.first())
                                drawContext.canvas.nativeCanvas.drawText(mk.stamp, p.x, p.y + 34.sp.toPx() * .35f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = mk.color.toArgb(); textSize = 34.sp.toPx(); textAlign = Paint.Align.CENTER; typeface = Typeface.DEFAULT_BOLD })
                            } else if (mk.points.isNotEmpty()) {
                                val path = Path().apply { val f = toView(mk.points.first()); moveTo(f.x, f.y); mk.points.drop(1).forEach { val v = toView(it); lineTo(v.x, v.y) }; if (mk.points.size == 1) lineTo(f.x + .1f, f.y) }
                                drawPath(path, SolidColor(mk.color), style = Stroke(strokeW, cap = StrokeCap.Round, join = StrokeJoin.Round))
                            }
                        }
                    }
                }
            }
            // tools
            Column(Modifier.fillMaxWidth().background(V.viewerTools).navigationBarsPadding().padding(start = 14.dp, end = 14.dp, top = 12.dp, bottom = 14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    ToolLabel("Comment")
                    SelectBox("Add a quick comment…", quickComments, { quick = it; vm.toast("Comment added") }, Modifier.weight(1f), dark = true, selected = quick)
                }
                DarkInput(custom, { custom = it }, "Custom comment…")
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ToolLabel("Draw")
                    pens.forEach { c ->
                        val on = c == pen && stamp == null
                        Box(
                            Modifier.size(40.dp).clip(RoundedCornerShape(9.dp)).background(c).border(if (on) 3.dp else 2.dp, if (on) Color.White else Color.White.copy(alpha = .25f), RoundedCornerShape(9.dp))
                                .clickable(role = Role.RadioButton, onClickLabel = "Pen color") { pen = c; stamp = null },
                        )
                    }
                    ToolBtn(onClick = { if (marks.isNotEmpty()) { marks.removeAt(marks.lastIndex) } }, label = "Undo") { Icon(VIcons.undo, "Undo", tint = Color.White, modifier = Modifier.size(17.dp)) }
                    ToolBtn(onClick = { marks.clear() }, label = "Clear") { Text("Clear", style = T.ui(13.sp, color = Color.White)) }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ToolLabel("Stamp")
                    listOf("★", "↑", "↓", "←", "→").forEach { s ->
                        ToolBtn(onClick = { stamp = if (stamp == s) null else s }, label = "Stamp $s", on = stamp == s) { Text(s, style = T.ui(16.sp, color = Color.White)) }
                    }
                }
                BtnRow(Modifier.padding(top = 0.dp)) {
                    VBtn("Save markup", { save { nav.back() } }, Modifier.weight(1f), BtnKind.Signal, VIcons.check)
                    VBtn("Save & return", {
                        save { if (!nav.popBackStack<SectionR>(inclusive = false)) nav.openSection(inspId, photo.section) }
                    }, Modifier.weight(1f), icon = VIcons.checkNext)
                }
            }
        }
        FindingSheet(
            visible = sheet, vm = vm, initialText = listOf(quick, custom).filter { it.isNotBlank() }.joinToString(" — "),
            onCancel = { sheet = false },
            onAdd = { cat, text -> vm.addFinding(inspId, cat, text, photo.section, photo.id); sheet = false },
        )
    }
}

/** Burns strokes + stamps into a copy of the photo (coordinates are normalized to the image). */
private fun flatten(src: ImageBitmap, marks: List<Mark>, strokePx: Float, stampPx: Float): Bitmap {
    val base = src.asAndroidBitmapCopy()
    val c = Canvas(base)
    marks.forEach { mk ->
        if (mk.stamp != null) {
            val p = mk.points.first()
            c.drawText(mk.stamp, p.x * base.width, p.y * base.height + stampPx * .35f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = mk.color.toArgb(); textSize = stampPx; textAlign = Paint.Align.CENTER; typeface = Typeface.DEFAULT_BOLD })
        } else if (mk.points.isNotEmpty()) {
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = mk.color.toArgb(); style = Paint.Style.STROKE; strokeWidth = strokePx; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
            val path = android.graphics.Path()
            mk.points.forEachIndexed { i, p -> if (i == 0) path.moveTo(p.x * base.width, p.y * base.height) else path.lineTo(p.x * base.width, p.y * base.height) }
            if (mk.points.size == 1) path.lineTo(mk.points[0].x * base.width + 0.5f, mk.points[0].y * base.height)
            c.drawPath(path, paint)
        }
    }
    return base
}

private fun ImageBitmap.asAndroidBitmapCopy(): Bitmap = this.asAndroidBitmap().copy(Bitmap.Config.ARGB_8888, true)

@Composable
private fun ToolLabel(t: String) { Text(t, style = T.mono(12.sp, color = Color(0xFF9AA8BA)), softWrap = false, maxLines = 1, modifier = Modifier.widthIn(min = 56.dp)) }

@Composable
private fun ToolBtn(onClick: () -> Unit, label: String, on: Boolean = false, content: @Composable () -> Unit) {
    Box(
        Modifier.heightIn(min = 40.dp).width(if (label == "Clear") 60.dp else 40.dp).height(40.dp).clip(RoundedCornerShape(9.dp))
            .background(if (on) V.brand else Color.White.copy(alpha = .1f)).clickable(role = Role.Button, onClickLabel = label, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { content() }
}

@Composable
private fun DarkInput(value: String, onChange: (String) -> Unit, placeholder: String) {
    BasicTextField(
        value, { onChange(com.vims.app.util.Filters.base(it, 200)) }, singleLine = true, textStyle = T.ui(13.sp, color = Color.White), cursorBrush = SolidColor(Color.White),
        modifier = Modifier.fillMaxWidth(),
        decorationBox = { inner ->
            Box(Modifier.fillMaxWidth().heightIn(min = 44.dp).clip(RoundedCornerShape(9.dp)).background(Color.White.copy(alpha = .1f)).border(1.dp, Color.White.copy(alpha = .18f), RoundedCornerShape(9.dp)).padding(horizontal = 11.dp, vertical = 10.dp), contentAlignment = Alignment.CenterStart) {
                if (value.isEmpty()) Text(placeholder, style = T.ui(13.sp, color = Color(0xFF9AA8BA)))
                inner()
            }
        },
    )
}

/* ================================================================ Flag a finding (bottom sheet) */

@Composable
fun FindingSheet(visible: Boolean, vm: AppViewModel, initialText: String, onCancel: () -> Unit, onAdd: (Int, String) -> Unit) {
    Box(Modifier.fillMaxSize()) {
        AnimatedVisibility(visible, enter = fadeIn(), exit = fadeOut()) {
            Box(Modifier.fillMaxSize().background(Color(0x990A0F16)).clickable(remember { MutableInteractionSource() }, null, onClick = onCancel))
        }
        AnimatedVisibility(visible, modifier = Modifier.align(Alignment.BottomCenter), enter = slideInVertically { it / 3 } + fadeIn(), exit = slideOutVertically { it / 3 } + fadeOut()) {
            var cat by rememberSaveable { mutableIntStateOf(2) }
            var text by rememberSaveable(initialText) { mutableStateOf(initialText) }
            var descErr by remember { mutableStateOf(false) }
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)).background(V.paper).imePadding().navigationBarsPadding()
                    .verticalScroll(rememberScrollState()).padding(start = 18.dp, end = 18.dp, top = 20.dp, bottom = 26.dp),
            ) {
                Text("Flag a finding", style = T.display(18.sp, FontWeight.Bold), modifier = Modifier.padding(bottom = 4.dp))
                Text("Pick a category and add a note. It's added to the summary and the report automatically.", style = T.ui(13.sp, color = V.ink3, lineHeight = 18.sp), modifier = Modifier.padding(bottom = 16.dp))
                Row(Modifier.padding(bottom = 14.dp), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
                    vm.config.findings.categories.forEach { c ->
                        val on = cat == c.id
                        Column(
                            Modifier.weight(1f).heightIn(min = 74.dp).clip(RoundedCornerShape(13.dp)).background(if (on) V.catBg(c.id) else V.paper)
                                .border(1.5.dp, if (on) V.cat(c.id) else V.line, RoundedCornerShape(13.dp)).clickable(role = Role.RadioButton) { cat = c.id }.padding(horizontal = 6.dp, vertical = 13.dp),
                            horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center,
                        ) {
                            Text("${c.id}", style = T.display(20.sp, FontWeight.ExtraBold, if (on) V.cat(c.id) else V.ink))
                            Spacer(Modifier.height(5.dp))
                            Text(c.label, style = T.ui(10.5.sp, color = V.ink3, lineHeight = 12.6.sp), textAlign = TextAlign.Center)
                        }
                    }
                }
                FieldLabel("Quick comment")
                SelectBox("Pick a quick comment…", vm.config.findings.quickComments, { text = it }, Modifier.padding(bottom = 13.dp))
                FieldLabel("Description")
                VInput(text, { text = it; descErr = false }, placeholder = "Describe the concern…", multiline = true, filter = { com.vims.app.util.Filters.base(it, 1000, multiline = true) },
                    error = if (descErr) "Describe the concern or pick a quick comment" else null)
                BtnRow(Modifier.padding(top = 4.dp)) {
                    VBtn("Cancel", onCancel, Modifier.weight(1f), BtnKind.Ghost)
                    VBtn("Add finding", { if (text.isBlank()) descErr = true else onAdd(cat, text) }, Modifier.weight(1f))
                }
            }
        }
    }
}
