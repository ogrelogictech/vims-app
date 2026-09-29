package com.vims.app.demo

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import com.vims.app.data.AccountState
import com.vims.app.data.ChecklistEdits
import com.vims.app.data.ChecklistLoader
import com.vims.app.data.Role
import com.vims.app.data.Session
import com.vims.app.data.db.CompanyEntity
import com.vims.app.data.db.VimsDao
import com.vims.app.services.LocalAuthService
import com.vims.app.data.ChecklistEngine
import com.vims.app.data.CompanyProfile
import com.vims.app.data.Finding
import com.vims.app.data.InspStatus
import com.vims.app.data.Inspection
import com.vims.app.data.InspectionBundle
import com.vims.app.data.Inspector
import com.vims.app.data.Photo
import com.vims.app.data.SecStatus
import com.vims.app.data.SectionAnswers
import com.vims.app.data.VimsRepository
import com.vims.app.data.WizardSelections
import com.vims.app.data.WizardSelections.Companion.F_ADDRESS
import com.vims.app.data.WizardSelections.Companion.F_AGENT
import com.vims.app.data.WizardSelections.Companion.F_AGENT_EMAIL
import com.vims.app.data.WizardSelections.Companion.F_CLIENT
import com.vims.app.data.WizardSelections.Companion.F_CLIENT_EMAIL
import com.vims.app.data.WizardSelections.Companion.F_CLIENT_PHONE
import com.vims.app.data.WizardSelections.Companion.F_DATE
import com.vims.app.data.WizardSelections.Companion.F_TIME
import java.io.File
import java.io.FileOutputStream
import java.time.LocalDate

/**
 * DEMO DATA — belongs ONLY to the demo account (jeremy@visionpropertyinspections.com / Vision Property Inspections);
 * new accounts start empty. The demo account's sample inspections (equivalent to the prototype's sample data) so the client can review
 * the app. Everything demo-specific lives in this one file. To ship without demo data, delete this file and the two
 * `DemoSeed.…` calls in AppContainer.start() (VimsApplication.kt), plus the debug-only `debugSignIn()` in AppViewModel.
 */
object DemoSeed {

    const val DEMO_EMAIL = "jeremy@visionpropertyinspections.com"
    /** Demo sign-in password (same as the approved prototype's prefill). Local stub only — TODO(backend). */
    const val DEMO_PASSWORD = "inspect2026"
    const val DEMO_USER_ID = "demo-user-jeremy"
    const val DEMO_COMPANY_ID = "demo-company-vpi"

