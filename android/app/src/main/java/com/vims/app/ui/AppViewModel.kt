package com.vims.app.ui

import android.app.Application
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.vims.app.VimsApplication
import com.vims.app.data.AccountState
import com.vims.app.data.AppSettings
import com.vims.app.data.ChecklistConfig
import com.vims.app.data.ChecklistEdits
import com.vims.app.data.ChecklistEngine
import com.vims.app.data.CompanyProfile
import com.vims.app.data.CoverChoice
import com.vims.app.data.CustomSection
import com.vims.app.data.Finding
import com.vims.app.data.InspStatus
import com.vims.app.data.Inspection
import com.vims.app.data.InspectionBundle
import com.vims.app.data.Inspector
import com.vims.app.data.ItemDef
import com.vims.app.data.Photo
import com.vims.app.data.Plan
import com.vims.app.data.Role
import com.vims.app.data.SecStatus
import com.vims.app.data.SectionAnswers
import com.vims.app.data.SectionDef
import com.vims.app.data.SectionOverride
import com.vims.app.data.Session
import com.vims.app.data.WizardSelections
import com.vims.app.report.ReportPdfGenerator
import com.vims.app.services.AuthResult
import com.vims.app.services.trialDaysLeft
import com.vims.app.ui.components.NetState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.time.LocalDate
import java.time.LocalTime
import java.util.Locale
import java.util.UUID

data class WizardState(val step: Int = 1, val sel: WizardSelections = WizardSelections(), val editingId: String? = null)

data class ToastMsg(val text: String, val id: Long = System.nanoTime())

class AppViewModel(app: Application) : AndroidViewModel(app) {
    private val container = (app as VimsApplication).container
    val repo = container.repo
    val config: ChecklistConfig = container.config

    val session: StateFlow<Session?> = repo.session
    val account: StateFlow<AccountState> = repo.account
    val company: StateFlow<CompanyProfile> = repo.company
    val settings: StateFlow<AppSettings> = repo.settings
    val edits: StateFlow<ChecklistEdits> = repo.edits
    val inspections: StateFlow<Map<String, InspectionBundle>> = repo.inspections

    val engine: StateFlow<ChecklistEngine> = repo.edits.map { ChecklistEngine(config, it) }
        .stateIn(viewModelScope, SharingStarted.Eagerly, ChecklistEngine(config, repo.edits.value))

    val net: StateFlow<NetState> = combine(repo.inspections, repo.settings) { m, s ->
        NetState(pending = m.values.count { it.inspection.pendingSync }, synced = s.lastSyncAt != null)
    }.stateIn(viewModelScope, SharingStarted.Eagerly, NetState(0, false))

    private val _toast = MutableStateFlow<ToastMsg?>(null)
    val toast: StateFlow<ToastMsg?> = _toast.asStateFlow()
    fun toast(text: String) { _toast.value = ToastMsg(text) }

    /** Free-look splash — shown at every sign-in while the trial is running. */
    private val _splash = MutableStateFlow(false)
    val splash: StateFlow<Boolean> = _splash.asStateFlow()
    fun closeSplash() { _splash.value = false }
    fun maybeShowSplash() { if (!account.value.active) _splash.value = true }

    fun trialDaysLeft(): Int = account.value.let { trialDaysLeft(it.trialDays, it.trialStartEpochDay) }

    fun bundle(id: String): InspectionBundle? = inspections.value[id]

    /* ------------------------------------------------------------------ auth */

    fun signIn(email: String, password: String, onOk: () -> Unit) = viewModelScope.launch {
        when (val r = container.auth.signIn(email, password)) {
            is AuthResult.Error -> toast(r.message)
            is AuthResult.Success -> { repo.setSession(r.session); onOk(); maybeShowSplash() }
        }
    }

    fun createAccount(name: String, companyName: String, email: String, password: String, onOk: () -> Unit) = viewModelScope.launch {
        when (val r = container.auth.createAccount(name, companyName, email, password)) {
            is AuthResult.Error -> toast(r.message)
            is AuthResult.Success -> {
                if (companyName.isNotBlank()) repo.updateCompany { it.copy(name = companyName.trim()) }
                repo.updateCompany { if (it.inspectorName.isBlank()) it.copy(inspectorName = name.trim()) else it }
                repo.updateAccount { a ->
                    if (a.inspectors.any { it.email.equals(email.trim(), true) }) a
                    else a.copy(inspectors = listOf(Inspector(UUID.randomUUID().toString(), name.trim(), email.trim(), owner = true, admin = true)) + a.inspectors.map { it.copy(owner = false) })
                }
                repo.setSession(r.session); onOk(); maybeShowSplash()
            }
        }
    }

