package com.vims.app.report

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import com.vims.app.data.AirQualityDef
import com.vims.app.data.ChecklistConfig
import com.vims.app.data.ChecklistEngine
import com.vims.app.data.sectionTitle
import com.vims.app.data.CoverFooterBoxDef
import com.vims.app.data.CompanyProfile
import com.vims.app.data.CoverLayoutDef
import com.vims.app.data.InspectionBundle
import com.vims.app.data.ItemDef
import com.vims.app.data.Photo
import com.vims.app.data.SecStatus
import com.vims.app.data.SectionAnswers
import com.vims.app.data.VimsRepository
import com.vims.app.data.baseName
import com.vims.app.util.Fmt
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

data class ReportOutput(val file: File, val pages: Int)

/**
 * Builds the inspection report PDF on-device with android.graphics.pdf.PdfDocument, following report.html:
 * cover → property information → beginning notes → per-section data pages (+ photo pages) → categorized summary.
 * Layout is authored in report.html's CSS pixel space (850 × 1100 per US Letter page) and scaled to points.
 * (The invoice page in report.html belongs to the client-payment add-on and is not part of Phase 1.)
 */
class ReportPdfGenerator(private val context: Context, private val config: ChecklistConfig, private val repo: VimsRepository) {

    private companion object {
        const val PW = 850f; const val PH = 1100f; const val SCALE = 612f / 850f
        const val PADX = 48f; const val PADY = 46f
        const val CW = PW - PADX * 2
        const val FOOT_H = 44f
        val BOTTOM = PH - PADY - FOOT_H

        val INK = Color.parseColor("#17222E"); val INK2 = Color.parseColor("#3F4E5E"); val INK3 = Color.parseColor("#5F6D7D")
        val LINE = Color.parseColor("#DDE5EE"); val LINE2 = Color.parseColor("#EEF2F7")
        val BRAND = Color.parseColor("#2F5EC9"); val BRAND_DEEP = Color.parseColor("#1E3D94"); val PAPER2 = Color.parseColor("#F4F7FA")
        val C = intArrayOf(0, Color.parseColor("#D0584A"), Color.parseColor("#C98A1A"), Color.parseColor("#2F9E6B"))
        val CBG = intArrayOf(0, Color.parseColor("#FBE9E6"), Color.parseColor("#FBF1DD"), Color.parseColor("#E7F4EE"))
    }

    private val am = context.assets
    private fun variable(path: String, w: Int): Typeface =
        Typeface.Builder(am, path).setFontVariationSettings("'wght' $w").build() ?: Typeface.DEFAULT
    private val archivo700 = variable("fonts/Archivo-Variable.ttf", 700)
    private val archivo800 = variable("fonts/Archivo-Variable.ttf", 800)
    private val plex400 = variable("fonts/IBMPlexSans-Variable.ttf", 400)
    private val plex600 = variable("fonts/IBMPlexSans-Variable.ttf", 600)
    private val plex700 = variable("fonts/IBMPlexSans-Variable.ttf", 700)
    private val mono: Typeface = try { Typeface.createFromAsset(am, "fonts/IBMPlexMono-Medium.ttf") } catch (_: Exception) { Typeface.MONOSPACE }