    /** Creates the demo account (user + company) and its sample inspections — only if it doesn't exist yet. */
    suspend fun ensureDemoAccount(dao: VimsDao, repo: VimsRepository, engine: ChecklistEngine) {
        if (dao.userByEmail(DEMO_EMAIL) != null) return
        val cfg = engine.config
        val sample = cfg.sample
        val today = LocalDate.now()
        val json = ChecklistLoader.json
        val account = AccountState(
            companyCode = sample?.company?.code ?: "VIS-4827",
            plans = cfg.subscription.plans,
            extraInspectorMonthly = cfg.subscription.extraInspectorMonthly,
            planId = cfg.subscription.plans.firstOrNull()?.id ?: "app",
            trialDays = cfg.subscription.trialDays,
            // 20 days into the 30-day free look → "10 days left", as in the approved screens.
            trialStartEpochDay = today.toEpochDay() - 20,
            inspectors = sample?.inspectors.orEmpty().mapIndexed { i, s -> Inspector("insp-$i", s.name, s.email, owner = s.owner, admin = s.owner) },
            seats = maxOf(1, sample?.inspectors?.size ?: 1),
            feedbackEmail = cfg.support.feedbackEmail,
        )
        val profile = CompanyProfile(
            name = sample?.company?.name ?: "Vision Property Inspections",
            address = "2029 N Main St Suite 103, Sunset, UT 84015",
            inspectorName = "Jeremy K. Heath",
            email = "VisionPropertyInspections@Gmail.com",
        )
        dao.insertCompany(CompanyEntity(DEMO_COMPANY_ID, account.companyCode, json.encodeToString(CompanyProfile.serializer(), profile),
            json.encodeToString(AccountState.serializer(), account), json.encodeToString(ChecklistEdits.serializer(), ChecklistEdits()), System.currentTimeMillis()))
        val user = LocalAuthService.newUser("Jeremy Heath", DEMO_EMAIL, DEMO_PASSWORD, DEMO_COMPANY_ID, cfg).copy(id = DEMO_USER_ID)
        dao.insertUser(user)

        // Write the sample inspections as the demo user, then drop the scope again.
        repo.activate(Session("Jeremy Heath", DEMO_EMAIL, Role.OWNER, userId = DEMO_USER_ID, companyId = DEMO_COMPANY_ID), persist = false)
        val base = engine.defaultSelections(cfg.wizard.defaults.depth)
        fun sel(address: String, client: String, time: String, date: LocalDate, structure: String, extra: List<String> = emptyList(), chips: Map<String, String> = emptyMap(), fields: Map<String, String> = emptyMap()) =
            base.copy(
                structure = structure,
                exterior = (base.exterior + extra).distinct(),
                chips = base.chips + chips,
                fields = mapOf(F_CLIENT to client, F_ADDRESS to address, F_DATE to date.toString(), F_TIME to time) + fields,
            )

        // 1428 Ridgeline Dr — in progress, with answers, findings, and photos.
        val ridgeSel = sel(
            "1428 Ridgeline Dr, Ogden, UT 84403", "Tysen and Chantel Gough", "09:30", today, "Single Family",
            chips = mapOf("Basement" to "Unfinished"),
            fields = mapOf(
                F_CLIENT_PHONE to "(801) 555-0134", F_CLIENT_EMAIL to "tysen.gough@example.com",
                F_AGENT to "Cyndi Farrais", F_AGENT_EMAIL to "cyndi.farrais@example.com",
                "Temperature (°F)" to "72", "Year of construction" to "1998", "Total sq ft" to "2400",
                "Valuation ($)" to "450,000", "Lot size (acres)" to "0.25",
                "Buyer's areas of concern" to "Buyer asked us to pay particular attention to the roof, the electrical panel, and any signs of water intrusion in the basement.",
                "Apparent hazards observed before inspection" to "Tree branches in contact with the structure on the north side. Section of front walkway concrete lifting — trip hazard.",
            ),
        )
        val ridge = newBundle(engine, "demo-ridgeline", ridgeSel, InspStatus.IN_PROGRESS, pending = true)
        val answers = mutableMapOf<String, SectionAnswers>()
        listOf("Landscaping", "Exterior Walls", "Garage", "Living Room", "Kitchen", "Bedroom 1").forEach { answers[it] = demoAnswers(ridge, it, SecStatus.DONE) }
        listOf("Roof", "Outside Utilities", "Electrical", "Foundation / Crawl Space").forEach { answers[it] = demoAnswers(ridge, it, SecStatus.PROG) }
        val findings = sample?.findings.orEmpty().mapIndexed { i, f -> Finding("demo-f$i", f.cat, f.txt, f.sec, createdAt = System.currentTimeMillis() + i) }
        val photos = mutableListOf<Photo>()
        fun addPhoto(section: String, cat: String, seed: Int, flag: Int = 0, comment: String = "") {
            val id = "demo-p${photos.size}"
            val file = File(repo.inspectionDir(ridge.id), "photos/$id.jpg")
            val rel = file.relativeTo(repo.root.parentFile!!).path
            writePlaceholderPhoto(file, seed)
            photos += Photo(id, section, cat, rel, flag, quickComment = comment)
        }
        addPhoto("Roof", "North Side", 0)
        addPhoto("Roof", "North Side", 1, flag = 2, comment = cfg.findings.quickComments.getOrNull(1).orEmpty())
        addPhoto("Landscaping", "Front Yard", 2)
        addPhoto("Landscaping", "Concerns", 3, flag = 1, comment = cfg.findings.quickComments.getOrNull(0).orEmpty())
        addPhoto("Exterior Walls", "Front", 4)
        addPhoto("Exterior Walls", "Left Side", 0)
        addPhoto("Kitchen", ChecklistEngine.photoCategories(ridge.defs["Kitchen"], "standard").first(), 1)
        repo.putBundle(ridge.copy(answers = answers, findings = findings, photos = photos))

        repo.putBundle(newBundle(engine, "demo-canyon", sel("82 Canyon Crest #4, Layton, UT 84041", "Marcus Webb", "13:00", today, "Condo", extra = listOf("Condo")), InspStatus.QUEUED, pending = false))
        repo.putBundle(newBundle(engine, "demo-willow", sel("210 Willow Park, Lot 17, Roy, UT 84067", "Dana Whitaker", "15:30", today, "Mobile / Manufactured", extra = listOf("Mobile Home Undercarriage")), InspStatus.SCHEDULED, pending = false))
        val harrison = newBundle(engine, "demo-harrison", sel("640 Harrison Blvd, Ogden, UT 84404", "Priya Raman", "10:00", today.minusDays(1), "Single Family"), InspStatus.DONE, pending = false)
        repo.putBundle(harrison.copy(
            inspection = harrison.inspection.copy(reportGeneratedAt = System.currentTimeMillis() - 86_400_000L),
            answers = harrison.inspection.leafSections.associateWith { demoAnswers(harrison, it, SecStatus.DONE) },
        ))

        repo.flush()
        repo.activate(null, persist = false)
    }

