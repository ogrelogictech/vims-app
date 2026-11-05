package com.vims.app.report

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.text.SpannableStringBuilder
import android.text.Spanned
import android.text.style.ReplacementSpan
import com.vims.app.data.AgreementBoxes

/**
 * A ☐ / ☒ / ☑ in a PDF's text, drawn as vector shapes (client Nov 4, `agreementPrefill.checkboxes._boxDrawing`). A font glyph here
 * came from whatever the device's fallback font has for these characters: on the client's Samsung tablet, small picture icons.
 * Empty = an outlined square. Ticked = a solid square with a white X (or check), obvious at a glance and in a black-and-white print.
 */
class VectorBoxSpan(private val mark: Char, private val outline: Int, private val tickFill: Int) : ReplacementSpan() {
    override fun getSize(paint: Paint, text: CharSequence?, start: Int, end: Int, fm: Paint.FontMetricsInt?): Int {
        fm?.let { paint.getFontMetricsInt(it) }
        return Math.ceil(paint.textSize * 1.2).toInt()
    }

    override fun draw(canvas: Canvas, text: CharSequence?, start: Int, end: Int, x: Float, top: Int, y: Int, bottom: Int, paint: Paint) {
        val size = paint.textSize
        val side = size * 1.02f
        val left = x + (size * 1.2f - side) / 2f
        val fm = paint.fontMetrics
        val t = y + (fm.ascent + fm.descent) / 2f - side / 2f
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        if (AgreementBoxes.isTicked(mark)) {
            p.color = tickFill; p.style = Paint.Style.FILL
            canvas.drawRect(left, t, left + side, t + side, p)
            p.color = android.graphics.Color.WHITE; p.style = Paint.Style.STROKE; p.strokeWidth = side * .17f; p.strokeCap = Paint.Cap.ROUND; p.strokeJoin = Paint.Join.ROUND
            val i = side * .24f
            if (mark == AgreementBoxes.CHECK) {
                canvas.drawPath(Path().apply { moveTo(left + i * .8f, t + side * .52f); lineTo(left + side * .42f, t + side - i); lineTo(left + side - i * .7f, t + i) }, p)
            } else {
                canvas.drawLine(left + i, t + i, left + side - i, t + side - i, p)
                canvas.drawLine(left + side - i, t + i, left + i, t + side - i, p)
            }
        } else {
            p.color = outline; p.style = Paint.Style.STROKE; p.strokeWidth = (size * .095f).coerceAtLeast(.7f)
            canvas.drawRect(left, t, left + side, t + side, p)
        }
    }
}

/**
 * [text] with every box character swapped for [VectorBoxSpan] over U+FFFC, so no ☐ / ☒ / ☑ is left for a text layout to find a
 * font for. Text without boxes comes back as it is.
 */
fun vectorBoxes(text: CharSequence, outline: Int, tickFill: Int): CharSequence {
    if (!AgreementBoxes.hasBoxes(text)) return text
    val glued = AgreementBoxes.glued(text.toString())
    val sb = SpannableStringBuilder(text)
    glued.forEachIndexed { i, c ->
        if (AgreementBoxes.isBox(c)) {
            sb.replace(i, i + 1, "￼")
            sb.setSpan(VectorBoxSpan(c, outline, tickFill), i, i + 1, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        } else if (c == AgreementBoxes.NBSP && text[i] != AgreementBoxes.NBSP) {
            sb.replace(i, i + 1, AgreementBoxes.NBSP.toString())
        }
    }
    return sb
}