    private fun tp(tf: Typeface, size: Float, color: Int = INK) = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { typeface = tf; textSize = size; this.color = color }
    private fun fill(color: Int) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.FILL }
    private fun stroke(color: Int, w: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color; style = Paint.Style.STROKE; strokeWidth = w }

    private fun layout(text: CharSequence, paint: TextPaint, width: Float, align: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL, spacing: Float = 1f): StaticLayout =
        StaticLayout.Builder.obtain(text, 0, text.length, paint, width.toInt().coerceAtLeast(10)).setAlignment(align).setLineSpacing(0f, spacing).setIncludePad(false).build()

    private fun Canvas.drawLayout(l: StaticLayout, x: Float, y: Float) { save(); translate(x, y); l.draw(this); restore() }

    // ------------------------------------------------------------------ page flow

    private lateinit var doc: PdfDocument
    private var page: PdfDocument.Page? = null
    private lateinit var cv: Canvas
    private var pageNo = 0
    private var y = 0f
    private lateinit var b: InspectionBundle
    private lateinit var company: CompanyProfile
    private var logo: Bitmap? = null

    /** Page header used by `startPage()` / page breaks (running brand header by default; TREC header on Texas checklist pages). */
    private var pageHeader: () -> Unit = { runningHeader() }

    private fun startPage(header: Boolean = true) {
        finishPage()
        pageNo++
        val info = PdfDocument.PageInfo.Builder(612, 792, pageNo).create()
        page = doc.startPage(info)
        cv = page!!.canvas
        cv.scale(SCALE, SCALE)
        cv.drawRect(0f, 0f, PW, PH, fill(Color.WHITE))
        y = PADY
        if (header) pageHeader()
    }

    private fun finishPage() {
        page?.let { val f = pageFooter; if (f != null) f() else if (pageNo > 1) footer(); doc.finishPage(it) }
        page = null
    }

    private fun ensure(h: Float, onBreak: () -> Unit = {}) {
        if (y + h > BOTTOM) { startPage(); onBreak() }
    }

    private fun brandLines(): Pair<String, String> {
        val words = company.name.ifBlank { "VIMS" }.split(" ").filter { it.isNotBlank() }
        return if (words.size >= 2) words.dropLast(1).joinToString(" ") to words.last() else (words.firstOrNull() ?: "VIMS") to ""
    }

    private fun addrLines(): List<String> {
        val parts = company.address.split(",").map { it.trim() }.filter { it.isNotEmpty() }
        val lines = if (parts.size >= 3) listOf(parts.dropLast(2).joinToString(", "), parts.takeLast(2).joinToString(", ")) else listOf(company.address).filter { it.isNotBlank() }
        return lines + listOfNotNull(company.email.takeIf { it.isNotBlank() }, company.phone.takeIf { it.isNotBlank() })
    }

    private fun drawLogo(x: Float, top: Float, size: Float) {
        val l = logo ?: run {
            val r = RectF(x, top, x + size, top + size)
            cv.drawRoundRect(r, size * .22f, size * .22f, Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = LinearGradient(r.left, r.top, r.right, r.bottom, Color.parseColor("#5580E6"), BRAND_DEEP, Shader.TileMode.CLAMP) })
            val initials = company.name.split(" ").filter { it.isNotBlank() && it.first().isLetterOrDigit() }.take(2).joinToString("") { it.first().uppercase() }.ifEmpty { "V" }
            cv.drawText(initials, r.centerX(), r.centerY() + size * .13f, tp(archivo700, size * .36f, Color.WHITE).apply { textAlign = Paint.Align.CENTER })
            return
        }
        val s = minOf(size / l.width, size / l.height)
        val w = l.width * s; val h = l.height * s
        cv.drawBitmap(l, null, RectF(x + (size - w) / 2, top + (size - h) / 2, x + (size + w) / 2, top + (size + h) / 2), Paint(Paint.FILTER_BITMAP_FLAG))
    }

    private fun brandBlock(x: Float, top: Float, logoSize: Float, nameSize: Float, subSize: Float, subColor: Int, subTf: Typeface) {
        drawLogo(x, top, logoSize)
        val (l1, l2) = brandLines()
        val p1 = tp(archivo800, nameSize, BRAND_DEEP); val p2 = tp(subTf, subSize, subColor)
        val tx = x + logoSize + if (logoSize > 50) 13f else 11f
        val total = nameSize + (if (l2.isNotEmpty()) subSize + 4 else 0f)
        var ty = top + (logoSize - total) / 2 + nameSize * .85f
        cv.drawText(l1, tx, ty, p1)
        if (l2.isNotEmpty()) { ty += subSize + 5; cv.drawText(l2, tx, ty, p2) }
    }

    private fun addrBlock(right: Float, top: Float, nameSize: Float, lineSize: Float, lh: Float) {
        val pn = tp(plex700, nameSize, INK).apply { textAlign = Paint.Align.RIGHT }
        val pl = tp(plex400, lineSize, INK2).apply { textAlign = Paint.Align.RIGHT }
        var ty = top + nameSize
        cv.drawText(company.name, right, ty, pn)
        addrLines().forEach { ty += lh; cv.drawText(it, right, ty, pl) }
    }

    private fun runningHeader() {
        brandBlock(PADX, y, 44f, 16f, 11f, INK3, plex400)
        addrBlock(PW - PADX, y, 11.5f, 10.5f, 15.75f)
        val bottom = y + maxOf(44f, 11.5f + addrLines().size * 15.75f + 4f) + 12f
        cv.drawRect(PADX, bottom, PW - PADX, bottom + 2f, fill(BRAND))
        y = bottom + 2f + 22f
    }

    private fun footer() {
        when (layoutKind) {
            ChecklistConfig.LAYOUT_TEXAS -> { texasFooter(); return }
            ChecklistConfig.LAYOUT_FOUR_POINT -> { fourPointFooter(); return }
        }
        val top = PH - PADY - 30f
        cv.drawRect(PADX, top - 14f, PW - PADX, top - 13f, fill(LINE))
        val sel = b.inspection.selections
        cv.drawText(sel.clientName.ifBlank { "Client" }, PADX, top + 2f, tp(plex700, 10f, INK))
        cv.drawText("${sel.street} · ${Fmt.slash(sel.date)}", PADX, top + 16f, tp(plex400, 10f, INK3))
        cv.drawText("Page $pageNo", PW - PADX, top + 2f, tp(plex400, 10f, INK3).apply { textAlign = Paint.Align.RIGHT })
    }

    private fun title(t: String, sub: String) {
        val tl = layout(t, tp(archivo800, 20f), CW)
        cv.drawLayout(tl, PADX, y); y += tl.height + 3f
        val sl = layout(sub, tp(plex400, 12.5f, INK3), CW)
        cv.drawLayout(sl, PADX, y); y += sl.height + 20f
    }

    private fun blockLabel(t: String) {
        ensure(96f) // keep the label with at least the first line of its content
        y += 20f
        cv.drawText(t.uppercase(), PADX, y + 13f, tp(archivo700, 13f, BRAND_DEEP).apply { letterSpacing = .04f })
        y += 13f + 8f + 4f
    }

    private fun note(t: String) {
        val l = layout(t, tp(plex400, 12.5f, INK2), CW - 26f, spacing = 1.2f)
        val h = l.height + 22f
        ensure(h)
        val r = RectF(PADX, y, PADX + CW, y + h)
        cv.drawRoundRect(r, 8f, 8f, fill(PAPER2)); cv.drawRoundRect(r, 8f, 8f, stroke(LINE, 1f))
        cv.drawLayout(l, PADX + 13f, y + 11f)
        y += h
    }

    /** Two-column key/value grid (`.info-grid` + `.frow2`). */
    /** [compact] = tighter rows and 12pt text (the one-page WDI report). */
    private fun infoGrid(rows: List<Pair<String, String>>, compact: Boolean = false) {
        val fs = if (compact) 12f else 13f; val pad = if (compact) 8f else 16f; val gap = if (compact) 2f else 9f
        val colW = (CW - 26f) / 2
        rows.chunked(2).forEach { pair ->
            val layouts = pair.map { (k, v) ->
                val kl = layout(k, tp(plex400, fs, INK3), colW * .5f)
                val vl = layout(v.ifBlank { "—" }, tp(plex600, fs, INK), colW * .5f - 14f, Layout.Alignment.ALIGN_OPPOSITE)
                kl to vl
            }
            val h = layouts.maxOf { maxOf(it.first.height, it.second.height) } + pad
            ensure(h + gap)
            layouts.forEachIndexed { i, (kl, vl) ->
                val x = PADX + i * (colW + 26f)
                cv.drawLayout(kl, x, y + pad / 2)
                cv.drawLayout(vl, x + colW - vl.width, y + pad / 2)
                cv.drawRect(x, y + h - 1f, x + colW, y + h, fill(LINE2))
            }
            y += h + gap
        }
    }

    private fun secTitle(num: Int, name: String) {
        ensure(60f)
        val h = 44f
        val r = RectF(PADX, y, PADX + CW, y + h)
        cv.drawRoundRect(r, 9f, 9f, fill(BRAND))
        val numText = if (num >= 99) "—" else String.format(Locale.US, "%02d", num)
        val np = tp(archivo800, 15f, Color.WHITE)
        val nw = np.measureText(numText) + 18f
        cv.drawRoundRect(RectF(PADX + 15f, y + 10f, PADX + 15f + nw, y + h - 10f), 7f, 7f, fill(Color.argb(51, 255, 255, 255)))
        cv.drawText(numText, PADX + 15f + 9f, y + h / 2 + 5.5f, np)
        cv.drawText(name, PADX + 15f + nw + 10f, y + h / 2 + 6f, tp(archivo700, 16f, Color.WHITE))
        y += h + 14f
    }

    // ------------------------------------------------------------------ build

    private var layoutKind = ChecklistConfig.LAYOUT_STANDARD
    /** Total page count for "Page X of Y" footers (Texas / 4-Point) — known after a first layout pass. */
    private var totalPages = 0

    fun generate(bundle: InspectionBundle, company: CompanyProfile): ReportOutput {
        b = bundle; this.company = company
        layoutKind = config.reportLayout(bundle.inspection.selections.inspType)
        // Company logo from Company profile; without one, an initials badge is drawn (same fallback as in the app).
        logo = company.logoFile?.let { BitmapFactory.decodeFile(File(context.filesDir, it).path) }
        // Texas / 4-Point "Page X of Y", and form sections' "Page X of N" (Wind Mitigation), are known after a first pass.
        if (layoutKind != ChecklistConfig.LAYOUT_STANDARD || hasFormSections()) { render(); totalPages = pageNo; doc.close() }
        render()

        val dir = File(repo.inspectionDir(bundle.id), "report").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val safe = bundle.inspection.selections.street.ifBlank { "Inspection" }.replace(Regex("[^A-Za-z0-9]+"), "-").trim('-')
        val out = File(dir, "VIMS-Report-$safe.pdf")
        FileOutputStream(out).use { doc.writeTo(it) }
        doc.close()
        return ReportOutput(out, pageNo)
    }

    /** Page order per `reportLayouts` in vims-checklists.json. */
    private fun render() {
        doc = PdfDocument(); pageNo = 0; page = null; pageHeader = { runningHeader() }
        cover()
        when (layoutKind) {
            ChecklistConfig.LAYOUT_TEXAS -> {
                trecInfoPage()
                formSections().forEach { trecChecklist(it) }
                picturePages()
                pageHeader = { runningHeader() }
                summary()
            }
            ChecklistConfig.LAYOUT_FOUR_POINT -> {
                fourPointForm()
                picturePages()
            }
            else -> {
                propertyInfo()
                beginningNotes()
                val sections = b.inspection.leafSections.filter { b.status(it) == SecStatus.DONE }
                    .sortedWith(compareBy<String>({ ChecklistEngine.number(b.defs, it) }, { it }))
                // Data v1.9 formReports: Wind Mitigation prints as the OIR-B1-1802 form, Termite as the WDI report; photos follow.
                sections.forEach { s ->
                    when (b.defs[baseName(s)]?.formReport) { "oir-b1-1802" -> oirForm(s); "wdi" -> wdiReport(s); else -> sectionPages(s) }
                    photoPages(s)
                }
                summary()
            }
        }
        finishPage()
    }

    // ------------------------------------------------------------------ cover (client's design, data v1.6 covers.layout)

    /** Inches on the US Letter page → canvas units (the canvas is 850 × 1100 = 100 units per inch). */
    private fun inch(v: Float) = v * 100f
    /** Points → canvas units. */
    private fun pt(v: Float) = v * 100f / 72f
    private fun List<Float>.inches(fallback: List<Float>): RectF {
        val r = if (size >= 4) this else fallback
        return RectF(inch(r[0]), inch(r[1]), inch(r[0] + r[2]), inch(r[1] + r[3]))
    }
    private val serif: Typeface = Typeface.create(Typeface.SERIF, Typeface.NORMAL)
    private val serifBold: Typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
    private fun ellipsize(t: String, p: TextPaint, w: Float): String = TextUtils.ellipsize(t, p, w.coerceAtLeast(0f), TextUtils.TruncateAt.END).toString()

    /**
     * The client's report cover ("Cover - Master example", Oct 9 2026; report.html coverPage() is the reference):
     * page box in the chosen color and style (Framed = light fill + black border + soft glow in deep; Shaded = light→mid→deep
     * gradient; Solid = solid fill), logo top-left, company info top-right, title, fields on underlines (bold serif labels),
     * property photo box, the theme artwork at its position (clipped to the page box), and the ownership footer (wrapped beside
     * the artwork when the art reaches the footer band). Everything is placed in inches from covers.layout.
     */
    private fun cover() {
        startPage(header = false)
        val sel = b.inspection.selections
        val cfg = config.covers
        val lay = cfg.layout
        val cover = b.inspection.cover.normalized()
        val pal = cfg.colors.firstOrNull { it.name == cover.color } ?: cfg.colors.firstOrNull()
        val light = Color.parseColor(pal?.light ?: "#F7FAFD"); val mid = Color.parseColor(pal?.mid ?: "#B5D2EC")
        val deep = Color.parseColor(pal?.deep ?: "#237AD4"); val solid = Color.parseColor(pal?.solid ?: "#8DBAE9")
        val style = cover.style
        val box = lay.pageBox.inches(CoverLayoutDef().pageBox)

        // page box
        when (style) {
            "Shaded" -> cv.drawRect(box, Paint().apply {
                shader = LinearGradient(0f, box.top, 0f, box.bottom, intArrayOf(light, light, mid, deep, deep), floatArrayOf(0f, .18f, .56f, .83f, 1f), Shader.TileMode.CLAMP)
            })
            "Solid" -> cv.drawRect(box, fill(solid))
            else -> { coverGlow(box, deep); cv.drawRect(box, fill(light)) }
        }
        cv.drawRect(box, stroke(Color.BLACK, pt(.75f)))

        // logo (aspect-fit, top-left) + company info (centered in its box)
        val lr = lay.logo.rect.inches(CoverLayoutDef().logo.rect)
        logo?.let { l ->
            val s = minOf(lr.width() / l.width, lr.height() / l.height)
            cv.drawBitmap(l, null, RectF(lr.left, lr.top, lr.left + l.width * s, lr.top + l.height * s), Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
        } ?: drawLogo(lr.left, lr.top, minOf(lr.width(), lr.height()))
        val ir = lay.companyInfo.rect.inches(CoverLayoutDef().companyInfo.rect)
        run {
            val pn = tp(serifBold, pt(10.5f), Color.BLACK).apply { textAlign = Paint.Align.CENTER }
            val pl = tp(serif, pt(9.5f), Color.BLACK).apply { textAlign = Paint.Align.CENTER }
            var ty = ir.top + pn.textSize
            cv.drawText(ellipsize(company.name, pn, ir.width()), ir.centerX(), ty, pn)
            // name, address, phone, email (the client's company block)
            val parts = company.address.split(",").map { it.trim() }.filter { it.isNotEmpty() }
            val addr = if (parts.size >= 3) listOf(parts.dropLast(2).joinToString(", "), parts.takeLast(2).joinToString(", ")) else listOf(company.address).filter { it.isNotBlank() }
            (addr + listOf(company.phone, company.email).filter { it.isNotBlank() }).forEach {
                ty += pt(9.5f) * 1.42f
                if (ty <= ir.bottom + pt(6f)) cv.drawText(ellipsize(it, pl, ir.width()), ir.centerX(), ty, pl)
            }
        }

        // title
        val tSize = pt(lay.title.size)
        cv.drawText(when (layoutKind) {
            ChecklistConfig.LAYOUT_TEXAS -> "Property Inspection Report"
            ChecklistConfig.LAYOUT_FOUR_POINT -> "4-Point Inspection Report"
            else -> lay.title.text
        }, PW / 2, inch(lay.title.centerY) + tSize * .35f, tp(serifBold, tSize, Color.BLACK).apply { textAlign = Paint.Align.CENTER })

        // fields: bold labels, values on an underline; the second address line and the line after it sit closer (0.36 in)
        val four = layoutKind == ChecklistConfig.LAYOUT_FOUR_POINT
        val rows = if (four) listOf(
            "Insured / Applicant" to sel.field("insuredName").ifBlank { sel.clientName }, "Application / Policy #" to sel.field("policyNumber"),
            "Address Inspected" to sel.street, "" to sel.cityLine, "Actual Year Built" to sel.field("Year of construction"),
            "Date Inspected" to Fmt.slash(sel.date),
        ) else listOf(
            "Client Name" to sel.clientName, "Address of Inspection" to sel.street, "" to sel.cityLine,
            "Date of Inspection" to Fmt.slash(sel.date), "Real Estate Agent" to sel.agentName,
        )
        val f = lay.fields
        val pr0 = lay.photoBox.rect.inches(CoverLayoutDef().photoBox.rect)
        // 4-Point has one more row: 0.39 / 0.30 in gaps so the inspector line (~4.78 in) stays above the photo box (5.1 in).
        val near = if (four) .30f else .36f
        val gap = if (four) .39f else f.lineGap
        val gaps = rows.mapIndexed { i, (l, _) -> l.isEmpty() || rows.getOrNull(i + 1)?.first?.isEmpty() == true }
        val fs = pt(13f)
        val pl = tp(serifBold, fs, Color.BLACK); val pv = tp(serif, fs, Color.BLACK)
        val left = inch(f.left); val right = inch(f.right); val sp = inch(.085f); val pad = inch(.05f)
        val rule = fill(Color.BLACK); val ruleH = pt(.75f)
        fun valueLine(v: String, x0: Float, x1: Float, base: Float) {
            cv.drawText(ellipsize(v.ifBlank { "—" }, pv, x1 - x0 - pad * 2), x0 + pad, base, pv)
            cv.drawRect(x0, base + fs * .3f, x1, base + fs * .3f + ruleH, rule)
        }
        var top = f.top
        var prevVx = left
        rows.forEachIndexed { i, (l, v) ->
            val base = inch(top) + fs * .9f
            // Client Oct 17 (`fields.addressLine2`): the 2nd address line's underline starts and ends exactly where the first
            // line's value underline does — under the value, not under the label.
            val vx = if (l.isEmpty()) prevVx else { cv.drawText(l, left, base, pl); left + pl.measureText(l) + sp }
            valueLine(v, vx, right, base)
            prevVx = vx
            top += if (gaps[i]) near else gap
        }
        // Name of Inspector with License # on the same line (every report type)
        val inspBase = inch(top) + fs * .9f
        run {
            val licW = inch(1.445f)
            val licX = right - licW
            val licLabel = "License #"
            val licLabelX = licX - sp - pl.measureText(licLabel)
            cv.drawText("Name of Inspector", left, inspBase, pl)
            valueLine(company.inspectorName, left + pl.measureText("Name of Inspector") + sp, licLabelX - inch(.12f) - sp, inspBase)
            cv.drawText(licLabel, licLabelX, inspBase, pl)
            valueLine(inspectorLicense(), licX, right, inspBase)
        }

        // theme art + footer (client Oct 17, `footer.box`): the footer text sits in the SAME box on every cover — bottom-left, never
        // past the page's center line (sized like Hobbies – F1 Racing) — or in the matching right-hand box when the theme picture
        // is on the left (4th of July). The text is drawn after (above) the art; the company name is underlined.
        val art = cfg.art(cover)
        val artRect = art?.rect?.takeIf { it.size >= 4 }
        val artBmp = if (artRect != null) art?.file?.let { themeArt(it) } else null
        val artLeft = artRect != null && artRect[0] + artRect[2] / 2f < 4.25f
        val fb = (if (artLeft) lay.footer.box.right else lay.footer.box.left).takeIf { it.size >= 4 } ?: (if (artLeft) CoverFooterBoxDef().right else CoverFooterBoxDef().left)
        val fl = fb[0]
        val footW = inch(fb[2])
        // "{companyName}" is the signed-in inspector's Company profile name, underlined (client, Oct 16).
        val footText = android.text.SpannableStringBuilder().apply {
            lay.footer.text.split("{companyName}").forEachIndexed { i, part ->
                if (i > 0) {
                    val st = length; append(company.name.ifBlank { "the inspection company" })
                    if (company.name.isNotBlank()) setSpan(android.text.style.UnderlineSpan(), st, length, 0)
                }
                append(part)
            }
        }
        // Largest size up to footer.size that fits the box (a long company name or a state notice shrinks it, never below 7.5pt).
        val stateText = config.stateRule(sel.state)?.coverNotice
        var fsz = lay.footer.size
        fun noticeAt(sz: Float) = layout(footText, tp(serifBold, pt(sz), Color.BLACK), footW, Layout.Alignment.ALIGN_CENTER, 1.12f)
        fun stateAt(sz: Float) = stateText?.let { layout(it, tp(serifBold, pt(sz - 1.5f), Color.BLACK), footW, Layout.Alignment.ALIGN_CENTER, 1.08f) }
        fun heightAt(sz: Float) = noticeAt(sz).height + (stateAt(sz)?.let { it.height + inch(.05f) } ?: 0f)
        while (fsz > 7.5f && heightAt(fsz) > inch(fb[3] + (if (stateText != null) .25f else 0f))) fsz -= .5f
        val notice = noticeAt(fsz)
        // stateRules.<STATE>.coverNotice (e.g. Oregon): extra line under the ownership notice, every layout.
        val stateNotice = stateAt(fsz)
        val footH = notice.height + (stateNotice?.let { it.height + inch(.05f) } ?: 0f)
        // Centered in the box; kept inside the page box.
        val footTop = (inch(fb[1] + fb[3] / 2f) - footH / 2).coerceAtMost(box.bottom - inch(.06f) - footH)

        // property photo (center-crop, clipped); without one, the empty box with the client's "Picture of Property." label
        val pr = RectF(pr0.left, maxOf(pr0.top, inspBase + fs * .3f + inch(.2f)), pr0.right, minOf(pr0.bottom, footTop - inch(.08f)))
        val photo = coverPhoto()
        if (photo != null) {
            cv.drawRect(pr, fill(Color.WHITE))
            cv.save(); cv.clipRect(pr); drawCover(photo, pr); cv.restore()
            photo.recycle()
        } else {
            val lab = layout("Picture of\nProperty.", tp(serif, pt(8.5f), Color.BLACK), pr.left - box.left - inch(.1f))
            cv.drawLayout(lab, box.left + inch(.05f), pr.top)
        }
        cv.drawRect(pr, stroke(Color.BLACK, pt(lay.photoBox.border)))

        // theme artwork at its position, clipped to the page box (over the photo box, as designed)
        if (artBmp != null && artRect != null) {
            cv.save(); cv.clipRect(box)
            cv.drawBitmap(artBmp, null, RectF(inch(artRect[0]), inch(artRect[1]), inch(artRect[0] + artRect[2]), inch(artRect[1] + artRect[3])), Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
            cv.restore()
            artBmp.recycle()
        }
        // footer last, so it stays readable where it has to overlap the art's edge (the client's covers do the same)
        cv.drawLayout(notice, inch(fl), footTop)
        stateNotice?.let { cv.drawLayout(it, inch(fl), footTop + notice.height + inch(.05f)) }
    }

    /**
     * Horizontal extent, in page inches, of the artwork's visible pixels between page heights [y0, y1] — a column counts
     * when over 8% of its pixels in that band are mostly opaque (ignores stray sparks and soft edges). Null if none.
     */
    private fun artBandExtent(bmp: Bitmap, r: List<Float>, y0: Float, y1: Float): Pair<Float, Float>? {
        val top = maxOf(y0, r[1]); val bot = minOf(y1, r[1] + r[3])
        if (bot <= top || bmp.width == 0 || bmp.height == 0) return null
        val r0 = ((top - r[1]) / r[3] * bmp.height).toInt().coerceIn(0, bmp.height - 1)
        val rows = (((bot - r[1]) / r[3] * bmp.height).toInt() - r0).coerceIn(1, bmp.height - r0)
        val w = bmp.width
        val px = IntArray(w * rows).also { bmp.getPixels(it, 0, w, 0, r0, w, rows) }
        var first = -1; var last = -1
        for (c in 0 until w) {
            var n = 0
            for (row in 0 until rows) if ((px[row * w + c] ushr 24) > 128) n++
            if (n > rows * .08f) { if (first < 0) first = c; last = c }
        }
        if (first < 0) return null
        return r[0] + first.toFloat() / w * r[2] to r[0] + (last + 1f) / w * r[2]
    }

    /**
     * Framed style's soft outer glow (CSS `box-shadow: 0 0 0.32in 0.06in deep`): nested translucent layers from the
     * outside in, each alpha chosen so the composited opacity follows the Gaussian edge profile. Vector, no raster.
     */
    private fun coverGlow(box: RectF, color: Int) {
        val spread = inch(.06f); val sigma = inch(.16f); val step = 2f
        fun target(d: Float): Float = (.5 * erfc((d - spread) / (sigma * Math.sqrt(2.0).toFloat()))).toFloat()
        var prev = 0f
        var e = spread + sigma * 3f
        while (e > 0f) {
            val t = target(e - step / 2).coerceIn(0f, .99f)
            val a = if (prev >= 1f) 0f else 1f - (1f - t) / (1f - prev)
            if (a > 0f) {
                val r = RectF(box.left - e, box.top - e, box.right + e, box.bottom + e)
                cv.drawRoundRect(r, e, e, fill((color and 0x00FFFFFF) or ((a * 255).toInt().coerceIn(0, 255) shl 24)))
            }
            prev = t; e -= step
        }
    }

    /** Complementary error function (Abramowitz & Stegun 7.1.26). */
    private fun erfc(x: Float): Double {
        val z = Math.abs(x.toDouble()); val t = 1.0 / (1.0 + .3275911 * z)
        val y = t * (.254829592 + t * (-.284496736 + t * (1.421413741 + t * (-1.453152027 + t * 1.061405429)))) * Math.exp(-z * z)
        return if (x >= 0) y else 2.0 - y
    }

    /** A theme artwork from shared/covers (WebP with transparency), or null if the asset is missing. */
    private fun themeArt(file: String): Bitmap? = try { am.open(file).use { BitmapFactory.decodeStream(it) } } catch (_: Exception) { null }

    private fun inspectorLicense(): String = b.inspection.selections.license.ifBlank { company.license }

    private fun coverPhoto(): Bitmap? {
        val photos = b.photos
        val pick = photos.firstOrNull { baseName(it.section) == "Exterior Walls" && it.category.startsWith("Front") }
            ?: photos.firstOrNull { baseName(it.section) == "Landscaping" && it.category.startsWith("Front") }
            ?: photos.firstOrNull { it.flag == 0 } ?: photos.firstOrNull()
        return pick?.let { loadBitmap(it, 1400) }
    }

    private fun loadBitmap(p: Photo, max: Int): Bitmap? {
        val f = repo.photoFile(p)
        if (!f.exists()) return null
        val o = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(f.path, o)
        var s = 1
        while (maxOf(o.outWidth, o.outHeight) / (s * 2) >= max) s *= 2
        return BitmapFactory.decodeFile(f.path, BitmapFactory.Options().apply { inSampleSize = s })
    }

    /** Center-crop a bitmap into a rect (`object-fit: cover`). */
    private fun drawCover(bmp: Bitmap, r: RectF) {
        val sr = r.width() / r.height(); val br = bmp.width.toFloat() / bmp.height
        val src = if (br > sr) { val w = bmp.height * sr; android.graphics.Rect(((bmp.width - w) / 2).toInt(), 0, ((bmp.width + w) / 2).toInt(), bmp.height) }
        else { val h = bmp.width / sr; android.graphics.Rect(0, ((bmp.height - h) / 2).toInt(), bmp.width, ((bmp.height + h) / 2).toInt()) }
        cv.drawBitmap(bmp, src, r, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))
    }

    private fun propertyInfo() {
        startPage()
        val s = b.inspection.selections
        title("Property Information", "Inspection details & property description")
        fun num(v: String) = com.vims.app.util.Num.parse(v)
        val sq = s.field("Total sq ft").let { v -> num(v)?.let { String.format(Locale.US, "%,d sq ft", it.toLong()) } ?: v }
        val value = s.field("Valuation ($)").let { v -> num(v)?.let { String.format(Locale.US, "$%,d", it.toLong()) } ?: v }
        val lot = s.field("Lot size (acres)").let { if (it.isBlank()) it else "$it acres" }
        val stories = s.chip("Stories").let { if (it == "Other" && s.storiesOther.isNotBlank()) "Other — ${s.storiesOther}" else it }
        val garage = listOf(s.chip("Garage"), s.chip("Number of cars").takeIf { it.isNotBlank() && s.chip("Garage") != "None" }?.let { "$it cars" }).filter { !it.isNullOrBlank() }.joinToString(" · ")
        val type = if (s.inspType == "Component" && s.component.isNotEmpty()) "Component — ${s.component.joinToString(", ")}" else s.inspType
        val rows = mutableListOf(
            "Type of inspection" to type, "Type of loan" to s.chip("Type of loan"),
            "Property type" to s.structure, "Construction style" to s.chip("Construction style"),
            "Year of construction" to s.field("Year of construction"), "Total square footage" to sq,
            "Valuation" to value, "Lot size" to lot,
            "Stories" to stories, "Basement" to s.chip("Basement"),
            "Garage" to garage, "Car port" to s.chip("Car port"),
        )
        config.wizard.roomCounts.forEach { rows += it.label to s.count(it.key).toString() }
        rows += "Kitchen" to (if ("Kitchen" in s.rooms) "1" else "0")
        rows += "Checklist depth" to config.depthLabel(s.depth)
        if (s.structure == "Multi-Unit") s.unitMix.filter { it.value > 0 }.forEach { (k, v) -> rows += "Units · $k" to v.toString() }
        infoGrid(rows)
        blockLabel("Additional inspection services")
        note(config.wizard.testOptions.filter { it in s.tests }.joinToString(" · ").ifEmpty { "None" })
        val contact = listOf(s.clientName, s.field("Client phone"), s.clientEmail).filter { it.isNotBlank() }
        if (contact.isNotEmpty()) { blockLabel("Client"); note(contact.joinToString(" · ")) }
    }

    private fun beginningNotes() {
        startPage()
        val s = b.inspection.selections
        title("Beginning Notes", "Conditions at the time of inspection")
        infoGrid(listOf(
            "Property status" to s.chip("Property status"), "Weather" to s.chip("Weather & site conditions"),
            "Temperature" to s.field("Temperature (°F)").let { if (it.isBlank()) it else "$it°F" }, "Power is on" to s.chip("Power is on"),
            "Gas is on" to s.chip("Gas is on"), "Water is on" to s.chip("Water is on"),
        ))
        blockLabel("Buyer’s areas of concern")
        note(s.field("Buyer's areas of concern").ifBlank { "None noted." })
        blockLabel("Apparent hazards observed before inspection")
        note(s.field("Apparent hazards observed before inspection").ifBlank { "None noted." })
    }

    private fun answerText(key: String, it: ItemDef, a: SectionAnswers, detail: Boolean): String? {
        val chips = a.values[key].orEmpty().joinToString(", ")
        val input = a.inputs[key].orEmpty().trim()
        val v = when (it.type) {
            "date" -> if (input.isBlank()) "" else Fmt.date(input)
            "time" -> if (input.isBlank()) "" else Fmt.time(input)
            "num", "text" -> input
            // Data v1.13 countChoice (client Oct 30): "GFCI (4), Standard (6)", "GFCI" (no count) or "None".
            ItemDef.TYPE_COUNT_CHOICE -> com.vims.app.data.CountChoice.text(a, key)
            // airReading outside a section with an `airQuality` table: "<level> <unit> · Rating <n>"
            ItemDef.TYPE_AIR_READING -> listOfNotNull(a.airLevel(key).ifBlank { null }?.let { l -> listOf(l, it.unit.orEmpty()).filter { x -> x.isNotBlank() }.joinToString(" ") },
                a.airRating(key)?.let { r -> "Rating $r" }).joinToString(" · ")
            else -> if (detail && input.isNotBlank()) listOf(chips, input).filter { s -> s.isNotBlank() }.joinToString(" — ") else chips
        }
        return v.ifBlank { null }
    }

    private fun sectionPages(section: String) {
        startPage()
        val num = ChecklistEngine.number(b.defs, section)
        val title = sectionTitle(section)
        secTitle(num, title)
        val a = b.answers[section] ?: SectionAnswers()
        val def = b.defs[baseName(section)]
        val depth = b.inspection.selections.depth
        val kP = tp(plex400, 12.5f, INK2); val vP = tp(plex600, 12.5f, INK)
        fun row(k: String, v: String, dot: Int = 0) {
            val kl = layout(k, kP, CW * .52f - 12f)
            val vl = layout(v, vP, CW * .48f - 24f)
            val h = maxOf(kl.height, vl.height) + 14f
            ensure(h) { secTitle(num, "${sectionTitle(section)} (cont.)") }
            cv.drawLayout(kl, PADX + 6f, y + 7f)
            cv.drawLayout(vl, PADX + CW * .52f + 6f, y + 7f)
            if (dot > 0) cv.drawCircle(PADX + CW * .52f + 6f + vl.getLineWidth(0) + 11f, y + 7f + 8f, 4f, fill(C[dot]))
            cv.drawRect(PADX, y + h - 1f, PADX + CW, y + h, fill(LINE2))
            y += h
        }
        fun band(t: String) {
            ensure(60f) { secTitle(num, "${sectionTitle(section)} (cont.)") }
            y += 14f
            val h = 30f
            cv.drawRoundRect(RectF(PADX, y, PADX + CW, y + h), 6f, 6f, fill(PAPER2))
            cv.drawRect(PADX, y, PADX + 3f, y + h, fill(BRAND))
            cv.drawText(t, PADX + 11f, y + 19.5f, tp(archivo700, 12.5f, BRAND_DEEP))
            y += h + 8f
        }
        var any = false
        if (depth == "fast") {
            if (a.present.isNotEmpty()) { row("Items reviewed", a.present.joinToString(", ")); any = true }
        } else if (def != null) {
            // `visibleIf` items that are hidden (e.g. "Sample 3 location" with 2 samples) are not printed.
            val keyed = ChecklistEngine.visibleKeyed(ChecklistEngine.keyed(ChecklistEngine.itemsFor(def, depth)), a)
            val detail = ChecklistEngine.showDetailInput(def, depth)
            val aq = def.airQuality
            var pendingHeader: String? = null
            var i = 0
            while (i < keyed.size) {
                val (key, it) = keyed[i]
                if (key == null) { pendingHeader = it.header; i++; continue }
                if (aq != null && it.isAirReading) {
                    // A run of readings prints as the client's IAQ table; its legend replaces the "Readings (…)" band.
                    val run = keyed.drop(i).takeWhile { p -> p.first != null && p.second.isAirReading }.map { p -> p.first!! to p.second }
                    pendingHeader = null
                    airQualityTable(num, section, aq, run, a)
                    any = true; i += run.size; continue
                }
                i++
                val v = answerText(key, it, a, detail) ?: continue
                pendingHeader?.let { h -> band(h); pendingHeader = null }
                row(it.q.orEmpty(), v, if (a.values[key].orEmpty().any { o -> o.equals("Concerns", true) || o.equals("Fail", true) }) 2 else 0)
                any = true
            }
        }
        if (!any) row("Line items", "No line items recorded")
        // Data v1.8 `reportNote` (Radon): the section's note paragraphs, after its items (the measured level) and above Overall condition.
        (def?.reportNote ?: config.section(baseName(section))?.reportNote).orEmpty().filter { it.isNotBlank() }.forEach { para ->
            val l = layout(para, tp(plex400, 11.5f, INK2), CW - 12f, spacing = 1.18f)
            ensure(l.height + 10f) { secTitle(num, "${sectionTitle(section)} (cont.)") }
            y += 10f
            cv.drawLayout(l, PADX + 6f, y)
            y += l.height
        }
        // overall condition
        val overall = (a.overall ?: config.overallConditionDefault).ifBlank { "Not recorded" }
        ensure(50f)
        y += 14f
        val (bg, border, fg) = when (overall) {
            "Poor", "Needs Attention" -> Triple(CBG[2], Color.parseColor("#F0DCAE"), Color.parseColor("#A5730A"))
            "Not Inspected", "N/A", "Not recorded" -> Triple(PAPER2, LINE, INK2)
            else -> Triple(CBG[3], Color.parseColor("#BFE3D0"), Color.parseColor("#1F7A52"))
        }
        val r = RectF(PADX, y, PADX + CW, y + 40f)
        cv.drawRoundRect(r, 8f, 8f, fill(bg)); cv.drawRoundRect(r, 8f, 8f, stroke(border, 1f))
        cv.drawText("Overall condition", PADX + 14f, y + 25f, tp(plex400, 13f, INK))
        cv.drawText(overall, PADX + CW - 14f, y + 25f, tp(plex700, 13f, fg).apply { textAlign = Paint.Align.RIGHT })
        y += 40f
        if (a.comments.isNotBlank()) { blockLabel("Comments"); note(a.comments) }
        val fs = b.findings.filter { it.section == section }
        if (fs.isNotEmpty()) {
            blockLabel("Findings")
            fs.sortedBy { it.cat }.forEach { f ->
                val label = config.findings.categories.firstOrNull { it.id == f.cat }?.label.orEmpty()
                val l = layout("Category ${f.cat} · $label — ${f.body}", tp(plex400, 12.5f, INK2), CW - 30f)
                ensure(l.height + 12f)
                cv.drawCircle(PADX + 8f, y + 12f, 4.5f, fill(C[f.cat.coerceIn(1, 3)]))
                cv.drawLayout(l, PADX + 22f, y + 4f)
                y += l.height + 12f
            }
        }
    }

    /**
     * Indoor Air Quality readings table (data v1.7 `airQuality`, the client's "Indoor air quality report - Updated" form;
     * report.html `.aqhead` / `.aqrow`): legend top-right, "Level Measured" / "Air Quality Rating" column heads, then per
     * reading "<code> – <name>" | level + unit on an underline | rating (bold), and under it the reference levels (left)
     * and the corrective action (right) in small text. Unanswered readings still print with a blank underline and rating,
     * like the paper form. A reading never splits across pages; the column heads repeat after a page break.
     */
    private fun airQualityTable(num: Int, section: String, aq: AirQualityDef, rows: List<Pair<String, ItemDef>>, a: SectionAnswers) {
        val nameW = CW * .36f
        val lvL = PADX + CW * .37f; val lvR = lvL + CW * .15f
        val rtL = PADX + CW * .53f; val rtR = rtL + CW * .15f
        val headP = tp(plex600, 11f, INK2).apply { textAlign = Paint.Align.CENTER }
        val legendP = tp(plex600, 10.5f, INK).apply { textAlign = Paint.Align.RIGHT }
        val legend = aq.legend.split("·").map { it.trim() }.filter { it.isNotEmpty() }.joinToString("    ")
        val cols = aq.columns.ifEmpty { AirQualityDef().columns }
        val nameP = tp(plex400, 13f, INK); val lvP = tp(plex400, 12.5f, INK).apply { textAlign = Paint.Align.CENTER }
        val rtP = tp(plex700, 14f, INK).apply { textAlign = Paint.Align.CENTER }
        val subP = tp(plex400, 10f, INK2)
        val legendInline = legendP.measureText(legend) <= PADX + CW - (rtR + 14f)
        val headH = if (legendInline || legend.isEmpty()) 26f else 44f
        fun heads() {
            if (!legendInline && legend.isNotEmpty()) { cv.drawText(legend, PADX + CW, y + 12f, legendP); y += 18f }
            val base = y + 14f
            cols.getOrNull(0)?.let { cv.drawText(it, (lvL + lvR) / 2, base, headP) }
            cols.getOrNull(1)?.let { cv.drawText(it, (rtL + rtR) / 2, base, headP) }
            if (legendInline && legend.isNotEmpty()) cv.drawText(legend, PADX + CW, base, legendP)
            y += 26f
            cv.drawRect(PADX, y - 1f, PADX + CW, y, fill(LINE))
        }
        fun label(it: ItemDef): CharSequence {
            val q = it.q.orEmpty(); val code = it.code.orEmpty().trim()
            val sb = android.text.SpannableStringBuilder()
            val rest = when {
                code.isEmpty() -> { sb.append(q); return sb }
                q.startsWith(code) -> q.removePrefix(code)
                else -> " – $q"
            }
            sb.append(code); sb.setSpan(android.text.style.StyleSpan(Typeface.BOLD), 0, code.length, 0)
            sb.append(rest)
            return sb
        }
        val layouts = rows.map { (key, it) ->
            val ref = it.reference.orEmpty().trim(); val act = it.action.orEmpty().trim()
            Triple(layout(label(it), nameP, nameW),
                layout(ref.ifEmpty { " " }, subP, CW * .5f - 12f),
                layout(if (act.isEmpty()) " " else aq.actionPrefix + act, subP, CW * .46f, Layout.Alignment.ALIGN_OPPOSITE)) to key
        }
        fun rowH(l: Triple<StaticLayout, StaticLayout, StaticLayout>) = 10f + maxOf(l.first.height.toFloat(), 22f) + 5f + maxOf(l.second.height, l.third.height) + 9f
        y += 8f
        // keep the column heads with the first reading
        ensure(headH + (layouts.firstOrNull()?.let { rowH(it.first) } ?: 0f)) { secTitle(num, "${sectionTitle(section)} (cont.)") }
        heads()
        layouts.forEachIndexed { idx, (l, key) ->
            val it = rows[idx].second
            val h = rowH(l)
            ensure(h) { secTitle(num, "${sectionTitle(section)} (cont.)"); heads() }
            val top = y + 10f
            cv.drawLayout(l.first, PADX + 6f, top)
            val base = top + l.first.getLineBaseline(0)
            val level = a.airLevel(key)
            if (level.isNotEmpty()) {
                val t = listOf(level, it.unit.orEmpty()).filter { x -> x.isNotBlank() }.joinToString(" ")
                cv.drawText(ellipsize(t, lvP, lvR - lvL - 8f), (lvL + lvR) / 2, base, lvP)
            }
            cv.drawRect(lvL + 14f, base + 4f, lvR - 14f, base + 5f, fill(INK3))
            a.airRating(key)?.let { r -> cv.drawText(r, (rtL + rtR) / 2, base, rtP) }
            val subTop = top + maxOf(l.first.height.toFloat(), 22f) + 5f
            cv.drawLayout(l.second, PADX + 6f, subTop)
            cv.drawLayout(l.third, PADX + CW - 6f - l.third.width, subTop)
            cv.drawRect(PADX, y + h - 1f, PADX + CW, y + h, fill(LINE2))
            y += h
        }
    }

    private fun photoPages(section: String) {
        val photos = b.photos.filter { it.section == section }
        if (photos.isEmpty()) return
        val num = ChecklistEngine.number(b.defs, section)
        startPage()
        secTitle(num, "${sectionTitle(section)} · Photos")
        val colW = (CW - 16f) / 2
        val imgH = colW * 2f / 3f
        val capP = tp(plex400, 11.5f, INK2)
        photos.chunked(2).forEach { pair ->
            val caps = pair.map { p -> layout(listOf(p.category, p.caption).filter { it.isNotBlank() }.joinToString(" — "), capP, colW - 22f - (if (p.flag > 0) 50f else 0f)) }
            val h = imgH + caps.maxOf { it.height } + 16f
            if (y + h > BOTTOM) { startPage(); secTitle(num, "${sectionTitle(section)} · Photos (cont.)") }
            pair.forEachIndexed { i, p ->
                val x = PADX + i * (colW + 16f)
                val card = RectF(x, y, x + colW, y + h)
                val clip = Path().apply { addRoundRect(card, 8f, 8f, Path.Direction.CW) }
                cv.save(); cv.clipPath(clip)
                val bmp = loadBitmap(p, 900)
                val ir = RectF(x, y, x + colW, y + imgH)
                if (bmp != null) { drawCover(bmp, ir); bmp.recycle() } else cv.drawRect(ir, fill(LINE))
                cv.restore()
                cv.drawRoundRect(card, 8f, 8f, stroke(LINE, 1f))
                if (p.flag > 0) {
                    val tagP = tp(plex700, 10f, Color.WHITE)
                    val tw = tagP.measureText("Concern") + 18f
                    cv.drawRoundRect(RectF(x + 8f, y + 8f, x + 8f + tw, y + 26f), 9f, 9f, fill(C[1]))
                    cv.drawText("Concern", x + 17f, y + 21f, tagP)
                    val cw = tagP.measureText("Cat ${p.flag}") + 16f
                    val cr = RectF(x + colW - 11f - cw, y + imgH + 8f, x + colW - 11f, y + imgH + 25f)
                    cv.drawRoundRect(cr, 9f, 9f, fill(C[p.flag.coerceIn(1, 3)]))
                    cv.drawText("Cat ${p.flag}", cr.left + 8f, cr.bottom - 4.5f, tagP)
                }
                cv.drawLayout(caps[i], x + 11f, y + imgH + 8f)
            }
            y += h + 16f
        }
    }

    private fun summary() {
        startPage()
        title("Summary of Findings", if (layoutKind == ChecklistConfig.LAYOUT_TEXAS) "Findings grouped by category" else "Findings grouped by category, in the order they appear in the report")
        stateDisclosure()
        config.findings.categories.forEach { cat ->
            val items = b.findings.filter { it.cat == cat.id }.sortedWith(compareBy({ ChecklistEngine.number(b.defs, it.section) }, { it.createdAt }))
            val rows = items.mapIndexed { i, f ->
                // Same line as the app's Summary screen (client, Oct 16): **Section** — custom comment — quick comment.
                val l = layout(android.text.SpannableStringBuilder().apply {
                    append(sectionTitle(f.section)); setSpan(android.text.style.StyleSpan(Typeface.BOLD), 0, length, 0); setSpan(android.text.style.ForegroundColorSpan(INK), 0, length, 0)
                    f.body.takeIf { it.isNotBlank() }?.let { append(" — $it") }
                }, tp(plex400, 12.5f, INK2), CW - 30f - 36f)
                (i + 1) to l
            }.ifEmpty { listOf(0 to layout("No findings in this category.", tp(plex400, 12.5f, INK3), CW - 30f)) }
            var idx = 0
            var first = true
            while (idx < rows.size || first) {
                val headH = 58f
                ensure(headH + (rows.getOrNull(idx)?.second?.height ?: 0) + 18f)
                val top = y
                // header band
                val cp = C[cat.id.coerceIn(1, 3)]
                cv.save()
                val chunk = mutableListOf<Pair<Int, StaticLayout>>()
                var h = headH
                while (idx < rows.size && (chunk.isEmpty() || top + h + rows[idx].second.height + 18f <= BOTTOM)) { chunk += rows[idx]; h += rows[idx].second.height + 18f; idx++ }
                val box = RectF(PADX, top, PADX + CW, top + h)
                val clip = Path().apply { addRoundRect(box, 10f, 10f, Path.Direction.CW) }
                cv.clipPath(clip)
                cv.drawRect(PADX, top, PADX + CW, top + headH, fill(CBG[cat.id.coerceIn(1, 3)]))
                cv.restore()
                cv.drawRoundRect(box, 10f, 10f, stroke(LINE, 1f))
                cv.drawRoundRect(RectF(PADX + 15f, top + 12f, PADX + 49f, top + 46f), 8f, 8f, fill(cp))
                cv.drawText("${cat.id}", PADX + 32f, top + 35f, tp(archivo800, 16f, Color.WHITE).apply { textAlign = Paint.Align.CENTER })
                val hp = tp(archivo700, 15f, INK)
                val t1 = "Category ${cat.id}" + if (first) "" else " (cont.)"
                cv.drawText(t1, PADX + 61f, top + 27f, hp)
                cv.drawText(" · ${cat.label}", PADX + 61f + hp.measureText(t1), top + 27f, tp(archivo700, 15f, INK2))
                cv.drawText(cat.note, PADX + 61f, top + 44f, tp(plex400, 12f, INK3))
                cv.drawText("${items.size}", PADX + CW - 15f, top + 34f, tp(plex700, 15f, INK).apply { textAlign = Paint.Align.RIGHT })
                var ry = top + headH
                chunk.forEach { (n, l) ->
                    cv.drawRect(PADX, ry, PADX + CW, ry + 1f, fill(LINE2))
                    if (n > 0) cv.drawText("$n", PADX + 15f, ry + 9f + 12.5f, tp(plex700, 12.5f, INK))
                    cv.drawLayout(l, PADX + 15f + (if (n > 0) 31f else 0f), ry + 9f)
                    ry += l.height + 18f
                }
                y = top + h + 14f
                first = false
                if (idx >= rows.size) break
                startPage()
            }
        }
    }

    /** stateRules.<STATE>.summaryDisclosure (e.g. Oklahoma): note box with an amber left edge on page 1 of the summary. */
    private fun stateDisclosure() {
        val st = b.inspection.selections.state
        val text = config.stateRule(st)?.summaryDisclosure ?: return
        val sb = android.text.SpannableStringBuilder().apply {
            val s0 = length; append("${config.stateName(st)} disclosure")
            setSpan(android.text.style.StyleSpan(Typeface.BOLD), s0, length, 0); setSpan(android.text.style.ForegroundColorSpan(INK), s0, length, 0)
            append("\n"); append(text)
        }
        val l = layout(sb, tp(plex400, 12.5f, INK2), CW - 29f, spacing = 1.2f)
        val h = l.height + 22f
        val r = RectF(PADX, y, PADX + CW, y + h)
        cv.drawRoundRect(r, 8f, 8f, fill(PAPER2)); cv.drawRoundRect(r, 8f, 8f, stroke(LINE, 1f))
        cv.save(); cv.clipPath(Path().apply { addRoundRect(r, 8f, 8f, Path.Direction.CW) }); cv.drawRect(PADX, y, PADX + 3f, y + h, fill(C[2])); cv.restore()
        cv.drawLayout(l, PADX + 16f, y + 11f)
        y += h + 14f
    }

    // ================================================================== state & insurance forms

    /** Checklist sections of a form inspection (everything except the picture page), in checklist order. */
    private fun formSections(): List<String> = b.inspection.leafSections.filter { b.defs[baseName(it)]?.photosOnly != true }
        .sortedWith(compareBy<String>({ ChecklistEngine.number(b.defs, it) }, { it }))

    private fun pageOfTotal() = if (totalPages > 0) "Page $pageNo of $totalPages" else "Page $pageNo"

    private fun texasFooter() {
        val top = PH - PADY - 22f
        cv.drawRect(PADX, top - 10f, PW - PADX, top - 9f, fill(INK))
        val p = tp(plex400, 9.5f, INK2)
        cv.drawText("REI 7-6 (8/9/21)  ·  Promulgated by the Texas Real Estate Commission  ·  (512) 936-3000  ·  www.trec.texas.gov", PADX, top + 6f, p)
        cv.drawText(pageOfTotal(), PW - PADX, top + 6f, tp(plex400, 9.5f, INK2).apply { textAlign = Paint.Align.RIGHT })
    }

    private fun fourPointFooter() {
        val top = PH - PADY - 30f
        cv.drawRect(PADX, top - 14f, PW - PADX, top - 13f, fill(LINE))
        val sel = b.inspection.selections
        cv.drawText("4-Point Inspection · ${sel.street} · ${Fmt.slash(sel.date)}", PADX, top + 2f, tp(plex400, 10f, INK3))
        cv.drawText(pageOfTotal(), PW - PADX, top + 2f, tp(plex400, 10f, INK3).apply { textAlign = Paint.Align.RIGHT })
    }

    private fun addressLine(): String = b.inspection.selections.let { listOf(it.street, it.cityLine).filter { x -> x.isNotBlank() }.joinToString(", ") }

    /** TREC REI 7-6 page 1: client / inspector / sponsor block + the promulgated text. */
    private fun trecInfoPage() {
        pageHeader = {}
        startPage(header = false)
        val sel = b.inspection.selections
        cv.drawText("PROPERTY INSPECTION REPORT FORM", PW / 2, y + 16f, tp(archivo800, 16f).apply { textAlign = Paint.Align.CENTER })
        y += 16f + 14f
        val gap = 16f
        val w1 = (CW - gap) * 1.6f / 2.6f; val w2 = CW - gap - w1
        fun cell(x: Float, w: Float, label: String, value: String) {
            cv.drawText(label, x, y + 10f, tp(plex400, 9.5f, INK3))
            var v = value; val vp = tp(plex400, 11f, INK)
            while (v.isNotEmpty() && vp.measureText(v) > w) v = v.dropLast(1)
            cv.drawText(v, x, y + 24f, vp)
            cv.drawRect(x, y + 29f, x + w, y + 30f, fill(INK))
        }
        fun row(a: Pair<String, String>, b2: Pair<String, String>?) {
            if (b2 == null) cell(PADX, CW, a.first, a.second)
            else { cell(PADX, w1, a.first, a.second); cell(PADX + w1 + gap, w2, b2.first, b2.second) }
            y += 30f + 7f
        }
        row("Name of Client" to sel.clientName, "Date of Inspection" to Fmt.slash(sel.date))
        row("Address of Inspected Property" to addressLine(), null)
        row("Name of Inspector" to company.inspectorName, "TREC License #" to inspectorLicense())
        row("Name of Sponsor (if applicable)" to sel.field("sponsorName"), "TREC License #" to sel.field("sponsorLicense"))
        y += 4f
        TREC_TEXT.forEach { block ->
            when (block) {
                is TrecBlock.Heading -> { val l = layout(block.text, tp(plex700, 10.6f), CW); ensure(l.height + 30f); cv.drawLayout(l, PADX, y); y += l.height }
                is TrecBlock.Para -> {
                    val sb = android.text.SpannableStringBuilder()
                    if (block.lead != null) { sb.append(block.lead); sb.setSpan(android.text.style.StyleSpan(Typeface.BOLD), 0, sb.length, 0); sb.append(" ") }
                    sb.append(block.text)
                    val l = layout(sb, tp(plex400, 10.2f), CW, spacing = 1.3f); ensure(l.height + 6f); cv.drawLayout(l, PADX, y); y += l.height + 6f
                }
                is TrecBlock.Bullets -> {
                    block.items.forEach { t ->
                        val l = layout(t, tp(plex400, 10.2f), CW - 16f, spacing = 1.3f); ensure(l.height.toFloat())
                        cv.drawText("•", PADX + 4f, y + 10f, tp(plex400, 10.2f)); cv.drawLayout(l, PADX + 16f, y); y += l.height
                    }
                    y += 6f
                }
            }
        }
    }

    private var trecSystem = ""

    private fun trecHeader(system: String) {
        val p = tp(plex400, 11f, INK2)
        val bold = tp(plex700, 11f, INK)
        cv.drawText("Report Identification:", PADX, y + 11f, bold)
        var addr = addressLine(); val ax = PADX + bold.measureText("Report Identification:") + 5f
        while (addr.isNotEmpty() && p.measureText(addr) > PW - PADX - ax) addr = addr.dropLast(1)
        cv.drawText(addr, ax, y + 11f, p)
        cv.drawRect(PADX, y + 17f, PW - PADX, y + 18f, fill(INK))
        y += 18f + 8f
        cv.drawText("I=Inspected    NI=Not Inspected    NP=Not Present    D=Deficient", PADX, y + 10.5f, tp(plex700, 10.5f, INK))
        y += 10.5f + 10f
        listOf("I", "NI", "NP", "D").forEachIndexed { i, t ->
            val r = RectF(PADX + i * 26f, y, PADX + (i + 1) * 26f, y + 17f)
            cv.drawRect(r, fill(PAPER2)); cv.drawRect(r, stroke(Color.parseColor("#9AA5B1"), 1f))
            cv.drawText(t, r.centerX(), r.bottom - 5f, tp(plex700, 10f, INK).apply { textAlign = Paint.Align.CENTER })
        }
        y += 17f + 8f
        val l = layout(system, tp(archivo800, 13f), CW)
        cv.drawLayout(l, PADX, y + 4f); y += l.height + 8f
        cv.drawRect(PADX, y, PW - PADX, y + 1f, fill(LINE)); y += 4f
    }

    /** One TREC system (section): rows with I / NI / NP / D boxes, component name, form fields and comments. */
    private fun trecChecklist(section: String) {
        val def = b.defs[baseName(section)] ?: return
        val a = b.answers[section] ?: SectionAnswers()
        trecSystem = section.substringAfter("— ").uppercase(Locale.US)
        pageHeader = { trecHeader("$trecSystem (continued)") }
        startPage(header = false)
        trecHeader(trecSystem)
        data class Comp(val name: String, val marks: BooleanArray, val fields: List<String>, val comment: String)
        val comps = mutableListOf<Comp>()
        var cur: Comp? = null
        ChecklistEngine.keyed(def.items).forEach { (key, it) ->
            if (key == null) { cur?.let { c -> comps += c }; cur = Comp(it.header.orEmpty(), BooleanArray(4), emptyList(), ""); return@forEach }
            val c = cur ?: Comp("", BooleanArray(4), emptyList(), "").also { n -> cur = n }
            when {
                it.isChoice && it.q == "Status" -> a.values[key].orEmpty().forEach { v ->
                    val idx = listOf("I", "NI", "NP", "D").indexOf(v.substringBefore(" ·").trim())
                    if (idx >= 0) c.marks[idx] = true
                }
                it.q == "Comments" -> cur = c.copy(comment = a.inputs[key].orEmpty().trim())
                it.isChoice -> cur = c.copy(fields = c.fields + "${it.q}: ${a.values[key].orEmpty().joinToString(", ")}")
                else -> cur = c.copy(fields = c.fields + "${it.q}: ${answerText(key, it, a, false).orEmpty()}")
            }
        }
        cur?.let { comps += it }
        val boxBorder = stroke(Color.parseColor("#9AA5B1"), 1f)
        val itemX = PADX + 4 * 26f + 10f; val itemW = PW - PADX - itemX
        comps.forEach { c ->
            val name = layout(c.name, tp(plex700, 11.5f), itemW)
            val fields = c.fields.map { layout(it, tp(plex400, 11f, INK2), itemW) }
            val cm = android.text.SpannableStringBuilder("Comments: ").apply {
                setSpan(android.text.style.ForegroundColorSpan(INK3), 0, length, 0); append(c.comment)
            }
            val comment = layout(cm, tp(plex400, 11f, INK), itemW)
            val h = 5f + name.height + fields.sumOf { it.height + 2 } + 3f + comment.height + 6f
            ensure(h)
            listOf(0, 1, 2, 3).forEach { i ->
                val r = RectF(PADX + i * 26f, y, PADX + (i + 1) * 26f, y + h)
                cv.drawRect(r, boxBorder)
                if (c.marks[i]) cv.drawText("✓", r.centerX(), y + 17f, tp(plex700, 12f, INK).apply { textAlign = Paint.Align.CENTER })
            }
            var ty = y + 5f
            cv.drawLayout(name, itemX, ty); ty += name.height
            fields.forEach { f -> ty += 2f; cv.drawLayout(f, itemX, ty); ty += f.height }
            ty += 3f; cv.drawLayout(comment, itemX, ty)
            cv.drawRect(itemX - 10f, y + h - 1f, PW - PADX, y + h, fill(LINE2))
            y += h
        }
    }

    /** Picture pages (Texas + 4-Point): 3 columns, 6 per page; the Pictures section first, then photos from the form sections. */
    private fun picturePages() {
        pageHeader = { runningHeader() }
        val picsSection = b.inspection.leafSections.firstOrNull { b.defs[baseName(it)]?.photosOnly == true }
        val photos = b.photos.filter { it.section == picsSection } + b.photos.filter { it.section != picsSection }
        val chunks = photos.chunked(6).ifEmpty { listOf(emptyList()) }
        val colW = (CW - 24f) / 3; val imgH = colW * 3f / 4f
        val capP = tp(plex400, 11f, INK2)
        chunks.forEachIndexed { ci, chunk ->
            startPage()
            picTitle(if (ci == 0) "Pictures" else "Pictures (continued)")
            if (chunk.isEmpty()) { cv.drawText("No pictures were added to this inspection.", PADX, y + 14f, tp(plex400, 12.5f, INK3)); return@forEachIndexed }
            chunk.chunked(3).forEach { row ->
                val caps = row.map { p ->
                    val t = listOf(if (p.section == picsSection) p.category else "${p.section.substringAfter("— ")} · ${p.category}", p.caption).filter { it.isNotBlank() }.joinToString(" — ")
                    layout(t, capP, colW - 18f)
                }
                val h = imgH + caps.maxOf { it.height } + 16f
                row.forEachIndexed { i, p ->
                    val x = PADX + i * (colW + 12f)
                    val card = RectF(x, y, x + colW, y + h)
                    cv.save(); cv.clipPath(Path().apply { addRoundRect(card, 8f, 8f, Path.Direction.CW) })
                    val ir = RectF(x, y, x + colW, y + imgH)
                    val bmp = loadBitmap(p, 700)
                    if (bmp != null) { drawCover(bmp, ir); bmp.recycle() } else cv.drawRect(ir, fill(LINE))
                    cv.restore()
                    cv.drawRoundRect(card, 8f, 8f, stroke(LINE, 1f))
                    if (p.flag > 0) {
                        val tagP = tp(plex700, 10f, Color.WHITE); val tw = tagP.measureText("Deficiency") + 18f
                        cv.drawRoundRect(RectF(x + 8f, y + 8f, x + 8f + tw, y + 26f), 9f, 9f, fill(C[1])); cv.drawText("Deficiency", x + 17f, y + 21f, tagP)
                    }
                    cv.drawLayout(caps[i], x + 9f, y + imgH + 8f)
                }
                y += h + 12f
            }
        }
    }

    private fun picTitle(t: String) {
        val h = 44f
        cv.drawRoundRect(RectF(PADX, y, PADX + CW, y + h), 9f, 9f, fill(BRAND))
        val bx = RectF(PADX + 15f, y + 10f, PADX + 15f + 34f, y + h - 10f)
        cv.drawRoundRect(bx, 7f, 7f, fill(Color.argb(51, 255, 255, 255)))
        val w = stroke(Color.WHITE, 1.6f)
        cv.drawRoundRect(RectF(bx.left + 8f, bx.top + 7f, bx.right - 8f, bx.bottom - 5f), 2.5f, 2.5f, w)
        cv.drawCircle(bx.centerX(), bx.centerY() + 1f, 3.6f, w)
        cv.drawText(t, bx.right + 10f, y + h / 2 + 6f, tp(archivo700, 16f, Color.WHITE))
        y += h + 14f
    }

    // ---- 4-Point form

    private class FpBox(val title: String?, val items: List<Pair<String, ItemDef>>) {
        val sup get() = title?.startsWith("Supplemental", true) == true
        val comments get() = title?.startsWith("Additional Comments", true) == true
    }

    private val FP_EDGE = Color.parseColor("#555555")
    private val CERT_H = 7f + 16f + 2 * 44f + 10f

    private fun fpItemText(key: String, it: ItemDef, a: SectionAnswers): CharSequence {
        val sb = android.text.SpannableStringBuilder()
        fun bold(t: String) { val st = sb.length; sb.append(t); sb.setSpan(android.text.style.StyleSpan(Typeface.BOLD), st, sb.length, 0) }
        sb.append("${it.q}: ")
        if (it.isChoice) {
            val sel = a.values[key].orEmpty()
            it.options.orEmpty().forEachIndexed { i, o -> if (i > 0) sb.append("   "); if (o in sel) { sb.append("☑ "); bold(o) } else sb.append("☐ $o") }
        } else {
            val v = answerText(key, it, a, false)
            if (v.isNullOrBlank()) sb.append("__________") else bold(v)
        }
        return sb
    }

    /** Lays out one box (or two boxes side by side) and returns its height and a draw function. */
    private fun fpMeasure(boxes: List<FpBox>, a: SectionAnswers): Pair<Float, (Float) -> Unit> {
        val gap = 18f
        val colW = (CW - 20f - gap * (boxes.size - 1)) / boxes.size
        val cols = boxes.map { box ->
            val ls = mutableListOf<StaticLayout>()
            if (box.title != null && !box.comments) ls += layout(box.title, tp(plex700, 11f), colW)
            box.items.forEach { (k, it) ->
                ls += if (box.comments) layout(a.inputs[k].orEmpty().ifBlank { " " }, tp(plex400, 11f), colW)
                else layout(fpItemText(k, it, a), tp(plex400, 11f), colW, spacing = 1.15f)
            }
            if (box.comments) ls.add(0, layout(box.title.orEmpty(), tp(plex700, 11f), colW))
            ls
        }
        var h = cols.maxOf { c -> c.sumOf { it.height + 3 }.toFloat() } + 14f
        if (boxes.first().comments) h = maxOf(h, 70f)
        val draw: (Float) -> Unit = { top ->
            val r = RectF(PADX, top, PADX + CW, top + h)
            if (boxes.first().sup) cv.drawRect(r, fill(Color.parseColor("#ECECEC")))
            cv.drawRect(r, stroke(FP_EDGE, 1f))
            cols.forEachIndexed { i, c ->
                var ty = top + 7f; val x = PADX + 10f + i * (colW + gap)
                c.forEach { l -> cv.drawLayout(l, x, ty); ty += l.height + 3f }
            }
        }
        return h to draw
    }

    private fun fpBand(title: String, note: String?) {
        val t = layout(title, tp(archivo800, 14f, Color.parseColor("#111111")), CW - 20f)
        val n = note?.let { layout(it, tp(plex400, 10f, Color.parseColor("#111111")), CW - 20f) }
        val h = t.height + (n?.height ?: 0) + 12f
        ensure(h + 60f)
        val r = RectF(PADX, y, PADX + CW, y + h)
        cv.drawRect(r, fill(Color.parseColor("#AAA5A1"))); cv.drawRect(r, stroke(FP_EDGE, 1f))
        cv.drawLayout(t, PADX + 10f, y + 6f); n?.let { cv.drawLayout(it, PADX + 10f, y + 6f + t.height) }
        y += h
    }

    private fun fourPointForm() {
        pageHeader = { runningHeader() }
        val secs = formSections()
        secs.forEachIndexed { si, section ->
            val def = b.defs[baseName(section)] ?: return@forEachIndexed
            val a = b.answers[section] ?: SectionAnswers()
            // group items into boxes at each header band
            val boxes = mutableListOf<FpBox>()
            var title: String? = null; var items = mutableListOf<Pair<String, ItemDef>>()
            ChecklistEngine.keyed(def.items).forEach { (k, it) ->
                if (k == null) { if (items.isNotEmpty() || title != null) boxes += FpBox(title, items); title = it.header; items = mutableListOf() }
                else items += k to it
            }
            if (items.isNotEmpty() || title != null) boxes += FpBox(title, items)
            // side-by-side pairs (Main / Second panel, Predominant / Secondary roof): identical question lists
            val rows = mutableListOf<List<FpBox>>()
            var i = 0
            while (i < boxes.size) {
                val nx = boxes.getOrNull(i + 1)
                if (nx != null && boxes[i].items.isNotEmpty() && boxes[i].items.map { it.second.q } == nx.items.map { it.second.q }) { rows += listOf(boxes[i], nx); i += 2 }
                else { rows += listOf(boxes[i]); i++ }
            }
            val measured = rows.map { fpMeasure(it, a) }
            val bandTitle = section.substringAfter("— ")
            // The paper form keeps the certification with the last system, and prints Plumbing under HVAC.
            val total = measured.sumOf { it.first.toDouble() }.toFloat() + 40f + (if (si == secs.lastIndex) CERT_H + 12f else 0f)
            val sharesPage = bandTitle.contains("Plumbing", true)
            if (si == 0 || !sharesPage || y + total > BOTTOM) startPage() else y += 12f
            fpBand(bandTitle, if (bandTitle.contains("Electrical", true)) "Separate documentation of any aluminum wiring remediation must be provided and certified by a licensed electrician." else null)
            measured.forEach { (h, draw) ->
                if (y + h > BOTTOM) { startPage(); fpBand("$bandTitle (continued)", null) }
                draw(y); y += h
            }
        }
        fpCertification()
    }

    private fun fpCertification() {
        val sel = b.inspection.selections
        val cells = listOf(
            company.inspectorName to "Inspector Signature", "Home Inspector" to "Title", inspectorLicense() to "License Number",
            Fmt.slash(sel.date) to "Date", company.name to "Company Name", "Home Inspector" to "License Type", company.phone to "Work Phone",
        )
        val cellW = (CW - 20f - 3 * 14f) / 4
        val h = CERT_H
        ensure(h + 12f)
        y += 12f
        val r = RectF(PADX, y, PADX + CW, y + h)
        cv.drawRect(r, stroke(FP_EDGE, 1f))
        cv.drawText("I certify that the above statements are true and correct.", PADX + 10f, y + 18f,
            tp(Typeface.create(plex400, Typeface.ITALIC), 11f, INK))
        cells.forEachIndexed { i, (v, l) ->
            val cx = PADX + 10f + (i % 4) * (cellW + 14f); val cy = y + 30f + (i / 4) * 44f
            var t = v; val vp = tp(plex600, 11.5f, INK)
            while (t.isNotEmpty() && vp.measureText(t) > cellW) t = t.dropLast(1)
            cv.drawText(t, cx, cy + 12f, vp)
            cv.drawRect(cx, cy + 20f, cx + cellW, cy + 21f, fill(Color.parseColor("#333333")))
            cv.drawText(l, cx, cy + 33f, tp(plex400, 10f, INK2))
        }
        y += h
    }

    // ================================================================== form reports (data v1.9 `formReports`, client Oct 17 item 13)

    /** Footer drawn by [finishPage] instead of the running footer while form pages are being written. */
    private var pageFooter: (() -> Unit)? = null
    /** Pages each form section took in the first pass ("Page X of N"); kept across the two render passes. */
    private val formPageCounts = HashMap<String, Int>()

    /** True when the standard report includes a section printed as a form (needs the counting pass). */
    private fun hasFormSections(): Boolean = layoutKind == ChecklistConfig.LAYOUT_STANDARD &&
        b.inspection.leafSections.any { b.status(it) == SecStatus.DONE && b.defs[baseName(it)]?.formReport != null }

    /** A form section's answers by question text (first occurrence), honoring `visibleIf`. */
    private inner class FormAnswers(section: String) {
        val a: SectionAnswers = b.answers[section] ?: SectionAnswers()
        private val def = b.defs[baseName(section)]
        val keyed = if (def == null) emptyList() else ChecklistEngine.keyed(ChecklistEngine.itemsFor(def, ChecklistEngine.effectiveDepth(def, b.inspection.selections.depth)))
        private val byQ = keyed.filter { it.first != null }.groupBy { it.second.q.orEmpty() }.mapValues { it.value.first() }
        fun item(q: String): ItemDef? = byQ[q]?.second
        private fun visible(q: String): Boolean = byQ[q]?.let { ChecklistEngine.isVisible(it.second, keyed, a) } ?: false
        /** Text / number / date ("MM/DD/YYYY") answer, or "" when unanswered or hidden. */
        fun v(q: String): String {
            val (k, it) = byQ[q] ?: return ""
            if (!visible(q)) return ""
            val raw = a.inputs[k!!].orEmpty().trim()
            return when (it.type) { "date" -> if (raw.isBlank()) "" else Fmt.slash(raw); "single", "multi" -> a.values[k].orEmpty().joinToString(", "); ItemDef.TYPE_COUNT_CHOICE -> com.vims.app.data.CountChoice.text(a, k); else -> raw }
        }
        /** Chip answers of a single / multi item (empty when hidden). */
        fun sel(q: String): List<String> { val (k, _) = byQ[q] ?: return emptyList(); return if (visible(q)) a.values[k!!].orEmpty() else emptyList() }
        /** Index of the chosen option of a single item, or -1. */
        fun idx(q: String): Int = sel(q).firstOrNull()?.let { s -> item(q)?.options.orEmpty().indexOf(s) } ?: -1
        fun on(q: String, option: String): Boolean = sel(q).any { it.equals(option, ignoreCase = true) }
    }

    private val formSerif: Typeface = Typeface.create(Typeface.SERIF, Typeface.NORMAL)
    private val formSerifBold: Typeface = Typeface.create(Typeface.SERIF, Typeface.BOLD)
    private val formSerifItalic: Typeface = Typeface.create(Typeface.SERIF, Typeface.ITALIC)

    /**
     * Mini markup for form text: **bold**, __underline__, //italic//, {question} = that answer underlined (or a blank line
     * "________" when unanswered), {=text} = a filled value given inline.
     */
    private fun formText(markup: String, fa: FormAnswers?, valueColor: Int = BRAND_DEEP): CharSequence {
        val sb = android.text.SpannableStringBuilder()
        var bold = -1; var under = -1; var ital = -1
        var i = 0
        while (i < markup.length) {
            when {
                // A run of 3+ underscores is a blank line to write on, not an underline marker.
                markup.startsWith("___", i) -> { var j = i; while (j < markup.length && markup[j] == '_') j++; sb.append(markup, i, j); i = j }
                markup.startsWith("**", i) -> { if (bold < 0) bold = sb.length else { sb.setSpan(android.text.style.StyleSpan(Typeface.BOLD), bold, sb.length, 0); bold = -1 }; i += 2 }
                markup.startsWith("__", i) -> { if (under < 0) under = sb.length else { sb.setSpan(android.text.style.UnderlineSpan(), under, sb.length, 0); under = -1 }; i += 2 }
                markup.startsWith("//", i) -> { if (ital < 0) ital = sb.length else { sb.setSpan(android.text.style.StyleSpan(Typeface.ITALIC), ital, sb.length, 0); ital = -1 }; i += 2 }
                markup[i] == '{' && markup.indexOf('}', i) > i -> {
                    val end = markup.indexOf('}', i)
                    val key = markup.substring(i + 1, end)
                    val v = if (key.startsWith("=")) key.drop(1) else fa?.v(key).orEmpty()
                    if (v.isBlank()) sb.append("__________") else {
                        val st = sb.length; sb.append(" $v ")
                        sb.setSpan(android.text.style.UnderlineSpan(), st, sb.length, 0)
                        sb.setSpan(android.text.style.ForegroundColorSpan(valueColor), st, sb.length, 0)
                        sb.setSpan(android.text.style.TypefaceSpan(plex600), st, sb.length, 0)
                    }
                    i = end + 1
                }
                else -> { sb.append(markup[i]); i++ }
            }
        }
        return sb
    }

    /** A ☐ / ☒ box drawn as vector lines (not a font glyph), top-left at (x, top). */
    private fun checkBox(x: Float, top: Float, on: Boolean, size: Float = 11f) {
        cv.drawRect(x, top, x + size, top + size, stroke(Color.BLACK, 1f))
        if (on) {
            val p = stroke(BRAND_DEEP, 1.8f)
            cv.drawLine(x + 2f, top + 2f, x + size - 2f, top + size - 2f, p); cv.drawLine(x + size - 2f, top + 2f, x + 2f, top + size - 2f, p)
        }
    }

    // ---------------------------------------------------------------- OIR-B1-1802 (Wind Mitigation), Florida state form (public)

    private fun fp(size: Float = BODY, tf: Typeface = formSerif, color: Int = Color.BLACK) = tp(tf, size, color)

    private fun formEnsure(h: Float) { if (y + h > F_BOTTOM) { startPage(header = false); y = 52f } }

    /** Paragraph across the form width (wraps; moves to the next page whole when it doesn't fit). */
    private fun fpara(markup: String, fa: FormAnswers?, x: Float = FX, w: Float = FW, size: Float = BODY, tf: Typeface = formSerif, gapAfter: Float = 6f, align: Layout.Alignment = Layout.Alignment.ALIGN_NORMAL) {
        val l = layout(formText(markup, fa), fp(size, tf), w, align, 1.03f)
        formEnsure(l.height.toFloat())
        cv.drawLayout(l, x, y)
        y += l.height + gapAfter
    }

    /** One ☐/☒ answer: box at [indent], wrapped text beside it. */
    private fun fopt(on: Boolean, markup: String, fa: FormAnswers?, indent: Float = 26f, size: Float = BODY, keep: Float = 0f) {
        val tx = FX + indent + 20f
        val l = layout(formText(markup, fa), fp(size), FW - (tx - FX), Layout.Alignment.ALIGN_NORMAL, 1.02f)
        formEnsure(l.height + keep)
        checkBox(FX + indent, y + size * .12f, on, 10f)
        cv.drawLayout(l, tx, y)
        y += l.height + 3.5f
    }

    /** "1. **__Building Code__**: question" heading with a hanging number. */
    private fun fq(num: String, markup: String, fa: FormAnswers?, keep: Float = 60f) {
        y += 4f
        val l = layout(formText(markup, fa), fp(), FW - 26f, Layout.Alignment.ALIGN_NORMAL, 1.02f)
        formEnsure(l.height + keep)
        cv.drawText(num, FX, y + BODY * .95f, fp())
        cv.drawLayout(l, FX + 26f, y)
        y += l.height + 4f
    }

    /** OIR-B1-1802 page footer: initials + property address (filled), validity note, form id and "Page X of N". */
    private fun oirFooter(start: Int, section: String, initials: String) {
        val sel = b.inspection.selections
        var fy = 978f
        val bold = fp(13f, formSerifBold)
        val lead = "Inspectors Initials "
        cv.drawText(lead, FX + 10f, fy, bold)
        var x = FX + 10f + bold.measureText(lead)
        val vp = tp(plex600, 12.5f, BRAND_DEEP)
        val iw = maxOf(60f, vp.measureText(initials) + 16f)
        cv.drawText(initials, x + 8f, fy - 1f, vp); cv.drawRect(x, fy + 3f, x + iw, fy + 4f, fill(Color.BLACK)); x += iw + 10f
        cv.drawText("Property Address", x, fy, bold); x += bold.measureText("Property Address") + 4f
        val addr = listOf(sel.street, sel.cityLine).filter { it.isNotBlank() }.joinToString(", ")
        cv.drawText(ellipsize(addr, vp, FX + FW - 30f - x - 8f), x + 8f, fy - 1f, vp); cv.drawRect(x, fy + 3f, FX + FW - 30f, fy + 4f, fill(Color.BLACK))
        fy += 14f
        val v = layout(VALID, fp(12.5f, formSerifBold), FW - 20f)
        cv.drawLayout(v, FX + 10f, fy); fy += v.height + 13f
        cv.drawText(FORM_ID, FX + 10f, fy, fp(12.5f, formSerifBold))
        val total = formPageCounts[section]?.let { " of $it" }.orEmpty()
        cv.drawText("Page ${pageNo - start + 1}$total", FX + FW - 60f, fy, fp(13f, formSerifItalic).apply { textAlign = Paint.Align.RIGHT })
    }

    /** Florida Uniform Mitigation Verification Inspection Form (OIR-B1-1802) for the Wind Mitigation section. */
    private fun oirForm(section: String) {
        val fa = FormAnswers(section)
        val sel = b.inspection.selections
        val initials = fa.v("Inspector initials")
        startPage(header = false)
        val start = pageNo
        pageFooter = { oirFooter(start, section, initials) }
        y = 44f
        cv.drawText("Uniform Mitigation Verification Inspection Form", PW / 2, y + 20f, fp(22f, formSerifBold).apply { textAlign = Paint.Align.CENTER })
        y += 28f
        val sub = "Maintain a copy of this form and any documentation provided with the insurance policy"
        val sp = fp(15f).apply { textAlign = Paint.Align.CENTER; isUnderlineText = true }
        cv.drawText(sub, PW / 2, y + 14f, sp)
        y += 24f

        // Owner Information grid
        val c1 = FX; val c2 = FX + FW * .33f; val c3 = FX + FW * .665f; val c4 = FX + FW
        val rowH = 21f
        fun cell(x0: Float, x1: Float, label: String, value: String, boldLabel: Boolean = false) {
            cv.drawRect(x0, y, x1, y + rowH, stroke(Color.BLACK, 1f))
            val lp = fp(13.5f, if (boldLabel) formSerifBold else formSerif)
            cv.drawText(label, x0 + 8f, y + 16.5f, lp)
            if (value.isNotBlank()) {
                val vx = x0 + 8f + lp.measureText(label) + 6f
                val vp = tp(plex600, 12.5f, BRAND_DEEP)
                cv.drawText(ellipsize(value, vp, x1 - vx - 6f), vx, y + 16.5f, vp)
            }
        }
        cell(c1, c4, "Inspection Date:", Fmt.slash(sel.date)); y += rowH
        cell(c1, c4, "Owner Information", "", boldLabel = true); y += rowH
        cell(c1, c3, "Owner Name:", fa.v("Owner name")); cell(c3, c4, "Contact Person:", fa.v("Contact person")); y += rowH
        cell(c1, c3, "Address:", fa.v("Address")); cell(c3, c4, "Home Phone:", fa.v("Home phone")); y += rowH
        cell(c1, c2, "City:", fa.v("City")); cell(c2, c3, "Zip:", fa.v("Zip")); cell(c3, c4, "Work Phone:", fa.v("Work phone")); y += rowH
        cell(c1, c2, "County:", fa.v("County")); cell(c2, c3, "", ""); cell(c3, c4, "Cell Phone:", fa.v("Cell phone")); y += rowH
        cell(c1, c3, "Insurance Company:", fa.v("Insurance company")); cell(c3, c4, "Policy #:", fa.v("Policy #")); y += rowH
        cell(c1, c2, "Year of Home:", fa.v("Year of home")); cell(c2, c3, "# of Stories:", fa.v("# of stories")); cell(c3, c4, "Email:", fa.v("Email")); y += rowH
        y += 10f
        fpara(NOTE, null, size = 12.4f)

        // 1. Building Code
        fq("1.", "**__Building Code__**:  Was the structure built in compliance with the Florida Building Code (FBC 2001 or later) OR for homes located in the HVHZ (Miami-Dade or Broward counties), South Florida Building Code (SFBC-94)?", fa)
        val q1 = fa.idx("Building code")
        Q1.forEachIndexed { i, t -> fopt(q1 == i, t, fa) }

        // 2. Roof Covering
        fq("2.", "**__Roof Covering:__** Select all roof covering types in use. Provide the permit application date OR FBC/MDC Product Approval number OR Year of Original Installation/Replacement OR indicate that no information was available to verify compliance for each roof covering identified.", fa, keep = 200f)
        roofCoveringTable(fa)
        val q2 = fa.idx("Roof covering compliance")
        Q2.forEachIndexed { i, t -> fopt(q2 == i, t, fa) }

        // 3. Roof Deck Attachment
        fq("3.", "**__Roof Deck Attachment__**: What is the __**weakest**__ form of roof deck attachment?", fa)
        val q3 = fa.idx("Roof deck attachment")
        Q3.forEachIndexed { i, t -> fopt(q3 == i, t, fa) }

        // 4. Roof to Wall Attachment
        fq("4.", "**__Roof to Wall Attachment__**: What is the __**WEAKEST**__ roof to wall connection? (Do not include attachment of hip/valley jacks within 5 feet of the inside or outside corner of the roof in determination of WEAKEST type)", fa)
        val q4 = fa.idx("Roof to wall attachment")
        fun subs(texts: List<String>, q: String, indent: Float = 52f) {
            val opts = fa.item(q)?.options.orEmpty()
            texts.forEachIndexed { i, t -> fopt(opts.getOrNull(i)?.let { fa.on(q, it) } == true, t, fa, indent, SMALL + 1f) }
        }
        Q4.forEachIndexed { i, t ->
            fopt(q4 == i, t, fa, keep = if (i == 0 || i == 1 || i == 3) 40f else 0f)
            when (i) {
                0 -> {
                    subs(Q4_TOE, "Toe nails — type")
                    fpara("Minimal conditions to qualify for categories B, C, or D. All visible metal connectors are:", fa, x = FX + 46f, w = FW - 46f, size = SMALL + 1f, gapAfter = 4f)
                    subs(Q4_MIN, "Minimal conditions for B, C or D (all visible metal connectors are)")
                }
                1 -> subs(Q4_CLIPS, "Clips — type")
                3 -> subs(Q4_DOUBLE, "Double wraps — type")
            }
        }

        // 5. Roof Geometry
        fq("5.", "**__Roof Geometry__**: What is the roof shape? (Do not consider roofs of porches or carports that are attached only to the fascia or wall of the host structure over unenclosed space in the determination of roof perimeter or roof area for roof geometry classification).", fa)
        val q5 = fa.idx("Roof geometry")
        Q5.forEachIndexed { i, t -> fopt(q5 == i, t, fa) }

        // 6. Secondary Water Resistance
        fq("6.", "**__Secondary Water Resistance (SWR)__**: (standard underlayments or hot-mopped felts do not qualify as an SWR)", fa)
        val q6 = fa.idx("Secondary water resistance")
        Q6.forEachIndexed { i, t -> fopt(q6 == i, t, fa) }

        // 7. Opening Protection (the chart is kept with the question)
        fq("7.", "**__Opening Protection__:** What is the **__weakest__** form of wind borne debris protection installed on the structure? **First**, use the table to determine the weakest form of protection for each category of opening. **Second**, (a) check one answer below (A, B, C, N, or X) based upon the lowest protection level for ALL Glazed openings **and** (b) check the protection level for all Non-Glazed openings (.1, .2, or .3) as applicable.", fa, keep = 320f)
        openingChart(fa)
        val weakest = fa.sel("Opening protection (weakest)").firstOrNull().orEmpty()
        Q7.forEach { (letter, text, subList) ->
            fopt(weakest == letter || weakest.startsWith("$letter."), text, fa, indent = 18f, keep = 50f)
            subList.forEach { t -> fopt(weakest == t.substringBefore(' '), t, fa, indent = 40f, size = SMALL + 1f) }
            y += 4f
        }

        // Qualified inspector block
        y += 6f
        formEnsure(140f)
        run {
            val top = y
            val hp = fp(15f, Typeface.create(formSerif, Typeface.BOLD_ITALIC)).apply { textAlign = Paint.Align.CENTER }
            cv.drawText("MITIGATION INSPECTIONS MUST BE CERTIFIED BY A QUALIFIED INSPECTOR.", PW / 2, y + 19f, hp)
            cv.drawText("Section 627.711(2), Florida Statutes, provides a listing of individuals who may sign this form.", PW / 2, y + 38f, fp(13.5f, Typeface.create(formSerif, Typeface.BOLD_ITALIC)).apply { textAlign = Paint.Align.CENTER })
            y += 46f
            val ch = 36f
            fun icell(x0: Float, x1: Float, label: String, value: String) {
                cv.drawRect(x0, y, x1, y + ch, stroke(Color.BLACK, 1f))
                cv.drawText(label, x0 + 8f, y + 13f, fp(11.5f))
                if (value.isNotBlank()) { val vp = tp(plex600, 12.5f, BRAND_DEEP); cv.drawText(ellipsize(value, vp, x1 - x0 - 16f), x0 + 8f, y + 29f, vp) }
            }
            icell(FX, FX + FW * .46f, "Qualified Inspector Name:", company.inspectorName)
            icell(FX + FW * .46f, FX + FW * .73f, "License Type:", fa.v("License type"))
            icell(FX + FW * .73f, FX + FW, "License or Certificate #:", inspectorLicense())
            y += ch
            icell(FX, FX + FW * .665f, "Inspection Company:", company.name)
            icell(FX + FW * .665f, FX + FW, "Phone:", com.vims.app.util.formatPhone(company.phone.filter { it.isDigit() }).ifBlank { company.phone })
            y += ch
            cv.drawRect(FX, top, FX + FW, y, stroke(Color.BLACK, 1.2f))
            y += 12f
        }
        fpara("**__Qualified Inspector – I hold an active license as a__: (check one)**", fa, size = 17f, gapAfter = 6f)
        val lic = fa.idx("I hold an active license as a")
        LICENSES.forEachIndexed { i, t -> fopt(lic == i, t, fa, indent = 4f, size = SMALL + 1f) }
        y += 4f
        boxed {
            fpara(CERT_EMPLOYEES, fa, x = FX + 10f, w = FW - 20f, size = 12.2f)
            fpara("**I, {=${company.inspectorName}} am a qualified inspector and I personally performed the inspection or (//licensed contractors and professional engineers only//) I had my employee (__________________) perform the inspection and I agree to be responsible for his/her work.**", fa, x = FX + 10f, w = FW - 20f, size = 12.6f)
            fpara("**Qualified Inspector Signature: ________________________________  Date: __________________**", fa, x = FX + 10f, w = FW - 20f, size = 13.5f, gapAfter = 10f)
            fpara(FRAUD, fa, x = FX + 10f, w = FW - 20f, size = 12.2f)
        }
        boxed {
            fpara("**__Homeowner to complete__:** I certify that the named Qualified Inspector or his or her employee did perform an inspection of the residence identified on this form and that proof of identification was provided to me or my Authorized Representative.", fa, x = FX + 10f, w = FW - 20f, size = 12.6f)
            fpara("**Signature: ________________________________  Date: ____________________**", fa, x = FX + 10f, w = FW - 20f, size = 14f, gapAfter = 8f)
        }
        boxed { fpara(MISDEMEANOR, fa, x = FX + 10f, w = FW - 20f, size = 12.2f) }
        y += 4f
        fpara(DEFINITIONS, fa, size = 12.2f)
        finishPage()
        pageFooter = null
        formPageCounts[section] = pageNo - start + 1
    }

    /** Draws [content] and a rectangle around it (the official form's boxed paragraphs); moves to a new page first if needed. */
    private fun boxed(content: () -> Unit) {
        formEnsure(90f)
        val top = y; val startPageNo = pageNo
        y += 6f
        content()
        if (pageNo == startPageNo) cv.drawRect(FX, top, FX + FW, y + 2f, stroke(Color.BLACK, 1f))
        y += 7f
    }

    /** Q2 roof covering table: type | permit application date | FBC or MDC product approval # | year installed | no information. */
    private fun roofCoveringTable(fa: FormAnswers) {
        val types = fa.item("Roof covering types in use")?.options.orEmpty().ifEmpty { listOf("Asphalt/Fiberglass Shingle", "Concrete/Clay Tile", "Metal", "Built Up", "Membrane", "Other") }
        val xs = floatArrayOf(FX + 46f, FX + FW * .29f, FX + FW * .46f, FX + FW * .64f, FX + FW * .83f)
        val ws = floatArrayOf(0f, FW * .14f, FW * .16f, FW * .14f, 0f)
        val hp = fp(11f, formSerifBold).apply { textAlign = Paint.Align.CENTER }
        formEnsure(40f + types.size * 26f)
        cv.drawText("2.1 Roof Covering Type:", xs[0], y + 38f, fp(11f, formSerifBold))
        listOf("Permit Application\nDate", "FBC or MDC\nProduct Approval #", "Year of Original\nInstallation or\nReplacement", "No Information\nProvided for\nCompliance").forEachIndexed { i, h ->
            val lines = h.split("\n"); val cx = if (i == 3) xs[4] + 7f else xs[i + 1] + ws[i + 1] / 2
            lines.forEachIndexed { li, t -> cv.drawText(t, cx, y + 38f - (lines.size - 1 - li) * 12f, hp) }
        }
        y += 50f
        val vp = tp(plex600, 12f, BRAND_DEEP)
        fun blank(x: Float, w: Float, v: String) {
            cv.drawRect(x, y + 15f, x + w, y + 16f, fill(Color.BLACK))
            if (v.isNotBlank()) cv.drawText(ellipsize(v, vp, w), x + w / 2, y + 12f, vp.apply { textAlign = Paint.Align.CENTER })
        }
        types.forEachIndexed { i, t ->
            val on = fa.on("Roof covering types in use", t)
            checkBox(xs[0], y + 3f, on)
            val label = "${i + 1}. $t"
            val lp = fp(11.5f)
            cv.drawText(label, xs[0] + 18f, y + 13f, lp)
            if (t == "Other") {
                val ox = xs[0] + 18f + lp.measureText(label) + 2f
                blank(ox, xs[1] - ox - 14f, fa.v("Other roof covering type"))
            }
            blank(xs[1], ws[1], fa.v("$t: permit application date"))
            blank(xs[2], ws[2], fa.v("$t: FBC or MDC product approval #"))
            blank(xs[3], ws[3], fa.v("$t: year of original installation or replacement"))
            checkBox(xs[4] + 1f, y + 3f, fa.on("$t: no information provided for compliance", "Yes"))
            y += 22f
        }
        y += 4f
    }

    /** Q7 Opening Protection Level Chart with an X in each opening type's column at its chosen level (D is grayed for glazed openings). */
    private fun openingChart(fa: FormAnswers) {
        val cols = fa.keyed.filter { it.first != null && it.second.formTable == "q7" }.map { it.second.q.orEmpty() }
        val leftW = FW * .56f
        val glazedW = (FW - leftW - 8f) * .68f; val nonW = FW - leftW - 8f - glazedW
        val colX = FloatArray(6); val colW = FloatArray(6)
        for (i in 0 until 4) { colW[i] = glazedW / 4; colX[i] = FX + leftW + i * colW[i] }
        for (i in 0 until 2) { colW[4 + i] = nonW / 2; colX[4 + i] = FX + leftW + glazedW + 8f + i * colW[4 + i] }
        val headH = 104f
        val rowHs = Q7_ROWS.map { (_, d) -> layout(d, tp(plex400, 10.5f), leftW - 52f).height + 10f }
        formEnsure(headH + rowHs.sum() + 10f)
        val top = y
        val edge = stroke(Color.BLACK, 1f); val heavy = stroke(Color.BLACK, 2.6f)
        // header: title + instruction (left), column groups and names (right)
        cv.drawText("Opening Protection Level Chart", FX + 8f, y + 22f, tp(plex700, 17f, Color.BLACK))
        cv.drawLayout(layout("Place an “X” in each row to identify all forms of protection in use for each opening type. Check only one answer below (A thru X), based on the weakest form of protection (lowest row) for any of the Glazed openings and indicate the weakest form of protection (lowest row) for Non-Glazed openings.",
            tp(plex700, 10.5f, Color.BLACK), leftW - 14f), FX + 8f, y + 30f)
        val gp = tp(plex700, 10.5f, Color.BLACK).apply { textAlign = Paint.Align.CENTER }
        cv.drawText("Glazed Openings", colX[0] + glazedW / 2, y + 24f, gp)
        cv.drawText("Non-Glazed", colX[4] + nonW / 2, y + 17f, gp); cv.drawText("Openings", colX[4] + nonW / 2, y + 30f, gp)
        val names = listOf("Windows\nor Entry\nDoors", "Garage\nDoors", "Skylights", "Glass\nBlock", "Entry\nDoors", "Garage\nDoors")
        names.forEachIndexed { i, n ->
            val ls = n.split("\n"); val cy = y + 40f + (64f - ls.size * 13f) / 2 + 10f
            ls.forEachIndexed { li, t -> cv.drawText(t, colX[i] + colW[i] / 2, cy + li * 13f, gp) }
            cv.drawRect(colX[i], y + 38f, colX[i] + colW[i], y + headH, edge)
        }
        cv.drawRect(colX[0], y, colX[0] + glazedW, y + 38f, edge); cv.drawRect(colX[4], y, colX[4] + nonW, y + 38f, edge)
        y += headH
        Q7_ROWS.forEachIndexed { r, (code, desc) ->
            val h = rowHs[r]
            cv.drawRect(FX, y, FX + 44f, y + h, edge); cv.drawRect(FX + 44f, y, FX + leftW, y + h, edge)
            cv.drawText(code, FX + 22f, y + h / 2 + 4f, tp(plex700, 11f, Color.BLACK).apply { textAlign = Paint.Align.CENTER })
            cv.drawLayout(layout(desc, tp(plex400, 10.5f, Color.BLACK), leftW - 52f), FX + 50f, y + 5f)
            for (i in 0 until 6) {
                val cell = RectF(colX[i], y, colX[i] + colW[i], y + h)
                if (code == "D" && i < 4) cv.drawRect(cell, fill(Color.parseColor("#8C8C8C")))
                cv.drawRect(cell, edge)
                val q = cols.getOrNull(i) ?: continue
                if (fa.on(q, code)) cv.drawText("X", cell.centerX(), cell.centerY() + 6f, tp(plex700, 16f, BRAND_DEEP).apply { textAlign = Paint.Align.CENTER })
            }
            y += h
        }
        cv.drawRect(FX, top, FX + leftW, y, heavy); cv.drawRect(colX[0], top, colX[0] + glazedW, y, heavy); cv.drawRect(colX[4], top, colX[4] + nonW, y, heavy)
        y += 12f
    }

    // ---------------------------------------------------------------- Wood Destroying Insect report (our own layout; NPMA-33 is copyrighted)

    /**
     * Wood Destroying Insect Inspection Report (formReports.wdi): the client's NPMA-33 data in VIMS report styling — Section I
     * general information, II findings (☐/☒ A or B + descriptions, previous treatment), III recommendations, IV obstructions,
     * V comments, blank signature lines and a neutral scope line. Not a copy of the NPMA-33 form, its text or marks.
     */
    private fun wdiReport(section: String) {
        val fa = FormAnswers(section)
        val sel = b.inspection.selections
        startPage()
        title("Wood Destroying Insect Inspection Report", listOf(sel.street, sel.cityLine).filter { it.isNotBlank() }.joinToString(", ") + " · " + Fmt.date(sel.date))
        fun head(t: String) { ensure(60f); y += 4f; val h = 24f
            cv.drawRoundRect(RectF(PADX, y, PADX + CW, y + h), 6f, 6f, fill(PAPER2)); cv.drawRect(PADX, y, PADX + 3f, y + h, fill(BRAND))
            cv.drawText(t, PADX + 11f, y + 16.5f, tp(archivo700, 12f, BRAND_DEEP)); y += h + 6f }
        fun opt(on: Boolean, text: CharSequence, indent: Float = 6f) {
            val l = layout(text, tp(plex400, 12.5f, INK), CW - indent - 22f)
            ensure(l.height + 6f)
            checkBox(PADX + indent, y + 3f, on, 12f)
            cv.drawLayout(l, PADX + indent + 22f, y); y += l.height + 4f
        }
        fun kv(k: String, v: String, indent: Float = 28f) {
            val kl = layout(k, tp(plex400, 12f, INK3), CW * .45f - indent); val vl = layout(v.ifBlank { "—" }, tp(plex600, 12.5f, INK), CW * .55f - 8f)
            val h = maxOf(kl.height, vl.height) + 6f; ensure(h)
            cv.drawLayout(kl, PADX + indent, y + 3f); cv.drawLayout(vl, PADX + CW * .45f + 8f, y + 3f)
            cv.drawRect(PADX + indent, y + h - 1f, PADX + CW, y + h, fill(LINE2)); y += h
        }
        head("Section I. General Information")
        infoGrid(listOf(
            "Inspection company" to company.name, "Company address" to company.address,
            "Company phone" to com.vims.app.util.formatPhone(company.phone.filter { it.isDigit() }).ifBlank { company.phone }, "Company business license no." to fa.v("Company business license no."),
            "Inspector" to company.inspectorName, "Inspector license #" to inspectorLicense(),
            "Date of inspection" to Fmt.slash(sel.date), "Structure(s) inspected" to fa.v("Structure(s) inspected"),
        ), compact = true)
        kv("Address of property inspected", listOf(sel.street, sel.cityLine).filter { it.isNotBlank() }.joinToString(", "), indent = 0f)
        head("Section II. Inspection Findings")
        val findings = fa.item("Findings")?.options.orEmpty()
        findings.forEachIndexed { i, o -> opt(fa.on("Findings", o), o) }
        val boxB = findings.getOrNull(1)?.let { fa.on("Findings", it) } == true
        listOf("1. Live insects (description and location)", "2. Dead insects, insect parts, frass, shelter tubes, exit holes, or staining (description and location)",
            "3. Visible damage from wood destroying insects (description and location)").forEach { q -> kv(q, if (boxB) fa.v(q) else "") }
        y += 6f
        val prev = "Structure(s) appear to have been previously treated"
        ensure(40f)
        cv.drawText("Structure(s) appear to have been previously treated:", PADX + 6f, y + 13f, tp(plex600, 12.5f, INK))
        var px = PADX + 6f + tp(plex600, 12.5f).measureText("Structure(s) appear to have been previously treated:") + 14f
        listOf("Yes", "No").forEach { o -> checkBox(px, y + 3f, fa.on(prev, o), 12f); cv.drawText(o, px + 18f, y + 13f, tp(plex400, 12.5f, INK)); px += 60f }
        y += 22f
        kv("Visible evidence of possible previous treatment", fa.v("Visible evidence of possible previous treatment"))
        head("Section III. Recommendations")
        fa.item("Recommendation")?.options.orEmpty().forEach { o -> opt(fa.on("Recommendation", o), o) }
        fa.v("Explanation (required if Section II box B is checked)").takeIf { it.isNotBlank() }?.let { kv("Explanation", it) }
        fa.v("Recommend treatment for the control of").takeIf { it.isNotBlank() }?.let { kv("Recommend treatment for the control of", it) }
        head("Section IV. Obstructions and Inaccessible Areas")
        val areas = fa.keyed.filter { it.first != null && it.second.q.orEmpty().endsWith("— obstructed or inaccessible") }.map { it.second.q.orEmpty() }
        // Areas with an obstruction, then one line naming the areas without any (keeps the report to one page).
        val (blocked, clear) = areas.partition { fa.v(it).isNotBlank() }
        if (blocked.isNotEmpty()) infoGrid(blocked.map { q -> q.substringBefore(" —") to fa.v(q) }, compact = true)
        if (clear.isNotEmpty()) kv(if (blocked.isEmpty()) "Obstructed or inaccessible areas" else "No obstructions observed", if (blocked.isEmpty()) "None observed" else clear.joinToString(", ") { it.substringBefore(" —") }, indent = 0f)
        head("Section V. Additional Comments and Attachments")
        kv("Additional comments", fa.v("Additional comments"), indent = 6f)
        kv("Attachments", fa.v("Attachments"), indent = 6f)
        // Signature lines (left blank) + scope line.
        ensure(90f)
        y += 8f
        val sp = tp(plex400, 11.5f, INK2)
        listOf("Signature of seller(s) or owner(s) if refinancing" to PADX, "Buyer’s signature" to PADX + CW / 2 + 10f).forEach { (t, x) ->
            cv.drawRect(x, y + 22f, x + CW / 2 - 30f, y + 23f, fill(INK)); cv.drawText(t, x, y + 38f, sp)
            cv.drawText("Date", x + CW / 2 - 70f, y + 38f, sp)
        }
        y += 46f
        val l = layout("This report reflects a visual inspection of readily accessible areas on the date of inspection and is not a guarantee or warranty against latent, concealed or future infestations or damage.",
            tp(Typeface.create(plex400, Typeface.ITALIC), 11.5f, INK3), CW)
        ensure(l.height + 4f); cv.drawLayout(l, PADX, y); y += l.height
    }
}

