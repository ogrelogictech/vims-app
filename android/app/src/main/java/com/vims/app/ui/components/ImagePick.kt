package com.vims.app.ui.components

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import java.io.File

/**
 * "Take photo / Choose from gallery / Remove" for the profile photo and the company logo.
 * Camera = ACTION_IMAGE_CAPTURE into a cache file (CAMERA permission requested first); gallery = Photo Picker.
 * Call `open()` to show the chooser.
 */
class ImageChooser internal constructor(private val show: () -> Unit) { fun open() = show() }

@Composable
fun rememberImageChooser(title: String, canRemove: Boolean, onImage: (Uri) -> Unit, onRemove: () -> Unit): ImageChooser {
    val ctx = LocalContext.current
    var visible by rememberSaveable { mutableStateOf(false) }
    var pendingCapture by rememberSaveable { mutableStateOf<String?>(null) }
    val capture = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { ok ->
        val f = pendingCapture?.let { File(it) }
        if (ok && f != null && f.length() > 0) onImage(Uri.fromFile(f))
    }
    fun launchCamera() {
        val f = File(ctx.cacheDir, "capture/cap-${System.currentTimeMillis()}.jpg").apply { parentFile?.mkdirs() }
        pendingCapture = f.path
        capture.launch(FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", f))
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted -> if (granted) launchCamera() }
    val gallery = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri -> if (uri != null) onImage(uri) }
    if (visible) {
        Dialog(onDismissRequest = { visible = false }) {
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(V.paper).padding(vertical = 14.dp)) {
                Text(title, style = T.display(17.sp, FontWeight.Bold), modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 8.dp))
                ChooserRow(VIcons.camera, "Take photo") {
                    visible = false
                    if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) launchCamera()
                    else permission.launch(Manifest.permission.CAMERA)
                }
                ChooserRow(VIcons.image, "Choose from gallery") { visible = false; gallery.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }
                if (canRemove) ChooserRow(VIcons.trash, "Remove", V.c1) { visible = false; onRemove() }
                ChooserRow(null, "Cancel", V.ink3) { visible = false }
            }
        }
    }
    return remember { ImageChooser { visible = true } }
}

/** One row of a chooser dialog (icon + label, 52dp tall). */
@Composable
fun ChooserRow(icon: ImageVector?, label: String, color: Color = V.ink, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(role = Role.Button, onClick = onClick).padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(Modifier.size(22.dp), contentAlignment = Alignment.Center) { if (icon != null) Icon(icon, null, tint = color, modifier = Modifier.size(20.dp)) }
        Text(label, style = T.ui(15.sp, FontWeight.Medium, color))
    }
}