    fun joinCompany(name: String, email: String, code: String, onOk: () -> Unit) = viewModelScope.launch {
        when (val r = container.auth.joinCompany(name, email, code)) {
            is AuthResult.Error -> toast(r.message)
            is AuthResult.Success -> {
                repo.updateAccount { a ->
                    if (a.inspectors.any { it.email.equals(email.trim(), true) && email.isNotBlank() }) a
                    else a.copy(inspectors = a.inspectors + Inspector(UUID.randomUUID().toString(), r.session.name, email.trim()))
                }
                repo.setSession(r.session)
                toast("Linked to ${company.value.name.ifBlank { "your company" }}")
                onOk()
            }
        }
    }

    fun sendReset(email: String, onOk: () -> Unit) = viewModelScope.launch {
        if (container.auth.sendPasswordReset(email)) { toast("Reset link sent"); onOk() } else toast("Enter your email")
    }

    fun signOut(onOk: () -> Unit) = viewModelScope.launch { container.auth.signOut(); repo.setSession(null); onOk() }

    /* ------------------------------------------------------------------ wizard */

    private val _wizard = MutableStateFlow(WizardState())
    val wizard: StateFlow<WizardState> = _wizard.asStateFlow()

    fun startWizard(editId: String?) {
        val existing = editId?.let { bundle(it) }
        _wizard.value = if (existing != null) WizardState(1, existing.inspection.selections, editId)
        else {
            // Prefill today's date and the next half hour.
            val now = LocalTime.now()
            val mins = ((now.hour * 60 + now.minute + 29) / 30 * 30) % (24 * 60)
            val sel = engine.value.defaultSelections(settings.value.defaultDepth)
            val time = String.format(Locale.US, "%02d:%02d", mins / 60, mins % 60)
            WizardState(1, sel.copy(fields = sel.fields + mapOf(WizardSelections.F_DATE to LocalDate.now().toString(), WizardSelections.F_TIME to time)), null)
        }
        if (debugWizardStep > 1) { _wizard.update { it.copy(step = debugWizardStep) }; debugWizardStep = 1 }
    }

    /** Debug-only (screenshots): open the wizard / cover picker at a given step. */
    var debugWizardStep = 1
    var debugCoverStep = 1

    fun wizardStep(step: Int) = _wizard.update { it.copy(step = step.coerceIn(1, 4)) }
    fun updateSel(f: (WizardSelections) -> WizardSelections) = _wizard.update { it.copy(sel = f(it.sel)) }

    /** "Build checklist": creates the inspection (or rebuilds an edited one) and returns its id. */
    fun buildChecklist(): String? {
        val w = _wizard.value
        if (w.sel.address.isBlank()) { toast("Enter the inspection address"); _wizard.update { it.copy(step = 1) }; return null }
        val eng = engine.value
        val groups = eng.buildGroups(w.sel)
        val editing = w.editingId?.let { bundle(it) }
        return if (editing != null) {
            repo.updateInspection(editing.id) { it.copy(selections = w.sel, groups = groups, pendingSync = true) }
            repo.updateDefs(editing.id, eng.snapshot(groups, editing.defs))
            toast("Checklist updated — ${w.sel.structure}")
            editing.id
        } else {
            val id = UUID.randomUUID().toString()
            repo.putBundle(
                InspectionBundle(
                    inspection = Inspection(id = id, createdAt = System.currentTimeMillis(), status = InspStatus.IN_PROGRESS, selections = w.sel, groups = groups, cover = settings.value.defaultCover),
                    defs = eng.snapshot(groups),
                )
            )
            toast("Checklist built — ${w.sel.structure}")
            id
        }
    }

    /* ------------------------------------------------------------------ section entry */

    private fun touch(id: String) {
        repo.updateInspection(id) { i -> i.copy(pendingSync = true, status = if (i.status == InspStatus.SCHEDULED || i.status == InspStatus.QUEUED) InspStatus.IN_PROGRESS else i.status) }
    }