/** Florida OIR-B1-1802 (Rev. 01/12) wording (state form, public) — docs/forms/oir-b1-1802.txt — and the form layout constants. */

private const val FX = 52f
private const val FW = 746f
private const val F_BOTTOM = 962f
private const val BODY = 12.9f
private const val SMALL = 11.6f
private const val NOTE = "**NOTE: Any documentation used in validating the compliance or existence of each construction or mitigation attribute must accompany this form. At least one photograph must accompany this form to validate each attribute marked in questions 3 though 7. The insurer may ask additional questions regarding the mitigated feature(s) verified on this form.**"
private val Q1 = listOf(
    "A. Built in compliance with the FBC: Year Built {Year built}. For homes built in 2002/2003 provide a permit application with a date after 3/1/2002: Building Permit Application Date (MM/DD/YYYY) {Building permit application date (FBC)}",
    "B. For the HVHZ Only: Built in compliance with the SFBC-94: Year Built {Year built (SFBC-94)}. For homes built in 1994, 1995, and 1996 provide a permit application with a date after 9/1/1994: Building Permit Application Date (MM/DD/YYYY) {Building permit application date (SFBC-94)}",
    "C. Unknown or does not meet the requirements of Answer “A” or “B”",
)
private val Q2 = listOf(
    "A. All roof coverings listed above meet the FBC with a FBC or Miami-Dade Product Approval listing current at time of installation OR have a roofing permit application date on or after 3/1/02 OR the roof is original and built in 2004 or later.",
    "B. All roof coverings have a Miami-Dade Product Approval listing current at time of installation OR (for the HVHZ only) a roofing permit application after 9/1/1994 and before 3/1/2002 OR the roof is original and built in 1997 or later.",
    "C. One or more roof coverings do not meet the requirements of Answer “A” or “B”.",
    "D. No roof coverings meet the requirements of Answer “A” or “B”.",
)
private val Q3 = listOf(
    "A. Plywood/Oriented strand board (OSB) roof sheathing attached to the roof truss/rafter (spaced a maximum of 24” inches o.c.) by staples or 6d nails spaced at 6” along the edge and 12” in the field. -OR- Batten decking supporting wood shakes or wood shingles. -OR- Any system of screws, nails, adhesives, other deck fastening system or truss/rafter spacing that has an equivalent mean uplift less than that required for Options B or C below.",
    "B. Plywood/OSB roof sheathing with a minimum thickness of 7/16”inch attached to the roof truss/rafter (spaced a maximum of 24”inches o.c.) by 8d common nails spaced a maximum of 12” inches in the field.-OR- Any system of screws, nails, adhesives, other deck fastening system or truss/rafter spacing that is shown to have an equivalent or greater resistance 8d nails spaced a maximum of 12 inches in the field or has a mean uplift resistance of at least 103 psf.",
    "C. Plywood/OSB roof sheathing with a minimum thickness of 7/16”inch attached to the roof truss/rafter (spaced a maximum of 24”inches o.c.) by 8d common nails spaced a maximum of 6” inches in the field. -OR- Dimensional lumber/Tongue & Groove decking with a minimum of 2 nails per board (or 1 nail per board if each board is equal to or less than 6 inches in width). -OR- Any system of screws, nails, adhesives, other deck fastening system or truss/rafter spacing that is shown to have an equivalent or greater resistance than 8d common nails spaced a maximum of 6 inches in the field or has a mean uplift resistance of at least 182 psf.",
    "D. Reinforced Concrete Roof Deck.",
    "E. Other: {Roof deck attachment — other}",
    "F. Unknown or unidentified.",
    "G. No attic access.",
)
private val Q4 = listOf(
    "A. Toe Nails", "B. Clips",
    "C. Single Wraps\nMetal connectors consisting of a single strap that wraps over the top of the truss/rafter and is secured with a minimum of 2 nails on the front side and a minimum of 1 nail on the opposing side.",
    "D. Double Wraps", "E. Structural Anchor bolts structurally connected or reinforced concrete roof.", "F. Other: {Roof to wall attachment — other}",
    "G. Unknown or unidentified", "H. No attic access",
)
private val Q4_TOE = listOf("Truss/rafter anchored to top plate of wall using nails driven at an angle through the truss/rafter and attached to the top plate of the wall, or",
    "Metal connectors that do not meet the minimal conditions or requirements of B, C, or D")
