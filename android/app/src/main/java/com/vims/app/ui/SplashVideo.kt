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
private const val ASSET = "media/vims-splash.mp4"

/**
 * Cold-launch splash (shared/media/vims-splash.mp4): full-screen, muted, center-crop, played once (~5 s), tap to skip.
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
        Box(tap.background(SplashGray)) { frame?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) } }
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
    Box(Modifier.fillMaxSize().background(SplashGray)) {
        AndroidView(
            factory = { c ->
                (android.view.LayoutInflater.from(c).inflate(com.vims.app.R.layout.splash_player, null) as PlayerView).apply {
                    resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                    this.player = player
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
        // Transparent layer on top so a tap anywhere skips (PlayerView would consume touches otherwise).
        Box(tap)
    }
}
