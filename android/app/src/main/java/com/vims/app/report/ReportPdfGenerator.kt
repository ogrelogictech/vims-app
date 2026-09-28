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
import com.vims.app.R
import com.vims.app.data.ChecklistConfig
import com.vims.app.data.ChecklistEngine
import com.vims.app.data.CompanyProfile
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

    private fun startPage(header: Boolean = true) {
        finishPage()
        pageNo++
        val info = PdfDocument.PageInfo.Builder(612, 792, pageNo).create()
        page = doc.startPage(info)
        cv = page!!.canvas
        cv.scale(SCALE, SCALE)
        cv.drawRect(0f, 0f, PW, PH, fill(Color.WHITE))
        y = PADY
        if (header) runningHeader()
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
        val l = logo ?: return
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

    fun generate(bundle: InspectionBundle, company: CompanyProfile): ReportOutput {
        b = bundle; this.company = company
        logo = company.logoFile?.let { BitmapFactory.decodeFile(File(context.filesDir, it).path) } ?: BitmapFactory.decodeResource(context.resources, R.drawable.vims_logo)
        doc = PdfDocument(); pageNo = 0; page = null

        cover()
        propertyInfo()
        beginningNotes()
        val sections = bundle.inspection.leafSections.filter { bundle.status(it) == SecStatus.DONE }
            .sortedWith(compareBy<String>({ ChecklistEngine.number(bundle.defs, it) }, { it }))
        sections.forEach { s -> sectionPages(s); photoPages(s) }
        summary()
        finishPage()

        val dir = File(repo.inspectionDir(bundle.id), "report").apply { mkdirs() }
        dir.listFiles()?.forEach { it.delete() }
        val safe = bundle.inspection.selections.street.ifBlank { "Inspection" }.replace(Regex("[^A-Za-z0-9]+"), "-").trim('-')
        val out = File(dir, "VIMS-Report-$safe.pdf")
        FileOutputStream(out).use { doc.writeTo(it) }
        doc.close()
        return ReportOutput(out, pageNo)
    }

    private fun coverColors(): Pair<Int, Int> {
        val c = config.covers.colors.firstOrNull { it.name == b.inspection.cover.color } ?: config.covers.colors.firstOrNull()
        return (c?.from?.let { Color.parseColor(it) } ?: BRAND) to (c?.to?.let { Color.parseColor(it) } ?: BRAND_DEEP)
    }

    private fun cover() {
        startPage(header = false)
        val sel = b.inspection.selections
        val cover = b.inspection.cover
        val (cFrom, cTo) = coverColors()
        // top: brand + company block
        brandBlock(46f, 40f, 64f, 24f, 13f, Color.parseColor("#7C8A55"), plex600)
        addrBlock(PW - 46f, 40f, 12.5f, 11.5f, 18.4f)
        y = 40f + maxOf(64f, 12.5f + addrLines().size * 18.4f) + 26f
        val h1 = tp(archivo800, 26f).apply { textAlign = Paint.Align.CENTER }
        cv.drawText("Inspection Report", PW / 2, y + 24f, h1)
        y += 26f + 18f + 6f
        val rows = listOf(
            "Client Name" to sel.clientName, "Address of Inspection" to sel.street, "" to sel.cityLine,
            "Date of Inspection" to Fmt.slash(sel.date), "Real Estate Agent" to sel.agentName,
            "Name of Inspector" to company.inspectorName,
        )
        val fl = tp(plex700, 15f); val fv = tp(plex400, 20f)
        rows.forEach { (l, v) ->
            val lw = if (l.isEmpty()) 0f else fl.measureText(l) + 12f
            if (l.isNotEmpty()) cv.drawText(l, 60f, y + 20f, fl)
            val vx = 60f + lw
            var text = v
            while (text.isNotEmpty() && fv.measureText(text) > PW - 60f - vx) text = text.dropLast(1)
            cv.drawText(text, vx, y + 20f, fv)
            cv.drawRect(vx, y + 26f, PW - 60f, y + 27f, fill(Color.parseColor("#9FB0C2")))
            y += 27f + 15f
        }
        // cover art band (bottom)
        val notice = layout("This inspection report is the property of ${company.name.ifBlank { "the inspection company" }}. Any reproduction or distribution without written consent is prohibited.",
            tp(archivo700, 15f, Color.WHITE), PW * .5f, Layout.Alignment.ALIGN_CENTER, 1.25f)
        val bandH = notice.height + 44f
        val bandTop = PH - bandH
        // property photo area
        val imgTop = y + 22f - 15f
        val imgRect = RectF(60f, imgTop, PW - 60f, bandTop - 22f)
        val photo = coverPhoto()
        val clip = Path().apply { addRoundRect(imgRect, 6f, 6f, Path.Direction.CW) }
        when {
            cover.category == "Solid" || photo == null -> {
                cv.drawRoundRect(imgRect, 6f, 6f, Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = LinearGradient(imgRect.left, imgRect.top, imgRect.right, imgRect.bottom, cFrom, cTo, Shader.TileMode.CLAMP) })
                val p = tp(archivo800, 30f, Color.WHITE).apply { textAlign = Paint.Align.CENTER }
                cv.drawText(if (photo == null && cover.category != "Solid") "Front of property" else cover.artLabel(), imgRect.centerX(), imgRect.centerY() + 10f, p)
            }
            else -> {
                cv.save(); cv.clipPath(clip); drawCover(photo, imgRect)
                if (cover.style == "Shaded") cv.drawRect(imgRect, Paint().apply { shader = LinearGradient(0f, imgRect.centerY(), 0f, imgRect.bottom, Color.TRANSPARENT, (cTo and 0x00FFFFFF) or (0xB0 shl 24), Shader.TileMode.CLAMP) })
                cv.restore()
            }
        }
        if (cover.style == "Framed") cv.drawRoundRect(imgRect, 6f, 6f, stroke(cFrom, 5f)) else cv.drawRoundRect(imgRect, 6f, 6f, stroke(LINE, 1f))
        photo?.recycle()
        cv.drawRect(0f, bandTop, PW, PH, Paint().apply { shader = LinearGradient(0f, bandTop, PW, PH, cFrom, cTo, Shader.TileMode.CLAMP) })
        cv.drawLayout(notice, 40f, bandTop + 20f)
        val ap = tp(plex400, 12f, Color.parseColor("#CFE0FF")).apply { textAlign = Paint.Align.RIGHT }
        cv.drawText("Cover artwork", PW - 34f, bandTop + bandH - 44f, ap)
        val tag = cover.tag()
        val tagP = tp(plex400, 10f, Color.WHITE)
        val tw = tagP.measureText(tag) + 18f
        val tr = RectF(PW - 34f - tw, bandTop + bandH - 36f, PW - 34f, bandTop + bandH - 18f)
        cv.drawRoundRect(tr, 9f, 9f, fill(Color.argb(41, 255, 255, 255)))
        cv.drawText(tag, tr.left + 9f, tr.bottom - 5.5f, tagP)
    }

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
            if (a.present.isNotEmpty()) { row("Items present", a.present.joinToString(", ")); any = true }
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
        title("Summary of Findings", "Findings grouped by category, in the order they appear in the report")
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
}
