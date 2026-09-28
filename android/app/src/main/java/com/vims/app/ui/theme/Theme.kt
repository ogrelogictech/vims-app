package com.vims.app.ui.theme

import android.content.res.AssetManager
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.sp

/** Design tokens from docs/design-tokens.md (prototype `:root`). */
object V {
    val brand = Color(0xFF2F5EC9)
    val brandBright = Color(0xFF5580E6)
    val brandDeep = Color(0xFF1E3D94)
    val hdr = Color(0xFF2F5EC9)
    val hdrSub = Color(0xFFD7E3F7)
    val ink = Color(0xFF17222E)
    val ink2 = Color(0xFF3F4E5E)
    val ink3 = Color(0xFF5F6D7D)
    val line = Color(0xFFDDE5EE)
    val line2 = Color(0xFFEEF2F7)
    val paper = Color(0xFFFFFFFF)
    val paper2 = Color(0xFFF4F7FA)
    val paper3 = Color(0xFFE9EEF4)
    val signal = Color(0xFFE4A11B)
    val signalDeep = Color(0xFFA5730A)
    val c1 = Color(0xFFD0584A)
    val c1Bg = Color(0xFFFBE9E6)
    val c2 = Color(0xFFC98A1A)
    val c2Bg = Color(0xFFFBF1DD)
    val c3 = Color(0xFF2F9E6B)
    val c3Bg = Color(0xFFE7F4EE)
    val pass = Color(0xFF2F9E6B)
    val fail = Color(0xFFD0584A)
    val doneText = Color(0xFF1F7A52)
    val placeholder = Color(0xFFA7B4C2)
    val chev = Color(0xFFB7C3D0)
    val signalInk = Color(0xFF3A2A05)
    val bannerBorder = Color(0xFFF0DCAE)
    val bannerText = Color(0xFF7A5A10)
    val bannerBold = Color(0xFF5E440A)
    val viewerBg = Color(0xFF0B0F15)
    val viewerTools = Color(0xFF12181F)
    val scrim = Color(0x800A0F16)

    fun cat(n: Int) = when (n) { 1 -> c1; 2 -> c2; else -> c3 }
    fun catBg(n: Int) = when (n) { 1 -> c1Bg; 2 -> c2Bg; else -> c3Bg }
}

/** Archivo (headings), IBM Plex Sans (UI), IBM Plex Mono (times, codes, labels, prices) — packaged from shared/fonts. */
object VimsFonts {
    lateinit var display: FontFamily private set
    lateinit var ui: FontFamily private set
    lateinit var mono: FontFamily private set

    fun init(assets: AssetManager) {
        fun variable(path: String, vararg weights: Int) = FontFamily(weights.map { w ->
            Font(path = path, assetManager = assets, weight = FontWeight(w), variationSettings = FontVariation.Settings(FontVariation.weight(w)))
        })
        display = variable("fonts/Archivo-Variable.ttf", 600, 700, 800)
        ui = variable("fonts/IBMPlexSans-Variable.ttf", 400, 500, 600, 700)
        mono = FontFamily(
            Font("fonts/IBMPlexMono-Regular.ttf", assets, FontWeight.Normal),
            Font("fonts/IBMPlexMono-Medium.ttf", assets, FontWeight.Medium),
            Font("fonts/IBMPlexMono-SemiBold.ttf", assets, FontWeight.SemiBold),
            Font("fonts/IBMPlexMono-SemiBold.ttf", assets, FontWeight.Bold),
            Font("fonts/IBMPlexMono-SemiBold.ttf", assets, FontWeight.ExtraBold),
        )
    }
}

object T {
    fun ui(size: TextUnit, weight: FontWeight = FontWeight.Normal, color: Color = V.ink, lineHeight: TextUnit = TextUnit.Unspecified) =
        TextStyle(fontFamily = VimsFonts.ui, fontSize = size, fontWeight = weight, color = color, lineHeight = lineHeight)
    fun display(size: TextUnit, weight: FontWeight = FontWeight.Bold, color: Color = V.ink, lineHeight: TextUnit = TextUnit.Unspecified) =
        TextStyle(fontFamily = VimsFonts.display, fontSize = size, fontWeight = weight, color = color, lineHeight = lineHeight)
    fun mono(size: TextUnit, weight: FontWeight = FontWeight.Normal, color: Color = V.ink, letterSpacing: TextUnit = TextUnit.Unspecified) =
        TextStyle(fontFamily = VimsFonts.mono, fontSize = size, fontWeight = weight, color = color, letterSpacing = letterSpacing)
}

@Composable
fun VimsTheme(content: @Composable () -> Unit) {
    // Light only — the approved prototype has no dark theme; OS dark mode must not restyle it.
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = V.brand, onPrimary = Color.White, secondary = V.brandDeep, background = V.paper2, surface = V.paper,
            onSurface = V.ink, onBackground = V.ink, outline = V.line, error = V.c1,
        ),
        typography = MaterialTheme.typography.copy(
            bodyLarge = T.ui(15.sp), bodyMedium = T.ui(14.sp), bodySmall = T.ui(12.sp),
            labelLarge = T.ui(15.sp, FontWeight.SemiBold), titleMedium = T.display(17.sp),
        ),
        content = content,
    )
}
