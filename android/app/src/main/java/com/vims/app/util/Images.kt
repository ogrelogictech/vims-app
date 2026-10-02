package com.vims.app.util

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.LruCache
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.produceState
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

object Images {
    private val cache = object : LruCache<String, Bitmap>(24 * 1024 * 1024) {
        override fun sizeOf(key: String, value: Bitmap) = value.byteCount
    }

    /** Decodes a file downsampled so its longer side is ≈ `max` px. */
    fun decode(file: File, max: Int): Bitmap? {
        if (!file.exists()) return null
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, o)
        if (o.outWidth <= 0) return null
        var s = 1
        while (maxOf(o.outWidth, o.outHeight) / (s * 2) >= max) s *= 2
        return BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = s })
    }

    fun thumb(file: File, max: Int = 360): Bitmap? {
        val key = "${file.path}@${file.lastModified()}@$max"
        cache.get(key)?.let { return it }
        return decode(file, max)?.also { cache.put(key, it) }
    }

    /** Applies EXIF rotation and caps the size at 2048px (CameraX writes rotation as EXIF only). */
    fun normalizeJpeg(file: File, max: Int = 2048) {
        val rotation = try {
            when (ExifInterface(file.path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
        } catch (_: Exception) { 0f }
        val src = decode(file, max) ?: return
        val scale = minOf(1f, max.toFloat() / maxOf(src.width, src.height))
        if (rotation == 0f && scale >= 1f) { src.recycle(); return }
        val m = Matrix().apply { if (scale < 1f) postScale(scale, scale); if (rotation != 0f) postRotate(rotation) }
        val out = Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)
        FileOutputStream(file).use { out.compress(Bitmap.CompressFormat.JPEG, 88, it) }
        if (out !== src) src.recycle()
        out.recycle()
    }
}

/** Square center-crop, scaled to `size`px, saved as JPEG (profile photos). Honors EXIF rotation. */
fun saveSquareAvatar(cr: android.content.ContentResolver, uri: android.net.Uri, out: File, size: Int = 512): Boolean = try {
    val raw = cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) } ?: throw IllegalStateException("decode")
    val rot = try { cr.openInputStream(uri)?.use { ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, 1) } ?: 1 } catch (_: Exception) { 1 }
    val deg = when (rot) { ExifInterface.ORIENTATION_ROTATE_90 -> 90f; ExifInterface.ORIENTATION_ROTATE_180 -> 180f; ExifInterface.ORIENTATION_ROTATE_270 -> 270f; else -> 0f }
    val side = minOf(raw.width, raw.height)
    val m = Matrix().apply { val s = size.toFloat() / side; postScale(s, s); if (deg != 0f) postRotate(deg) }
    val sq = Bitmap.createBitmap(raw, (raw.width - side) / 2, (raw.height - side) / 2, side, side, m, true)
    out.parentFile?.mkdirs()
    FileOutputStream(out).use { sq.compress(Bitmap.CompressFormat.JPEG, 90, it) }
    true
} catch (_: Exception) { false }

@Composable
fun rememberThumb(file: File, version: Int = 0, max: Int = 360): State<ImageBitmap?> =
    produceState<ImageBitmap?>(null, file.path, version, max) {
        value = withContext(Dispatchers.IO) { Images.thumb(file, max)?.asImageBitmap() }
    }

/** Whether [file] exists, checked off the main thread (starts as [initial] until the check finishes). */
@Composable
fun rememberFileExists(file: File?, version: Int = 0, initial: Boolean = file != null): State<Boolean> =
    produceState(initial, file?.path, version) {
        value = file != null && withContext(Dispatchers.IO) { file.exists() }
    }
