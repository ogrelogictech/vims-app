package com.vims.app.ui

import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.provider.Settings
import androidx.annotation.OptIn
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

/** Same gray as the video background and the system splash (no white flash). */
val SplashGray = Color(0xFFD4D4D9)
/** Fallback letterbox colors = the video's top / bottom edge colors (sampled at runtime when possible). */
private val EdgeTop = Color(0xFFD2D4DA)
private val EdgeBottom = Color(0xFFC3CAD1)

/** Averages the top and bottom pixel rows of a mid-video frame so the fit-inside letterbox blends seamlessly. */
private fun sampleEdges(ctx: android.content.Context): Pair<Color, Color>? = try {
    val r = MediaMetadataRetriever()
    ctx.assets.openFd(ASSET).use { fd -> r.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length) }
    val durUs = (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 5000L) * 1000
    val bmp = r.getFrameAtTime(durUs / 2, MediaMetadataRetriever.OPTION_CLOSEST_SYNC).also { r.release() } ?: throw IllegalStateException()
    fun avg(y0: Int, y1: Int): Color {
        var rr = 0L; var gg = 0L; var bb = 0L; var n = 0
        for (y in y0 until y1) for (x in 0 until bmp.width step 4) { val c = bmp.getPixel(x, y); rr += (c shr 16) and 255; gg += (c shr 8) and 255; bb += c and 255; n++ }
        return Color((rr / n).toInt(), (gg / n).toInt(), (bb / n).toInt())
    }
    (avg(0, 6) to avg(bmp.height - 6, bmp.height)).also { bmp.recycle() }
} catch (_: Exception) { null }
private const val ASSET = "media/vims-splash.mp4"

/**
 * Cold-launch splash (shared/media/vims-splash.mp4): full-screen, muted, fit-inside (whole frame visible, letterbox in the
 * video's edge colors), played once (~5 s), tap to skip.
 * With animations turned off (Animator duration scale 0) the last frame is shown for ~1 s instead.
 */
@OptIn(UnstableApi::class)
@Composable
fun SplashVideo(onDone: () -> Unit) {
    val ctx = LocalContext.current
    var finished by remember { mutableStateOf(false) }
    fun finish() { if (!finished) { finished = true; onDone() } }
    val reduceMotion = remember { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
    val tap = Modifier.fillMaxSize().semantics { contentDescription = "VIMS — tap to skip" }
        .clickable(remember { MutableInteractionSource() }, null) { finish() }

    if (reduceMotion) {
        var frame by remember { mutableStateOf<Bitmap?>(null) }
        LaunchedEffect(Unit) {
            frame = withContext(Dispatchers.IO) {
                try {
                    val r = MediaMetadataRetriever()
                    ctx.assets.openFd(ASSET).use { fd -> r.setDataSource(fd.fileDescriptor, fd.startOffset, fd.length) }
                    val durUs = (r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 5000L) * 1000
                    r.getFrameAtTime((durUs - 100_000).coerceAtLeast(0), MediaMetadataRetriever.OPTION_CLOSEST).also { r.release() }
                } catch (_: Exception) { null }
            }
            delay(1000); finish()
        }
        Box(tap.background(androidx.compose.ui.graphics.Brush.verticalGradient(0f to EdgeTop, 0.5f to EdgeTop, 0.5f to EdgeBottom, 1f to EdgeBottom))) {
            frame?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Fit) }
        }
        return
    }

    val player = remember {
        // Emulators only: their host "goldfish" H.264 decoder renders nothing under software GPU, so prefer the
        // platform software decoder there. Real devices keep the default (hardware) decoder order.
        val emulator = android.os.Build.HARDWARE.contains("ranchu") || android.os.Build.HARDWARE.contains("goldfish")
        val renderers = androidx.media3.exoplayer.DefaultRenderersFactory(ctx).setMediaCodecSelector { mime, secure, tunneling ->
            val list = androidx.media3.exoplayer.mediacodec.MediaCodecSelector.DEFAULT.getDecoderInfos(mime, secure, tunneling)
            if (emulator) list.sortedBy { if (it.name.contains("goldfish")) 1 else 0 } else list
        }
        ExoPlayer.Builder(ctx, renderers).build().apply {
            volume = 0f
            repeatMode = Player.REPEAT_MODE_OFF
            setMediaItem(MediaItem.fromUri("asset:///$ASSET"))
            prepare(); playWhenReady = true
        }
    }
    DisposableEffect(player) {
        val l = object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) { if (state == Player.STATE_ENDED) finish() }
            override fun onPlayerError(error: PlaybackException) { finish() }
        }
        player.addListener(l)
        onDispose { player.removeListener(l); player.release() }
    }
    // Safety net: never hold the user on the splash (video is ~5 s).
    LaunchedEffect(Unit) { delay(7000); finish() }
    // Fit-inside: the whole frame (incl. the tagline) is visible; letterbox bands use the video's own edge colors.
    var edges by remember { mutableStateOf(EdgeTop to EdgeBottom) }
    LaunchedEffect(Unit) { withContext(Dispatchers.IO) { sampleEdges(ctx) }?.let { edges = it } }
    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Brush.verticalGradient(0f to edges.first, 0.5f to edges.first, 0.5f to edges.second, 1f to edges.second))) {
        AndroidView(
            factory = { c ->
                (android.view.LayoutInflater.from(c).inflate(com.vims.app.R.layout.splash_player, null) as PlayerView).apply {
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_FIT
                    setBackgroundColor(android.graphics.Color.TRANSPARENT)
                    setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
                    this.player = player
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
        // Transparent layer on top so a tap anywhere skips (PlayerView would consume touches otherwise).
        Box(tap)
    }
}
