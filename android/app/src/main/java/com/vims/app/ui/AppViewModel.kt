package com.vims.app.ui

import android.app.Application
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
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

/** Created by `MainActivity` only after `VimsApplication.ready` (the container's startup work runs in the background). */
class AppViewModel(app: Application) : AndroidViewModel(app) {
    private val container = (app as VimsApplication).container
    val repo = container.repo
    val config: ChecklistConfig = container.config
    /** App files dir, derived from the repository root (Context.getFilesDir() stats the disk; composables use this instead). */
    val filesDir: File = repo.root.parentFile!!

    val session: StateFlow<Session?> = repo.session
    val account: StateFlow<AccountState> = repo.account
    val company: StateFlow<CompanyProfile> = repo.company
    val settings: StateFlow<AppSettings> = repo.settings
    val edits: StateFlow<ChecklistEdits> = repo.edits
    val inspections: StateFlow<Map<String, InspectionBundle>> = repo.inspections
    val platform: StateFlow<com.vims.app.data.PlatformSettings> = repo.platform

    /** The client's EULA (assets/legal/eula.json). */
    val eula: com.vims.app.data.Eula = container.eulaResult.getOrElse { com.vims.app.data.Eula() }
    /** Non-null when the EULA couldn't be loaded — shown instead of a blank agreement. */
    val eulaError: String? = container.eulaResult.exceptionOrNull()?.let { "${it::class.java.simpleName}: ${it.message}" }
    /** VIMS default inspection agreement (assets/legal/inspection-agreement.json), loaded at startup. */
    val agreement: com.vims.app.data.InspectionAgreement = container.agreementResult.getOrElse { com.vims.app.data.InspectionAgreement() }
    val agreementError: String? = container.agreementResult.exceptionOrNull()?.let { "${it::class.java.simpleName}: ${it.message}" }
    /** Debug-only override of the current EULA version (to exercise the re-acceptance screen). */
    var debugEulaVersion by androidx.compose.runtime.mutableStateOf<String?>(null)
    val currentEulaVersion: String get() = debugEulaVersion ?: eula.version.ifBlank { "unavailable" }

    fun acceptEula() = viewModelScope.launch { repo.acceptEula(currentEulaVersion); toast("License agreement accepted") }

    // Subscription cancel / resume (owner & admins; TODO(backend): Square).
    fun cancelSubscription() = viewModelScope.launch {
        if (container.subscriptions.cancelSubscription()) {
            repo.updateAccount { it.copy(cancelled = true) }
            toast("Subscription cancelled — active until ${account.value.periodEndEpochDay?.let { com.vims.app.util.Fmt.date(java.time.LocalDate.ofEpochDay(it)) } ?: "the end of the period"}")
        }
    }
    fun resumeSubscription() = viewModelScope.launch {
        if (container.subscriptions.resumeSubscription()) { repo.updateAccount { it.copy(cancelled = false) }; toast("Cancellation undone — auto-pay continues") }
    }
    val isPlatformOwner: Boolean get() = session.value?.platformOwner == true

    /** Owner-only: Report quality copy (BCC). The address is validated by the screen. */
    fun saveReportBcc(on: Boolean, email: String) {
        repo.updatePlatform { it.copy(reportBccOn = on, reportBccEmail = email.trim()) }
        toast(if (on) "Reports will be blind-copied to ${email.trim()}" else "Report BCC turned off")
    }

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

    /** Auth errors come back through `onError` so the form can show them inline under the right field. */
    fun signIn(email: String, password: String, onError: (AuthResult.Error) -> Unit, onOk: () -> Unit) = viewModelScope.launch {
        when (val r = container.auth.signIn(email.trim(), password)) {
            is AuthResult.Error -> onError(r)
            is AuthResult.Success -> { repo.activate(r.session); onOk(); maybeShowSplash() }
        }
    }

    fun createAccount(name: String, companyName: String, email: String, password: String, onError: (AuthResult.Error) -> Unit, onOk: () -> Unit) = viewModelScope.launch {
        when (val r = container.auth.createAccount(name.trim(), companyName.trim(), email.trim(), password, currentEulaVersion)) {
            is AuthResult.Error -> onError(r)
            is AuthResult.Success -> { repo.activate(r.session); onOk(); maybeShowSplash() }
        }
    }

    fun joinCompany(name: String, email: String, code: String, password: String, onError: (AuthResult.Error) -> Unit, onOk: () -> Unit) = viewModelScope.launch {
        when (val r = container.auth.joinCompany(name.trim(), email.trim(), code, password, currentEulaVersion)) {
            is AuthResult.Error -> onError(r)
            is AuthResult.Success -> {
                repo.activate(r.session)
                toast("Linked to ${company.value.name.ifBlank { "your company" }}")
                onOk()
            }
        }
    }