    fun editSection(id: String, section: String, f: (SectionAnswers) -> SectionAnswers) {
        repo.updateAnswers(id, section) { a -> f(a).let { if (it.status == SecStatus.TODO) it.copy(status = SecStatus.PROG) else it } }
        touch(id)
    }

    fun saveSection(id: String, section: String) {
        repo.updateAnswers(id, section) { it.copy(status = SecStatus.DONE, overall = it.overall ?: config.overallConditionDefault) }
        touch(id)
    }

    fun nextSection(id: String, section: String): String? {
        val leaves = bundle(id)?.inspection?.leafSections ?: return null
        val i = leaves.indexOf(section)
        return if (i >= 0 && i < leaves.size - 1) leaves[i + 1] else null
    }

    fun sectionDef(id: String, section: String): SectionDef? =
        bundle(id)?.defs?.get(com.vims.app.data.baseName(section)) ?: engine.value.def(section)

    /* ------------------------------------------------------------------ photos */

    fun newPhotoFile(id: String): Pair<String, File> {
        val pid = UUID.randomUUID().toString()
        val rel = "vims/inspections/$id/photos/$pid.jpg"
        return pid to File(getApplication<Application>().filesDir, rel).apply { parentFile?.mkdirs() }
    }

    fun addPhoto(id: String, section: String, cat: String, pid: String, file: File): Photo {
        val rel = file.relativeTo(getApplication<Application>().filesDir).path
        val p = Photo(pid, section, cat, rel)
        repo.updatePhotos(id) { it + p }
        touch(id)
        return p
    }