private val Q4_MIN = listOf("Secured to truss/rafter with a minimum of three (3) nails, and",
    "Attached to the wall top plate of the wall framing, or embedded in the bond beam, with less than a ½\" gap from the blocking or truss/rafter and blocked no more than 1.5” of the truss/rafter, and free of visible severe corrosion.")
private val Q4_CLIPS = listOf("Metal connectors that do not wrap over the top of the truss/rafter, or",
    "Metal connectors with a minimum of 1 strap that wraps over the top of the truss/rafter and does not meet the nail position requirements of C or D, but is secured with a minimum of 3 nails.")
private val Q4_DOUBLE = listOf("Metal Connectors consisting of 2 separate straps that are attached to the wall frame, or embedded in the bond beam, on either side of the truss/rafter where each strap wraps over the top of the truss/rafter and is secured with a minimum of 2 nails on the front side, and a minimum of 1 nail on the opposing side, or",
    "Metal connectors consisting of a single strap that wraps over the top of the truss/rafter, is secured to the wall on both sides, and is secured to the top plate with a minimum of three nails on each side.")
private val Q5 = listOf(
    "A. Hip Roof  Hip roof with no other roof shapes greater than 10% of the total roof system perimeter.\nTotal length of non-hip features: {Total length of non-hip features (feet)} feet; Total roof system perimeter: {Total roof system perimeter (feet)} feet",
    "B. Flat Roof  Roof on a building with 5 or more units where at least 90% of the main roof area has a roof slope of less than 2:12. Roof area with slope less than 2:12 {Roof area with slope less than 2:12 (sq ft)} sq ft; Total roof area {Total roof area (sq ft)} sq ft",
    "C. Other Roof  Any roof that does not qualify as either (A) or (B) above.",
)
private val Q6 = listOf(
    "A. SWR (also called Sealed Roof Deck) Self-adhering polymer modified-bitumen roofing underlayment applied directly to the sheathing or foam adhesive SWR barrier (not foamed-on insulation) applied as a supplemental means to protect the dwelling from water intrusion in the event of roof covering loss.",
    "B. No SWR.", "C. Unknown or undetermined.",
)
private val Q7_ROWS = listOf(
    "N/A" to "Not Applicable- there are no openings of this type on the structure",
    "A" to "Verified cyclic pressure & large missile (9-lb for windows doors/4.5 lb for skylights)",
    "B" to "Verified cyclic pressure & large missile (4-8 lb for windows doors/2 lb for skylights)",
    "C" to "Verified plywood/OSB meeting Table 1609.1.2 of the FBC 2007",
    "D" to "Verified Non-Glazed Entry or Garage doors indicating compliance with ASTM E 330, ANSI/DASMA 108, or PA/TAS 202 for wind pressure resistance",
    "N" to "Opening Protection products that appear to be A or B but are not verified\nOther protective coverings that cannot be identified as A, B, or C",
    "X" to "No Windborne Debris Protection",
)
/** Q7 answers: letter, heading + text, bullets, sub-answers (.1 / .2 / .3). */
private val Q7: List<Triple<String, String, List<String>>> = listOf(
    Triple("A", "**__A. Exterior Openings Cyclic Pressure and 9-lb Large Missile (4.5 lb for skylights only)__** All Glazed openings are protected at a minimum, with impact resistant coverings or products listed as wind borne debris protection devices in the product approval system of the State of Florida or Miami-Dade County and meet the requirements of one of the following for “Cyclic Pressure and Large Missile Impact” (Level A in the table above).\n•  Miami-Dade County PA 201, 202, __and__ 203\n•  Florida Building Code Testing Application Standard (TAS) 201, 202, __and__ 203\n•  American Society for Testing and Materials (ASTM) E 1886 __and__ ASTM E 1996\n•  Southern Standards Technical Document (SSTD) 12\n•  For Skylights Only: ASTM E 1886 __and__ ASTM E 1996\n•  For Garage Doors Only: ANSI/DASMA 115",
        listOf("A.1 All Non-Glazed openings classified as A in the table above, or no Non-Glazed openings exist",
            "A.2 One or More Non-Glazed openings classified as Level D in the table above, and no Non-Glazed openings classified as Level B, C, N, or X in the table above",
            "A.3 One or More Non-Glazed Openings is classified as Level B, C, N, or X in the table above")),
    Triple("B", "**__B. Exterior Opening Protection- Cyclic Pressure and 4 to 8-lb Large Missile (2-4.5 lb for skylights only)__** All Glazed openings are protected, at a minimum, with impact resistant coverings or products listed as windborne debris protection devices in the product approval system of the State of Florida or Miami-Dade County and meet the requirements of one of the following for “Cyclic Pressure and Large Missile Impact” (Level B in the table above):\n•  ASTM E 1886 __and__ ASTM E 1996 (Large Missile – 4.5 lb.)\n•  SSTD 12 (Large Missile – 4 lb. to 8 lb.)\n•  For Skylights Only: ASTM E 1886 __and__ ASTM E 1996 (Large Missile - 2 to 4.5 lb.)",
        listOf("B.1 All Non-Glazed openings classified as A or B in the table above, or no Non-Glazed openings exist",
            "B.2 One or More Non-Glazed openings classified as Level D in the table above, and no Non-Glazed openings classified as Level C, N, or X in the table above",
            "B.3 One or More Non-Glazed openings is classified as Level C, N, or X in the table above")),
    Triple("C", "**__C. Exterior Opening Protection- Wood Structural Panels meeting FBC 2007__** All Glazed openings are covered with plywood/OSB meeting the requirements of Table 1609.1.2 of the FBC 2007 (Level C in the table above).",
        listOf("C.1 All Non-Glazed openings classified as A, B, or C in the table above, or no Non-Glazed openings exist",
            "C.2 One or More Non-Glazed openings classified as Level D in the table above, and no Non-Glazed openings classified as Level N or X in the table above",
            "C.3 One or More Non-Glazed openings is classified as Level N or X in the table above")),
    Triple("N", "**__N. Exterior Opening Protection (unverified shutter systems with no documentation)__** All Glazed openings are protected with protective coverings not meeting the requirements of Answer “A”, “B”, or C” or systems that appear to meet Answer “A” or “B” with no documentation of compliance (Level N in the table above).",
        listOf("N.1 All Non-Glazed openings classified as Level A, B, C, or N in the table above, or no Non-Glazed openings exist",
            "N.2 One or More Non-Glazed openings classified as Level D in the table above, and no Non-Glazed openings classified as Level X in the table above",
            "N.3 One or More Non-Glazed openings is classified as Level X in the table above")),
    Triple("X", "**__X. None or Some Glazed Openings__** One or more Glazed openings classified and Level X in the table above.", emptyList()),
)
private val LICENSES = listOf(
    "Home inspector licensed under Section 468.8314, Florida Statutes who has completed the statutory number of hours of hurricane mitigation training approved by the Construction Industry Licensing Board and completion of a proficiency exam.",
    "Building code inspector certified under Section 468.607, Florida Statutes.",
    "General, building or residential contractor licensed under Section 489.111, Florida Statutes.",
    "Professional engineer licensed under Section 471.015, Florida Statutes.",
    "Professional architect licensed under Section 481.213, Florida Statutes.",
    "Any other individual or entity recognized by the insurer as possessing the necessary qualifications to properly complete a uniform mitigation verification form pursuant to Section 627.711(2), Florida Statutes.",
)
private const val CERT_EMPLOYEES = "**__Individuals other than licensed contractors licensed under Section 489.111, Florida Statutes, or professional engineer licensed under Section 471.015, Florida Statues, must inspect the structures personally and not through employees or other persons. Licensees under s.471.015 or s.489.111 may authorize a direct employee who possesses the requisite skill, knowledge, and experience to conduct a mitigation verification inspection.__**"
private const val FRAUD = "**__An individual or entity who knowingly or through gross negligence provides a false or fraudulent mitigation verification form is subject to investigation by the Florida Division of Insurance Fraud and may be subject to administrative action by the appropriate licensing agency or to criminal prosecution. (Section 627.711(4)-(7), Florida Statutes) The Qualified Inspector who certifies this form shall be directly liable for the misconduct of employees as if the authorized mitigation inspector personally performed the inspection.__**"
private const val MISDEMEANOR = "**An individual or entity who knowingly provides or utters a false or fraudulent mitigation verification form with the intent to obtain or receive a discount on an insurance premium to which the individual or entity is not entitled commits a misdemeanor of the first degree. (Section 627.711(7), Florida Statutes)**"
private const val DEFINITIONS = "**The definitions on this form are for inspection purposes only and cannot be used to certify any product or construction feature as offering protection from hurricanes.**"
private const val VALID = "*This verification form is valid for up to five (5) years provided no material changes have been made to the structure or inaccuracies found on the form."
private const val FORM_ID = "OIR-B1-1802 (Rev. 01/12) Adopted by Rule 69O-170.0155"


