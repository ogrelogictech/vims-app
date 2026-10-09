package com.vims.app.report

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.ForegroundColorSpan
import android.text.style.MetricAffectingSpan
import com.vims.app.data.AgreementPiece
import java.io.File
import java.io.FileOutputStream

/**
 * "Download" on the inspection agreement viewer: prints the viewer's [AgreementPiece]s (title, boxed form lines, body,
 * the state disclosures shown, closing — viewer-only notes are skipped) into a clean paginated US Letter PDF with
 * android.graphics.pdf.PdfDocument, like [ReportPdfGenerator]. Long paragraphs split across pages line by line; every
 * page gets a "<company> · Inspection Agreement" / "Page x of n" footer.
 */
class AgreementPdf(context: Context) {
    private companion object {
        const val PW = 612f; const val PH = 792f; const val M = 54f // US Letter in points, 0.75 in margins
        const val CW = PW - 2 * M
        const val FOOT = 30f
        val BOTTOM = PH - M - FOOT
        val INK = Color.parseColor("#17222E"); val INK2 = Color.parseColor("#3F4E5E"); val INK3 = Color.parseColor("#5F6D7D")
        val LINE = Color.parseColor("#DDE5EE"); val BRAND_DEEP = Color.parseColor("#1E3D94"); val PAPER2 = Color.parseColor("#F4F7FA")
    }

    private val am = context.assets
    private fun variable(path: String, w: Int): Typeface = Typeface.Builder(am, path).setFontVariationSettings("'wght' $w").build() ?: Typeface.DEFAULT
    private val archivo800 = variable("fonts/Archivo-Variable.ttf", 800)
    private val archivo700 = variable("fonts/Archivo-Variable.ttf", 700)
    private val plex400 = variable("fonts/IBMPlexSans-Variable.ttf", 400)
    private val plex600 = variable("fonts/IBMPlexSans-Variable.ttf", 600)
    private val plex700 = variable("fonts/IBMPlexSans-Variable.ttf", 700)
    private val mono = try { Typeface.createFromAsset(am, "fonts/IBMPlexMono-Regular.ttf") } catch (_: Exception) { Typeface.MONOSPACE }

