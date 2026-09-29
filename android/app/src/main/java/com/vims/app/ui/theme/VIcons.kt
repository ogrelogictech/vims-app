package com.vims.app.ui.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.addPathNodes
import androidx.compose.ui.unit.dp

/**
 * The prototype's stroke icons (24×24, stroke 2, round caps/joins), built from the same SVG path data
 * so the native UI matches the approved screens exactly.
 */
object VIcons {
    private fun c(cx: Float, cy: Float, r: Float) = "M${cx - r},${cy}a$r,$r 0 1,0 ${2 * r},0a$r,$r 0 1,0 ${-2 * r},0"
    private fun r(x: Float, y: Float, w: Float, h: Float, rx: Float = 0f): String =
        if (rx == 0f) "M$x,${y}h${w}v${h}h${-w}z"
        else "M${x + rx},${y}h${w - 2 * rx}a$rx,$rx 0 0 1 $rx,$rx" + "v${h - 2 * rx}a$rx,$rx 0 0 1 ${-rx},$rx" +
            "h${-(w - 2 * rx)}a$rx,$rx 0 0 1 ${-rx},${-rx}" + "v${-(h - 2 * rx)}a$rx,$rx 0 0 1 $rx,${-rx}z"

    private fun icon(name: String, vararg paths: String, stroke: Float = 2f): ImageVector {
        val b = ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f)
        paths.forEach { d ->
            b.addPath(addPathNodes(d), fill = null, stroke = SolidColor(Color.Black), strokeLineWidth = stroke,
                strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round)
        }
        return b.build()
    }

    val back by lazy { icon("back", "M19 12H5M12 19l-7-7 7-7") }
    val menu by lazy { icon("menu", "M3 6h18M3 12h18M3 18h18") }
    val home by lazy { icon("home", "M3 10.5 12 3l9 7.5", "M5 9.5V20h14V9.5") }
    val plus by lazy { icon("plus", "M12 5v14M5 12h14") }
    val camera by lazy { icon("camera", "M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3z", c(12f, 13f, 3f)) }
    val list by lazy { icon("list", "M8 6h13M8 12h13M8 18h13M3 6h.01M3 12h.01M3 18h.01") }
    val info by lazy { icon("info", c(12f, 12f, 10f), "M12 16v-4M12 8h.01") }
    val tree by lazy { icon("tree", "M12 22v-7M9 9l3-6 3 6M7 14l5-8 5 8M5 19h14") }
    val sofa by lazy { icon("sofa", "M4 11V7a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v4", "M2 13a2 2 0 0 1 4 0v3h12v-3a2 2 0 0 1 4 0v5H2z") }
    val flask by lazy { icon("flask", "M9 3h6M10 3v6l-5 9a2 2 0 0 0 2 3h10a2 2 0 0 0 2-3l-5-9V3") }
    val layers by lazy { icon("layers", "M12 2 2 7l10 5 10-5z", "M2 17l10 5 10-5M2 12l10 5 10-5") }
    val box by lazy { icon("box", "M21 8 12 3 3 8v8l9 5 9-5z", "M3 8l9 5 9-5") }
    val bolt by lazy { icon("bolt", "M13 2 3 14h9l-1 8 10-12h-9z") }
    val wind by lazy { icon("wind", "M9.6 4.6A2 2 0 1 1 11 8H2M12.6 19.4A2 2 0 1 0 14 16H2M17.6 7.6A2 2 0 1 1 19 11H2") }
    val flame by lazy { icon("flame", "M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.07-2.14-.5-4 1-6 1 2 2 3 3 4s2 3 2 5a5 5 0 0 1-10 .5z") }
    val drop by lazy { icon("drop", "M12 2s6 7 6 11a6 6 0 0 1-12 0c0-4 6-11 6-11z") }
    val file by lazy { icon("file", "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z", "M14 2v6h6") }
    val fileLines by lazy { icon("fileLines", "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z", "M14 2v6h6M9 15h6M9 12h6") }
    val fileCheck by lazy { icon("fileCheck", "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z", "M14 2v6h6M9 15l2 2 4-4") }
    val fileAgreement by lazy { icon("fileAgreement", "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z", "M14 2v6h6M9 15h6M9 11h2") }
    val chevRight by lazy { icon("chevRight", "m9 18 6-6-6-6") }
    val caretRight by lazy { icon("caretRight", "m9 6 6 6-6 6") }
    val chevDown by lazy { icon("chevDown", "m6 9 6 6 6-6") }
    val chevUp by lazy { icon("chevUp", "m18 15-6-6-6 6") }
    val check by lazy { icon("check", "M20 6 9 17l-5-5") }
    val checkBold by lazy { icon("checkBold", "M20 6 9 17l-5-5", stroke = 2.4f) }
    val checkNext by lazy { icon("checkNext", "M20 6 9 17l-5-5M13 6l6 6-6 6") }
    val reviewSummary by lazy { icon("reviewSummary", "M9 11l3 3 8-8M20 12v7a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h9") }
    val eye by lazy { icon("eye", "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z", c(12f, 12f, 3f)) }
    val eyeOff by lazy { icon("eyeOff", "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z", c(12f, 12f, 3f), "M3 3l18 18") }
    val userPlus by lazy { icon("userPlus", "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2", c(9f, 7f, 4f), "M19 8v6M22 11h-6") }
    val users by lazy { icon("users", "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2", c(9f, 7f, 4f), "M22 21v-2a4 4 0 0 0-3-3.9") }
    val usersSmall by lazy { icon("usersSmall", "M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2", c(9f, 7f, 4f)) }
    val settings by lazy {
        icon("settings", c(12f, 12f, 3f),
            "M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.2.61.79 1 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z")
    }
    val download by lazy { icon("download", "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M7 10l5 5 5-5M12 15V3") }
    val upload by lazy { icon("upload", "M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4M17 8l-5-5-5 5M12 3v12") }
    val preview by lazy { icon("preview", "M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z", c(12f, 12f, 3f)) }
    val offline by lazy { icon("offline", "M21 12a9 9 0 0 1-9 9 9 9 0 0 1-6.7-3L3 16M3 12a9 9 0 0 1 9-9 9 9 0 0 1 6.7 3L21 8") }
    val sync by lazy { icon("sync", "M21 12a9 9 0 0 1-9 9 9 9 0 0 1-6.7-3L3 16M3 12a9 9 0 0 1 9-9 9 9 0 0 1 6.7 3L21 8M21 3v5h-5M3 21v-5h5") }
    val card by lazy { icon("card", r(2f, 5f, 20f, 14f, 2f), "M2 10h20") }
    val mail by lazy { icon("mail", r(2f, 4f, 20f, 16f, 2f), "m22 6-10 7L2 6") }
    val signOut by lazy { icon("signOut", "M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9") }
    val pencil by lazy { icon("pencil", "M12 20h9M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z") }
    val dollar by lazy { icon("dollar", "M12 1v22M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6") }
    val building by lazy { icon("building", "M3 21h18M5 21V7l7-4 7 4v14M9 9h.01M9 13h.01M9 17h.01M15 9h.01M15 13h.01M15 17h.01") }
    val help by lazy { icon("help", c(12f, 12f, 10f), "M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3M12 17h.01") }
    val close by lazy { icon("close", "M18 6 6 18M6 6l12 12") }
    val flag by lazy { icon("flag", "M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z", "M4 22v-7") }
    val undo by lazy { icon("undo", "M9 14 4 9l5-5", "M4 9h11a5 5 0 0 1 5 5v1a5 5 0 0 1-5 5H9") }
    val trash by lazy { icon("trash", "M3 6h18M8 6V4h8v2M6 6l1 14h10l1-14") }
    val copy by lazy { icon("copy", r(9f, 9f, 13f, 13f, 2f), "M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1") }
    val clock by lazy { icon("clock", "M12 8v4l3 2", c(12f, 12f, 9f)) }
    val clockFull by lazy { icon("clockFull", c(12f, 12f, 10f), "M12 6v6l4 2") }
    val calendar by lazy { icon("calendar", r(3f, 4f, 18f, 18f, 2f), "M16 2v4M8 2v4M3 10h18") }
    val lock by lazy { icon("lock", r(3f, 11f, 18f, 11f, 2f), "M7 11V7a5 5 0 0 1 10 0v4") }
    val arrowRight by lazy { icon("arrowRight", "M5 12h14M12 5l7 7-7 7") }
    val image by lazy { icon("image", r(3f, 3f, 18f, 18f, 2f), c(8.5f, 8.5f, 1.5f), "M21 15l-5-5L5 21") }
    val share by lazy { icon("share", c(18f, 5f, 3f), c(6f, 12f, 3f), c(18f, 19f, 3f), "M8.59 13.51l6.83 3.98M15.41 6.51l-6.82 3.98") }
    val grid by lazy { icon("grid", r(3f, 3f, 7f, 7f, 1f), r(14f, 3f, 7f, 7f, 1f), r(14f, 14f, 7f, 7f, 1f), r(3f, 14f, 7f, 7f, 1f)) }
    val switchCamera by lazy { icon("switchCamera", "M20 16v4a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-4M4 8V4a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v4M9 12H3M21 12h-6") }

    /** Icons named in vims-checklists.json (`icon` on groups/sections). */
    fun named(name: String?) = when (name) {
        "info" -> info; "tree" -> tree; "sofa" -> sofa; "flask" -> flask; "list" -> list; "layers" -> layers
        "box" -> box; "bolt" -> bolt; "wind" -> wind; "flame" -> flame; "drop", "water" -> drop; "file" -> file
        "home" -> home; "grid" -> grid; "camera" -> camera
        else -> info
    }
}
