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
import com.vims.app.data.ChecklistConfig
import com.vims.app.data.ChecklistEngine
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
        page?.let { if (pageNo > 1) footer(); doc.finishPage(it) }
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
    private fun infoGrid(rows: List<Pair<String, String>>) {
        val colW = (CW - 26f) / 2
        rows.chunked(2).forEach { pair ->
            val layouts = pair.map { (k, v) ->
                val kl = layout(k, tp(plex400, 13f, INK3), colW * .5f)
                val vl = layout(v.ifBlank { "—" }, tp(plex600, 13f, INK), colW * .5f - 14f, Layout.Alignment.ALIGN_OPPOSITE)
                kl to vl
            }
            val h = layouts.maxOf { maxOf(it.first.height, it.second.height) } + 16f
            ensure(h + 9f)
            layouts.forEachIndexed { i, (kl, vl) ->
                val x = PADX + i * (colW + 26f)
                cv.drawLayout(kl, x, y + 8f)
                cv.drawLayout(vl, x + colW - vl.width, y + 8f)
                cv.drawRect(x, y + h - 1f, x + colW, y + h, fill(LINE2))
            }
            y += h + 9f
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
        if (layoutKind != ChecklistConfig.LAYOUT_STANDARD) { render(); totalPages = pageNo; doc.close() }
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
                sections.forEach { s -> sectionPages(s); photoPages(s) }
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
        val cover = b.inspection.cover
        val pal = cfg.colors.firstOrNull { it.name == cover.color } ?: cfg.colors.firstOrNull()
        val light = Color.parseColor(pal?.light ?: "#F7FAFD"); val mid = Color.parseColor(pal?.mid ?: "#B5D2EC")
        val deep = Color.parseColor(pal?.deep ?: "#237AD4"); val solid = Color.parseColor(pal?.solid ?: "#8DBAE9")
        val style = if (cover.category == "Solid") cfg.solidStyle else cover.style
        val box = lay.pageBox.inches(CoverLayoutDef().pageBox)

        // page box
        when (style) {
            "Shaded" -> cv.drawRect(box, Paint().apply {
                shader = LinearGradient(0f, box.top, 0f, box.bottom, intArrayOf(light, light, mid, deep, deep), floatArrayOf(0f, .18f, .56f, .83f, 1f), Shader.TileMode.CLAMP)
            })
            cfg.solidStyle -> cv.drawRect(box, fill(solid))
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
        rows.forEachIndexed { i, (l, v) ->
            val base = inch(top) + fs * .9f
            val vx = if (l.isEmpty()) left else { cv.drawText(l, left, base, pl); left + pl.measureText(l) + sp }
            valueLine(v, vx, right, base)
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

        // theme art + footer: when the art's visible pixels reach the footer band, the footer wraps into the wider free side
        // beside them (as on the client's covers), at least 3.3 in wide. Measured from the artwork's alpha, not its rect:
        // the rects include transparent margins (Horses starts at 3.46 in but its first pixels are at 4.2 in).
        val art = cfg.art(cover)
        val artRect = art?.rect?.takeIf { it.size >= 4 }
        val artBmp = if (artRect != null) art?.file?.let { themeArt(it) } else null
        var fl = .55f; var fr = 7.95f
        val ext = if (artBmp != null && artRect != null) artBandExtent(artBmp, artRect, lay.footer.centerY - .3f, lay.footer.centerY + .3f) else null
        if (ext != null) {
            val minW = 3.3f
            val leftFree = ext.first - .1f - fl; val rightFree = fr - (ext.second + .1f)
            if (leftFree >= rightFree) fr = fl + maxOf(leftFree, minW) else fl = fr - maxOf(rightFree, minW)
        }
        val footW = inch(fr - fl)
        val footText = lay.footer.text.replace("{companyName}", company.name.ifBlank { "the inspection company" })
        val notice = layout(footText, tp(serifBold, pt(lay.footer.size), Color.BLACK), footW, Layout.Alignment.ALIGN_CENTER, 1.18f)
        // stateRules.<STATE>.coverNotice (e.g. Oregon): extra line under the ownership notice, every layout.
        val stateNotice = config.stateRule(sel.state)?.coverNotice?.let {
            layout(it, tp(serifBold, pt(lay.footer.size - 1.5f), Color.BLACK), footW, Layout.Alignment.ALIGN_CENTER, 1.12f)
        }
        val footH = notice.height + (stateNotice?.let { it.height + inch(.06f) } ?: 0f)
        val footTop = (inch(lay.footer.centerY) - footH / 2).coerceAtMost(box.bottom - inch(.06f) - footH)

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
        stateNotice?.let { cv.drawLayout(it, inch(fl), footTop + notice.height + inch(.06f)) }
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
        fun num(v: String) = v.replace(",", "").toDoubleOrNull()
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
            else -> if (detail && input.isNotBlank()) listOf(chips, input).filter { s -> s.isNotBlank() }.joinToString(" — ") else chips
        }
        return v.ifBlank { null }
    }

    private fun sectionPages(section: String) {
        startPage()
        val num = ChecklistEngine.number(b.defs, section)
        secTitle(num, section)
        val a = b.answers[section] ?: SectionAnswers()
        val def = b.defs[baseName(section)]
        val depth = b.inspection.selections.depth
        val kP = tp(plex400, 12.5f, INK2); val vP = tp(plex600, 12.5f, INK)
        fun row(k: String, v: String, dot: Int = 0) {
            val kl = layout(k, kP, CW * .52f - 12f)
            val vl = layout(v, vP, CW * .48f - 24f)
            val h = maxOf(kl.height, vl.height) + 14f
            ensure(h) { secTitle(num, "$section (cont.)") }
            cv.drawLayout(kl, PADX + 6f, y + 7f)
            cv.drawLayout(vl, PADX + CW * .52f + 6f, y + 7f)
            if (dot > 0) cv.drawCircle(PADX + CW * .52f + 6f + vl.getLineWidth(0) + 11f, y + 7f + 8f, 4f, fill(C[dot]))
            cv.drawRect(PADX, y + h - 1f, PADX + CW, y + h, fill(LINE2))
            y += h
        }
        fun band(t: String) {
            ensure(60f) { secTitle(num, "$section (cont.)") }
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
            val keyed = ChecklistEngine.keyed(ChecklistEngine.itemsFor(def, depth))
            val detail = ChecklistEngine.showDetailInput(def, depth)
            var pendingHeader: String? = null
            keyed.forEach { (key, it) ->
                if (key == null) { pendingHeader = it.header; return@forEach }
                val v = answerText(key, it, a, detail) ?: return@forEach
                pendingHeader?.let { h -> band(h); pendingHeader = null }
                row(it.q.orEmpty(), v, if (a.values[key].orEmpty().any { o -> o.equals("Concerns", true) || o.equals("Fail", true) }) 2 else 0)
                any = true
            }
        }
        if (!any) row("Line items", "No line items recorded")
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
                val l = layout("Category ${f.cat} · $label — ${f.text}", tp(plex400, 12.5f, INK2), CW - 30f)
                ensure(l.height + 12f)
                cv.drawCircle(PADX + 8f, y + 12f, 4.5f, fill(C[f.cat.coerceIn(1, 3)]))
                cv.drawLayout(l, PADX + 22f, y + 4f)
                y += l.height + 12f
            }
        }
    }

    private fun photoPages(section: String) {
        val photos = b.photos.filter { it.section == section }
        if (photos.isEmpty()) return
        val num = ChecklistEngine.number(b.defs, section)
        startPage()
        secTitle(num, "$section · Photos")
        val colW = (CW - 16f) / 2
        val imgH = colW * 2f / 3f
        val capP = tp(plex400, 11.5f, INK2)
        photos.chunked(2).forEach { pair ->
            val caps = pair.map { p -> layout(listOf(p.category, p.caption).filter { it.isNotBlank() }.joinToString(" — "), capP, colW - 22f - (if (p.flag > 0) 50f else 0f)) }
            val h = imgH + caps.maxOf { it.height } + 16f
            if (y + h > BOTTOM) { startPage(); secTitle(num, "$section · Photos (cont.)") }
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
                val l = layout(android.text.SpannableStringBuilder().apply {
                    append(f.text); append(" ")
                    val st = length; append("(${f.section})"); setSpan(android.text.style.ForegroundColorSpan(INK3), st, length, 0)
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
}

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