    private fun tp(tf: Typeface, size: Float, color: Int) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = tf; textSize = size; this.color = color }
    private val titleP = tp(archivo800, 20f, INK)
    private val headP = tp(archivo700, 12.5f, BRAND_DEEP)
    private val bodyP = tp(plex400, 10f, INK2)
    private val leadP = tp(plex600, 10f, INK)
    private val mutedP = tp(plex400, 10f, INK3)
    private val formP = tp(mono, 8.6f, INK2)
    private val footP = tp(plex400, 8f, INK3)

    private fun layout(text: CharSequence, paint: TextPaint, width: Float, spacing: Float = 1.3f): StaticLayout =
        StaticLayout.Builder.obtain(text, 0, text.length, paint, width.toInt().coerceAtLeast(10))
            .setAlignment(Layout.Alignment.ALIGN_NORMAL).setLineSpacing(0f, spacing).setIncludePad(false).build()

    /** Bold run inside a paragraph (the state name of a disclosure). */
    private class Bold(private val tf: Typeface) : MetricAffectingSpan() {
        override fun updateDrawState(p: TextPaint) { p.typeface = tf }
        override fun updateMeasureState(p: TextPaint) { p.typeface = tf }
    }

    // ------------------------------------------------------------------ page flow (dry run counts pages, 2nd pass draws)

    private var doc: PdfDocument? = null
    private var page: PdfDocument.Page? = null
    private var cv: Canvas? = null
    private var pageNo = 0
    private var total = 0
    private var y = M
    private var footerLeft = ""

    private fun newPage() {
        endPage()
        pageNo++
        doc?.let { d ->
            val p = d.startPage(PdfDocument.PageInfo.Builder(PW.toInt(), PH.toInt(), pageNo).create())
            page = p; cv = p.canvas.apply { drawColor(Color.WHITE) }
        }
        y = M
    }

    private fun endPage() {
        val p = page ?: return
        cv?.let { c ->
            c.drawLine(M, PH - M - 12f, PW - M, PH - M - 12f, Paint().apply { color = LINE; strokeWidth = 0.6f })
            val fy = PH - M + 2f
            c.drawText(footerLeft, M, fy, footP)
            val right = "Page $pageNo of $total"
            c.drawText(right, PW - M - footP.measureText(right), fy, footP)
        }
        doc?.finishPage(p)
        page = null; cv = null
    }

    /** Draws [l] at x, splitting it across pages between lines when it doesn't fit; `gapAfter` is added below it. */
    private fun flow(l: StaticLayout, x: Float, gapAfter: Float, keepLines: Int = 2, bullet: String? = null) {
        var line = 0
        // Don't strand the first line(s) at the bottom of a page.
        val firstChunk = l.getLineBottom((minOf(keepLines, l.lineCount) - 1).coerceAtLeast(0)).toFloat()
        if (y + firstChunk > BOTTOM && y > M) newPage()
        while (line < l.lineCount) {
            val top = l.getLineTop(line)
            var last = line
            while (last + 1 < l.lineCount && y + (l.getLineBottom(last + 1) - top) <= BOTTOM) last++
            val h = (l.getLineBottom(last) - top).toFloat()
            cv?.let { c ->
                if (bullet != null && line == 0) c.drawText(bullet, x - 11f, y + l.getLineBaseline(0), bodyP)
                c.save(); c.clipRect(x, y, x + l.width + 2f, y + h); c.translate(x, y - top); l.draw(c); c.restore()
            }
            y += h
            line = last + 1
            if (line < l.lineCount) newPage()
        }
        y += gapAfter
    }

    private fun form(lines: List<String>) {
        val pad = 10f
        val l = layout(lines.joinToString("\n"), formP, CW - 2 * pad, 1.45f)
        if (y + l.height + 2 * pad <= BOTTOM || y <= M) {
            cv?.let { c ->
                val r = RectF(M, y, M + CW, y + l.height + 2 * pad)
                c.drawRoundRect(r, 7f, 7f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = PAPER2 })
                c.drawRoundRect(r, 7f, 7f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = LINE; style = Paint.Style.STROKE; strokeWidth = 0.8f })
            }
            y += pad; flow(l, M + pad, pad + 12f)
        } else {
            // Taller than what's left on the page: print the lines unboxed so they can flow across pages.
            flow(l, M, 12f)
        }
    }

    private fun render(pieces: List<AgreementPiece>) {
        pageNo = 0
        newPage()
        pieces.forEach { p ->
            when (p) {
                is AgreementPiece.Title -> flow(layout(p.text, titleP, CW, 1.15f), M, 12f)
                is AgreementPiece.Form -> form(p.lines)
                is AgreementPiece.Para -> flow(layout(p.text, if (p.lead) leadP else if (p.muted) mutedP else bodyP, CW), M, 7f)
                is AgreementPiece.Bullet -> flow(layout(p.text, bodyP, CW - 14f), M + 14f, 7f, bullet = "•")
                is AgreementPiece.Heading -> {
                    // Keep a heading with at least a few lines of what follows it.
                    val l = layout(p.text, headP, CW, 1.2f)
                    y += 6f
                    if (y + l.height + 40f > BOTTOM) newPage()
                    flow(l, M, 7f)
                }
                is AgreementPiece.Disclosure -> {
                    val sb = SpannableStringBuilder("${p.state}: ").apply {
                        setSpan(Bold(plex700), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        setSpan(ForegroundColorSpan(INK), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                        append(p.text)
                    }
                    flow(layout(sb, bodyP, CW), M, 7f)
                }
                is AgreementPiece.Note -> Unit // viewer-only
            }
        }
        endPage()
    }

    /** Writes the PDF to [out] and returns its page count. */
    fun write(pieces: List<AgreementPiece>, companyName: String, out: File): Int {
        footerLeft = listOf(companyName.ifBlank { null }, "Inspection Agreement").filterNotNull().joinToString(" · ")
        // Pass 1: count pages (nothing drawn). Pass 2: draw with "Page x of n".
        doc = null; total = 0; render(pieces); total = pageNo
        val d = PdfDocument(); doc = d
        try {
            render(pieces)
            out.parentFile?.mkdirs()
            FileOutputStream(out).use { d.writeTo(it) }
        } finally { d.close(); doc = null }
        return total
    }
}