    /** Photo Picker fallback: copy + downscale the picked image into the inspection's photo folder. */
    suspend fun importPhoto(id: String, section: String, cat: String, uri: Uri): Photo? = withContext(Dispatchers.IO) {
        val (pid, file) = newPhotoFile(id)
        val ok = try {
            val cr = getApplication<Application>().contentResolver
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= 2048) sample *= 2
            val bmp = cr.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, BitmapFactory.Options().apply { inSampleSize = sample }) }
            if (bmp == null) false else { FileOutputStream(file).use { bmp.compress(Bitmap.CompressFormat.JPEG, 88, it) }; bmp.recycle(); true }
        } catch (_: Exception) { false }
        if (ok) withContext(Dispatchers.Main) { addPhoto(id, section, cat, pid, file) } else null
    }

    fun deletePhoto(id: String, photoId: String) {
        val p = bundle(id)?.photos?.firstOrNull { it.id == photoId } ?: return
        repo.updatePhotos(id) { l -> l.filterNot { it.id == photoId } }
        viewModelScope.launch(Dispatchers.IO) { repo.photoFile(p).delete() }
        toast("Photo deleted")
    }

    fun saveMarkup(id: String, photoId: String, flattened: Bitmap?, quick: String, custom: String, onDone: () -> Unit) = viewModelScope.launch {
        val p = bundle(id)?.photos?.firstOrNull { it.id == photoId } ?: return@launch
        if (flattened != null) withContext(Dispatchers.IO) { FileOutputStream(repo.photoFile(p)).use { flattened.compress(Bitmap.CompressFormat.JPEG, 90, it) } }
        repo.updatePhotos(id) { l -> l.map { if (it.id == photoId) it.copy(quickComment = quick, customComment = custom, createdAt = it.createdAt) else it } }
        photoVersion.update { it + 1 }
        touch(id)
        toast("Markup saved to photo")
        onDone()
    }

    /** Bumped when a photo file is rewritten so thumbnails reload. */
    val photoVersion = MutableStateFlow(0)

    /* ------------------------------------------------------------------ findings */

    fun addFinding(id: String, cat: Int, text: String, section: String, photoId: String?) {
        repo.updateFindings(id) { it + Finding(UUID.randomUUID().toString(), cat, text.trim().ifEmpty { "Finding noted" }, section, photoId) }
        if (photoId != null) repo.updatePhotos(id) { l -> l.map { if (it.id == photoId) it.copy(flag = cat) else it } }
        touch(id)
        toast("Finding added to summary")
    }

    fun deleteFinding(id: String, findingId: String) {
        repo.updateFindings(id) { l -> l.filterNot { it.id == findingId } }
        toast("Finding removed")
    }

    /* ------------------------------------------------------------------ report */

    fun setCover(id: String, cover: CoverChoice) = repo.updateInspection(id) { it.copy(cover = cover) }

    private val _generating = MutableStateFlow(false)
    val generating: StateFlow<Boolean> = _generating.asStateFlow()

    fun generateReport(id: String, markDone: Boolean, onDone: (File) -> Unit) = viewModelScope.launch {
        val b = bundle(id) ?: return@launch
        _generating.value = true
        try {
            val out = withContext(Dispatchers.IO) {
                ReportPdfGenerator(getApplication(), config, repo).generate(b, company.value)
            }
            repo.updateInspection(id) {
                it.copy(reportFile = out.file.relativeTo(getApplication<Application>().filesDir).path, reportPages = out.pages,
                    reportGeneratedAt = if (markDone) System.currentTimeMillis() else it.reportGeneratedAt,
                    status = if (markDone) InspStatus.DONE else it.status, pendingSync = true)
            }
            onDone(out.file)
        } catch (e: Exception) {
            toast("Could not generate the report")
        } finally { _generating.value = false }
    }

    fun reportFile(id: String): File? = bundle(id)?.inspection?.reportFile?.let { File(getApplication<Application>().filesDir, it) }?.takeIf { it.exists() }

    /* ------------------------------------------------------------------ settings / company / admin */

    fun setDefaultDepth(depth: String) = repo.updateSettings { it.copy(defaultDepth = depth) }
    fun setAutoSync(on: Boolean) = repo.updateSettings { it.copy(autoSync = on) }
    fun syncNow() = viewModelScope.launch { container.sync.syncNow(); toast("Synced to portal") }

    fun saveCompany(p: CompanyProfile) { repo.updateCompany { p }; toast("Company profile saved") }

    fun importLogo(uri: Uri) = viewModelScope.launch {
        val ok = withContext(Dispatchers.IO) {
            try {
                val bmp = getApplication<Application>().contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) } ?: return@withContext false
                val scale = minOf(1f, 512f / maxOf(bmp.width, bmp.height))
                val out = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true) else bmp
                val f = File(getApplication<Application>().filesDir, "vims/company/logo.png").apply { parentFile?.mkdirs() }
                FileOutputStream(f).use { out.compress(Bitmap.CompressFormat.PNG, 100, it) }
                true
            } catch (_: Exception) { false }
        }
        if (ok) { repo.updateCompany { it.copy(logoFile = "vims/company/logo.png") }; logoVersion.update { it + 1 }; toast("Logo updated") } else toast("Could not read that image")
    }
    val logoVersion = MutableStateFlow(0)

    fun importAgreement(uri: Uri, name: String) = viewModelScope.launch {
        val ext = name.substringAfterLast('.', "pdf")
        val ok = withContext(Dispatchers.IO) {
            try {
                val f = File(getApplication<Application>().filesDir, "vims/company/agreement.$ext").apply { parentFile?.mkdirs() }
                getApplication<Application>().contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(f).use { input.copyTo(it) } } != null
            } catch (_: Exception) { false }
        }
        if (ok) { repo.updateCompany { it.copy(agreementName = name, agreementFile = "vims/company/agreement.$ext") }; toast("Agreement uploaded") } else toast("Could not read that file")
    }

    fun saveFeedbackEmail(email: String): Boolean {
        val v = email.trim()
        if (v.isEmpty() || !v.contains("@")) { toast("Enter a valid email"); return false }
        repo.updateAccount { it.copy(feedbackEmail = v) }; toast("Feedback email saved"); return true
    }

    // Checklist admin -------------------------------------------------------

    fun saveSectionItems(name: String, high: Boolean, items: List<ItemDef>) {
        val eng = engine.value
        val custom = repo.edits.value.custom.firstOrNull { it.def.name == name }
        repo.updateEdits { e ->
            if (custom != null) e.copy(custom = e.custom.map { if (it.def.name == name) it.copy(def = if (high) it.def.copy(itemsHigh = items) else it.def.copy(items = items)) else it })
            else {
                val o = e.overrides[name] ?: SectionOverride()
                e.copy(overrides = e.overrides + (name to if (high) o.copy(itemsHigh = items) else o.copy(items = items)))
            }
        }
        if (eng.def(name) != null) toast("Checklist updated")
    }

    fun addCustomSection(name: String, group: String): Boolean {
        val n = name.trim()
        if (n.isEmpty()) { toast("Enter a section name"); return false }
        if (engine.value.def(n) != null) { toast("A section named “$n” already exists"); return false }
        val def = SectionDef(name = n, number = 99, photoCategories = listOf("Overview", "Concerns"),
            items = listOf(ItemDef(q = "Condition", type = "single", options = listOf("Good", "Fair", "Poor", "N/A"))))
        repo.updateEdits { it.copy(custom = it.custom + CustomSection(group, def)) }
        toast("Added “$n”")
        return true
    }

    // Subscription / inspectors / plans -------------------------------------

    fun selectPlan(planId: String) = repo.updateAccount { it.copy(planId = planId) }
    fun setSeats(n: Int) = repo.updateAccount { it.copy(seats = n.coerceAtLeast(maxOf(1, it.inspectors.size))) }

    fun monthlyTotal(a: AccountState = account.value): Double = if (a.plan.perReport) 0.0 else a.plan.price + maxOf(0, a.seatCount - 1) * a.extraInspectorMonthly

    fun startSubscription(cardNumber: String, onOk: () -> Unit) = viewModelScope.launch {
        val a = account.value
        val r = container.subscriptions.startSubscription(a.plan, a.seatCount, cardNumber)
        if (r.ok) {
            repo.updateAccount { it.copy(active = true, cardLast4 = r.cardLast4, subscribedEpochDay = LocalDate.now().toEpochDay()) }
            onOk()
        } else toast(r.message ?: "Payment failed")
    }

    fun addInspector(name: String, email: String): Boolean {
        if (name.isBlank()) { toast("Enter a name"); return false }
        repo.updateAccount { it.copy(inspectors = it.inspectors + Inspector(UUID.randomUUID().toString(), name.trim(), email.trim()), seats = maxOf(it.seats, it.inspectors.size + 1)) }
        toast("Inspector added · +${com.vims.app.util.Fmt.money(account.value.extraInspectorMonthly)}/mo")
        return true
    }

    fun removeInspector(inspectorId: String) = repo.updateAccount { a ->
        val l = a.inspectors.filterNot { it.id == inspectorId && !it.owner }
        a.copy(inspectors = l, seats = maxOf(1, minOf(a.seats, l.size)))
    }

    fun toggleAdmin(inspectorId: String) {
        val ins = account.value.inspectors.firstOrNull { it.id == inspectorId } ?: return
        if (ins.owner) return
        repo.updateAccount { a -> a.copy(inspectors = a.inspectors.map { if (it.id == inspectorId) it.copy(admin = !it.admin) else it }) }
        toast(if (!ins.admin) "${ins.name} is now an admin" else "${ins.name} is no longer an admin")
    }

    fun setPlanPrice(planId: String, price: Double) {
        repo.updateAccount { a -> a.copy(plans = a.plans.map { if (it.id == planId) it.copy(price = price) else it }) }
        account.value.plans.firstOrNull { it.id == planId }?.let { toast("${it.name} → ${com.vims.app.util.Fmt.money(price)}") }
    }

    fun setExtraRate(v: Double) { repo.updateAccount { it.copy(extraInspectorMonthly = v) }; toast("Extra inspector → ${com.vims.app.util.Fmt.money(v)}") }

    fun addPlan(name: String, price: String, desc: String): Boolean {
        val p = price.trim().toDoubleOrNull()
        if (name.isBlank()) { toast("Enter a plan name"); return false }
        if (p == null || p < 0) { toast("Enter a valid price"); return false }
        repo.updateAccount { a -> a.copy(plans = a.plans + Plan("plan${a.plans.size + 1}-${System.currentTimeMillis() % 10000}", name.trim(), p, desc.trim().ifEmpty { "Custom plan" })) }
        toast("Added “${name.trim()}”")
        return true
    }

    val isAdmin: Boolean get() = session.value?.role != Role.INSPECTOR

    /** Debug-only helper (screenshots): force an inspection's depth. */
    fun debugSetDepth(id: String, depth: String) = repo.updateInspection(id) { it.copy(selections = it.selections.copy(depth = depth)) }
    fun debugSignIn() { if (session.value == null) repo.setSession(Session(company.value.inspectorName.ifBlank { "Jeremy Heath" }.replace(" K.", ""), account.value.inspectors.firstOrNull()?.email ?: "demo@vims.app")) }
}