    private fun newBundle(engine: ChecklistEngine, id: String, sel: WizardSelections, status: String, pending: Boolean): InspectionBundle {
        val groups = engine.buildGroups(sel)
        return InspectionBundle(
            inspection = Inspection(id = id, createdAt = System.currentTimeMillis(), status = status, selections = sel, groups = groups,
                cover = engine.config.covers.defaultCover, pendingSync = pending),
            defs = engine.snapshot(groups),
        )
    }

    /** Deterministic sample answers: first option on each line (completed) or on the first few lines (in progress). */
    private fun demoAnswers(b: InspectionBundle, section: String, status: String): SectionAnswers {
        val def = b.defs[com.vims.app.data.baseName(section)] ?: return SectionAnswers(status = status)
        val keyed = ChecklistEngine.keyed(ChecklistEngine.itemsFor(def, b.inspection.selections.depth)).filter { it.first != null && it.second.isChoice }
        val take = if (status == SecStatus.DONE) keyed else keyed.take(1)
        return SectionAnswers(
            status = status,
            values = take.associate { (k, it) -> k!! to listOf(it.options!!.first()) },
            overall = "Good",
            comments = if (status == SecStatus.DONE) "No significant concerns noted at the time of inspection." else "",
        )
    }

    /** The demo company uses the VIMS mark as its uploaded logo (new companies show an initials badge until they upload one). */
    suspend fun ensureDemoLogo(dao: VimsDao, filesDir: File, res: android.content.res.Resources) {
        val c = dao.company(DEMO_COMPANY_ID) ?: return
        val json = ChecklistLoader.json
        val profile = json.decodeFromString(CompanyProfile.serializer(), c.profileJson)
        if (profile.logoFile != null && File(filesDir, profile.logoFile).exists()) return
        val f = File(filesDir, "vims/companies/$DEMO_COMPANY_ID/logo.png").apply { parentFile?.mkdirs() }
        val bmp = android.graphics.BitmapFactory.decodeResource(res, com.vims.app.R.drawable.vims_logo) ?: return
        FileOutputStream(f).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
        dao.updateCompanyProfile(DEMO_COMPANY_ID, json.encodeToString(CompanyProfile.serializer(), profile.copy(logoFile = f.relativeTo(filesDir).path)))
    }

    /** Neutral placeholder "photo" (landscape silhouette), like the prototype's sample thumbnails. */
    private fun writePlaceholderPhoto(file: File, seed: Int) {
        val colors = intArrayOf(0xFF4A6572.toInt(), 0xFF5B6B78.toInt(), 0xFF7A6A55.toInt(), 0xFF8A5A4A.toInt(), 0xFF5A6B52.toInt())
        val w = 1200; val h = 900
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(colors[seed % colors.size])
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(56, 0, 0, 0) }
        c.drawPath(Path().apply { moveTo(0f, h * .69f); lineTo(w * .375f, h * .4f); lineTo(w * .625f, h * .58f); lineTo(w.toFloat(), h * .37f); lineTo(w.toFloat(), h.toFloat()); lineTo(0f, h.toFloat()); close() }, p)
        p.color = Color.argb(128, 255, 255, 255)
        c.drawCircle(w * .78f, h * .25f, h * .11f, p)
        file.parentFile?.mkdirs()
        FileOutputStream(file).use { bmp.compress(Bitmap.CompressFormat.JPEG, 85, it) }
        bmp.recycle()
    }
}