/** TREC REI 7-6 (8/9/21) promulgated text for page 1 of the Texas report (verbatim from report.html). */
private sealed interface TrecBlock {
    data class Heading(val text: String) : TrecBlock
    data class Para(val text: String, val lead: String? = null) : TrecBlock
    data class Bullets(val items: List<String>) : TrecBlock
}

private val TREC_TEXT: List<TrecBlock> = listOf(
    TrecBlock.Heading("PURPOSE OF INSPECTION"),
    TrecBlock.Para("A real estate inspection is a visual survey of a structure and a basic performance evaluation of the systems and components of a building. It provides information regarding the general condition of a residence at the time the inspection was conducted. It is important that you carefully read ALL of this information. Ask the inspector to clarify any items or comments that are unclear."),
    TrecBlock.Heading("RESPONSIBILITY OF THE INSPECTOR"),
    TrecBlock.Para("This inspection is governed by the Texas Real Estate Commission (TREC) Standards of Practice (SOPs), which dictates the minimum requirements for a real estate inspection."),
    TrecBlock.Para("The inspector IS required to:"),
    TrecBlock.Bullets(listOf(
        "use this Property Inspection Report form for the inspection;",
        "inspect only those components and conditions that are present, visible, and accessible at the time of the inspection;",
        "indicate whether each item was inspected, not inspected, or not present;",
        "indicate an item as Deficient (D) if a condition exists that adversely and materially affects the performance of a system or component OR constitutes a hazard to life, limb or property as specified by the SOPs; and",
        "explain the inspector’s findings in the corresponding section in the body of the report form.",
    )),
    TrecBlock.Para("The inspector IS NOT required to:"),
    TrecBlock.Bullets(listOf(
        "identify all potential hazards;",
        "turn on decommissioned equipment, systems, utilities, or apply an open flame or light a pilot to operate any appliance;",
        "climb over obstacles, move furnishings or stored items;",
        "prioritize or emphasize the importance of one deficiency over another;",
        "provide follow-up services to verify that proper repairs have been made; or",
        "inspect system or component listed under the optional section of the SOPs (22 TAC 535.233).",
    )),
    TrecBlock.Heading("RESPONSIBILITY OF THE CLIENT"),
    TrecBlock.Para("While items identified as Deficient (D) in an inspection report DO NOT obligate any party to make repairs or take other actions, in the event that any further evaluations are needed, it is the responsibility of the client to obtain further evaluations and/or cost estimates from qualified service professionals regarding any items reported as Deficient (D). It is recommended that any further evaluations and/or cost estimates take place prior to the expiration of any contractual time limitations, such as option periods."),
    TrecBlock.Para("Evaluations performed by service professionals in response to items reported as Deficient (D) on the report may lead to the discovery of additional deficiencies that were not present, visible, or accessible at the time of the inspection. Any repairs made after the date of the inspection may render information contained in this report obsolete or invalid.", lead = "Please Note:"),
    TrecBlock.Heading("REPORT LIMITATIONS"),
    TrecBlock.Para("This report is provided for the benefit of the named client and is based on observations made by the named inspector on the date the inspection was performed (indicated above). ONLY those items specifically noted as being inspected on the report were inspected. This inspection IS NOT:"),
    TrecBlock.Bullets(listOf(
        "a technically exhaustive inspection of the structure, its systems, or its components and may not reveal all deficiencies;",
        "an inspection to verify compliance with any building codes;",
        "an inspection to verify compliance with manufacturer’s installation instructions for any system or component and DOES NOT imply insurability or warrantability of the structure or its components.",
    )),
)