    fun sendReset(email: String, onOk: () -> Unit) = viewModelScope.launch {
        if (container.auth.sendPasswordReset(email)) { toast("Reset link sent"); onOk() }
    }

    /** Clears every user/company value from memory; the next user only ever loads their own data. */
    fun signOut(onOk: () -> Unit) = viewModelScope.launch { container.auth.signOut(); repo.activate(null); _splash.value = false; onOk() }

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
            // Inspector License # defaults to the lead inspector's license from the Company profile.
            val license = company.value.license.trim()
            val prefill = mapOf(WizardSelections.F_DATE to LocalDate.now().toString(), WizardSelections.F_TIME to time) +
                (if (license.isNotEmpty()) mapOf(WizardSelections.F_LICENSE to license) else emptyMap())
            WizardState(1, sel.copy(fields = sel.fields + prefill), null)
        }
        if (debugWizardStep > 1) { _wizard.update { it.copy(step = debugWizardStep) }; debugWizardStep = 1 }
    }

    /** Debug-only (screenshots): open the wizard / cover picker at a given step. */
    var debugWizardStep = 1
    var debugCoverStep = 1

    fun wizardStep(step: Int) = _wizard.update { it.copy(step = step.coerceIn(1, 4)) }
    fun updateSel(f: (WizardSelections) -> WizardSelections) = _wizard.update { it.copy(sel = f(it.sel)) }

    /**
     * Wizard step 1 "State" (stateRules `_about`): a rule's `type` is auto-selected; changing to a state without that
     * rule while the inspection is still on the auto type reverts it to the default type ("Real Estate Sale").
     * Changing the state clears the state-documents acknowledgment and resets "Send the report to the real estate agent"
     * to the state's `agentCopyDefault` (unchecked for NH, checked elsewhere).
     */
    fun setInspState(code: String) = updateSel { s ->
        if (s.state == code) return@updateSel s
        val prev = config.stateRule(s.state)?.type
        val next = config.stateRule(code)?.type
        var type = s.inspType
        if (prev != null && type == prev && next != prev) type = config.wizard.defaults.inspType
        if (next != null && next in config.wizard.inspectionTypes) type = next
        s.copy(state = code, inspType = type, stateDocsAck = false, stateDocsAckAt = null, sendToAgent = config.stateRule(code)?.agentCopy ?: true)
    }

    /** Step 1 "Send the report to the real estate agent" — saved on the inspection with the rest of the selections. */
    fun setSendToAgent(on: Boolean) = updateSel { it.copy(sendToAgent = on) }

    /** "Provided to the client with the inspection agreement" — stored with a timestamp on the inspection. */
    fun ackStateDocs(on: Boolean) = updateSel { it.copy(stateDocsAck = on, stateDocsAckAt = if (on) System.currentTimeMillis() else null) }

    /** "Build checklist": creates the inspection (or rebuilds an edited one) and returns its id. */
    fun buildChecklist(): String? {
        val w = _wizard.value
        if (w.sel.address.isBlank()) { toast("Enter the inspection address"); _wizard.update { it.copy(step = 1) }; return null }
        if (w.sel.state.isBlank()) { toast("Select the property's state"); _wizard.update { it.copy(step = 1) }; return null }
        if (config.stateRule(w.sel.state)?.docs.orEmpty().isNotEmpty() && !w.sel.stateDocsAck) {
            toast("Confirm the required state notice was given to the client"); _wizard.update { it.copy(step = 1) }; return null
        }
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
        return pid to File(repo.inspectionDir(id), "photos/$pid.jpg").apply { parentFile?.mkdirs() }
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

    fun addFinding(id: String, cat: Int, text: String, section: String, photoId: String?, item: String? = null) {
        repo.updateFindings(id) { it + Finding(UUID.randomUUID().toString(), cat, text.trim().ifEmpty { "Finding noted" }, section, photoId, item = item) }
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

    /** Saves the profile form; the logo and agreement (upload / edit) are managed by their own actions and kept as they are. */
    fun saveCompany(p: CompanyProfile) {
        repo.updateCompany { cur -> p.copy(logoFile = cur.logoFile, agreementName = cur.agreementName, agreementFile = cur.agreementFile, agreementText = cur.agreementText, agreementEditedAt = cur.agreementEditedAt) }
        toast("Company profile saved")
    }

    /* ---- profile photo (per user, never the company logo) ---- */
    val userPhoto: StateFlow<String?> = repo.userPhoto
    val memberPhotos: StateFlow<Map<String, String>> = repo.memberPhotos
    fun setUserPhoto(uri: Uri) = viewModelScope.launch {
        val s = session.value ?: return@launch
        val f = File(repo.root, "users/${s.userId}/profile.jpg")
        val ok = withContext(Dispatchers.IO) { com.vims.app.util.saveSquareAvatar(getApplication<Application>().contentResolver, uri, f) }
        if (ok) { repo.setUserPhoto(f.relativeTo(getApplication<Application>().filesDir).path); logoVersion.update { it + 1 }; toast("Profile photo updated") } else toast("Could not read that image")
    }
    fun removeUserPhoto() = viewModelScope.launch {
        val s = session.value ?: return@launch
        withContext(Dispatchers.IO) { File(repo.root, "users/${s.userId}/profile.jpg").delete() }
        repo.setUserPhoto(null); toast("Profile photo removed")
    }
    fun removeLogo() {
        val f = company.value.logoFile?.let { File(getApplication<Application>().filesDir, it) }
        repo.updateCompany { it.copy(logoFile = null) }; f?.delete(); logoVersion.update { it + 1 }; toast("Logo removed")
    }

    /* ---- account deletion / ownership ---- */
    fun deleteAccount(onError: (String) -> Unit, onOk: () -> Unit) = viewModelScope.launch {
        val wasSoleOwner = session.value?.role == Role.OWNER
        val err = repo.deleteAccount()
        if (err != null) { onError(err); return@launch }
        if (wasSoleOwner) container.subscriptions.cancelSubscription() // TODO(backend): server-side cancel + deletion request
        _splash.value = false
        toast("Account deleted"); onOk()
    }

    /** Owner hands the company to another inspector (they become Owner · Admin; the old owner stays Admin). */
    fun makeOwner(inspectorId: String) = viewModelScope.launch {
        val target = account.value.inspectors.firstOrNull { it.id == inspectorId } ?: return@launch
        repo.updateAccount { a -> a.copy(inspectors = a.inspectors.map { i -> if (i.id == inspectorId) i.copy(owner = true, admin = true) else if (i.owner) i.copy(owner = false, admin = true) else i }) }
        session.value?.let { repo.activate(it.copy(role = Role.ADMIN)) }
        toast("${target.name} is now the owner")
    }

    fun importLogo(uri: Uri) = viewModelScope.launch {
        val ok = withContext(Dispatchers.IO) {
            try {
                val bmp = getApplication<Application>().contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it) } ?: return@withContext false
                val scale = minOf(1f, 512f / maxOf(bmp.width, bmp.height))
                val out = if (scale < 1f) Bitmap.createScaledBitmap(bmp, (bmp.width * scale).toInt(), (bmp.height * scale).toInt(), true) else bmp
                val f = File(repo.companyDir(), "logo.png")
                FileOutputStream(f).use { out.compress(Bitmap.CompressFormat.PNG, 100, it) }
                true
            } catch (_: Exception) { false }
        }
        val rel = File(repo.companyDir(), "logo.png").relativeTo(getApplication<Application>().filesDir).path
        if (ok) { repo.updateCompany { it.copy(logoFile = rel) }; logoVersion.update { it + 1 }; toast("Logo updated") } else toast("Could not read that image")
    }
    val logoVersion = MutableStateFlow(0)

    fun importAgreement(uri: Uri, name: String) = viewModelScope.launch {
        if (!isAdmin) return@launch
        val ext = name.substringAfterLast('.', "pdf")
        val ok = withContext(Dispatchers.IO) {
            try {
                val f = File(repo.companyDir(), "agreement.$ext")
                getApplication<Application>().contentResolver.openInputStream(uri)?.use { input -> FileOutputStream(f).use { input.copyTo(it) } } != null
            } catch (_: Exception) { false }
        }
        val rel = File(repo.companyDir(), "agreement.$ext").relativeTo(getApplication<Application>().filesDir).path
        if (ok) {
            val old = company.value.agreementFile
            // An upload replaces an edited agreement as the one in use.
            repo.updateCompany { it.copy(agreementName = name, agreementFile = rel, agreementText = null, agreementEditedAt = null) }
            if (old != null && old != rel) withContext(Dispatchers.IO) { File(filesDir, old).delete() }
            toast("Your agreement is now in use")
        } else toast("Could not read that file")
    }

    /** The company's own uploaded agreement file, or null when it uses the VIMS agreement. */
    fun ownAgreementFile(): File? = company.value.agreementFile?.takeIf { company.value.agreementName != null }?.let { File(filesDir, it) }

    /** "Use VIMS agreement": back to the default agreement; the uploaded file and any edited text are removed from the device. */
    fun useDefaultAgreement() = viewModelScope.launch {
        if (!isAdmin) return@launch
        val old = company.value.agreementFile
        repo.updateCompany { it.copy(agreementName = null, agreementFile = null, agreementText = null, agreementEditedAt = null) }
        if (old != null) withContext(Dispatchers.IO) { File(filesDir, old).delete() }
        toast("Using the VIMS agreement")
    }

    /**
     * Edit agreement → Save (admins only): the company's edited copy becomes the agreement in use and replaces an uploaded
     * file. The VIMS agreement itself never changes. TODO(backend): sync the edited agreement to the server.
     */
    fun saveAgreementText(text: String) = viewModelScope.launch {
        if (!isAdmin) return@launch
        val old = company.value.agreementFile
        repo.updateCompany { it.copy(agreementText = text, agreementEditedAt = System.currentTimeMillis(), agreementName = null, agreementFile = null) }
        if (old != null) withContext(Dispatchers.IO) { File(filesDir, old).delete() }
        toast("Your edited agreement is now in use")
    }

    /** What the agreement viewer shows: the company's edited text (whole, never filtered by state), else the VIMS agreement. */
    fun agreementPieces(c: CompanyProfile, state: String): List<com.vims.app.data.AgreementPiece> =
        c.editedAgreement?.let { com.vims.app.data.AgreementText.pieces(it) } ?: agreement.pieces(c.name, state, config::stateName)

    /** Editor prefill: the company's edited version, else the whole VIMS agreement as plain text with the company name filled in. */
    fun agreementEditorText(): String = company.value.let { c -> c.editedAgreement ?: agreement.plainText(c.name, config::stateName) }

    /** Unsaved editor text by editor visit, kept here (not in saved instance state — it can be ~100 KB) across rotation. */
    val agreementDrafts = HashMap<String, androidx.compose.runtime.MutableState<androidx.compose.ui.text.input.TextFieldValue>>()

    data class AgreementPdfFile(val file: File, val pages: Int)

    /** Download: renders what the viewer shows into cache/agreement/Inspection-Agreement-<Company-Name>.pdf (shared via FileProvider). */
    suspend fun buildAgreementPdf(state: String): AgreementPdfFile? = withContext(Dispatchers.IO) {
        val c = company.value
        val dir = File(getApplication<Application>().cacheDir, "agreement")
        val f = File(dir, agreementPdfName(c.name))
        try {
            dir.listFiles()?.forEach { it.delete() } // only the latest download is kept
            AgreementPdfFile(f, com.vims.app.report.AgreementPdf(getApplication()).write(agreementPieces(c, state), c.name, f))
        } catch (t: Throwable) {
            android.util.Log.e("VIMS-Agreement", "Could not build the agreement PDF", t); null
        }
    }

    /** Save to device: copies the generated PDF to the document the user picked (ACTION_CREATE_DOCUMENT). */
    fun saveAgreementPdf(src: File, uri: Uri) = viewModelScope.launch {
        val ok = withContext(Dispatchers.IO) {
            try { getApplication<Application>().contentResolver.openOutputStream(uri, "w")?.use { out -> src.inputStream().use { it.copyTo(out) } } != null } catch (_: Exception) { false }
        }
        toast(if (ok) "Saved ${src.name}" else "Could not save the PDF")
    }

    fun saveFeedbackEmail(email: String): Boolean {
        val v = email.trim()
        if (v.isEmpty() || !v.contains("@")) { toast("Enter a valid email"); return false }
        repo.updatePlatform { it.copy(feedbackEmail = v) }; toast("Feedback email saved"); return true
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
            repo.updateAccount { it.copy(active = true, cancelled = false, cardLast4 = r.cardLast4, subscribedEpochDay = LocalDate.now().toEpochDay()) }
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

    companion object {
        /** "Inspection-Agreement-<Company-Name>.pdf" (letters and digits kept, everything else becomes "-"). */
        fun agreementPdfName(company: String): String =
            "Inspection-Agreement" + company.replace(Regex("[^A-Za-z0-9]+"), "-").trim('-').let { if (it.isEmpty()) "" else "-$it" } + ".pdf"
    }

    /** Debug-only helper (screenshots): force an inspection's depth. */
    fun debugSetDepth(id: String, depth: String) = repo.updateInspection(id) { it.copy(selections = it.selections.copy(depth = depth)) }
    /** Debug-only helper (screenshots / QA): set an inspection's property state (docs marked as provided). */
    fun debugSetState(id: String, state: String) = repo.updateInspection(id) {
        val docs = config.stateRule(state)?.docs.orEmpty().isNotEmpty()
        it.copy(selections = it.selections.copy(state = state.uppercase(), stateDocsAck = docs, stateDocsAckAt = if (docs) System.currentTimeMillis() else null,
            sendToAgent = config.stateRule(state)?.agentCopy ?: true))
    }
    suspend fun debugSignIn() {
        if (session.value != null) return
        val r = container.auth.signIn(com.vims.app.demo.DemoSeed.DEMO_EMAIL, com.vims.app.demo.DemoSeed.DEMO_PASSWORD)
        if (r is AuthResult.Success) repo.activate(r.session)
    }
}
