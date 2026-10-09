package com.vims.app.data

import com.vims.app.data.db.AnswerEntity
import com.vims.app.data.db.FindingEntity
import com.vims.app.data.db.InspectionEntity
import com.vims.app.data.db.KvEntity
import com.vims.app.data.db.PhotoEntity
import com.vims.app.data.db.VimsDao
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File

/**
 * Offline-first local store scoped to the signed-in user. After [activate] the StateFlows hold ONLY that user's
 * inspections and that user's company (profile, plans, inspectors, subscription, checklist edits); signing out
 * clears them. Writes update memory immediately and are persisted to Room in order on a background thread.
 */
interface VimsRepository {
    val root: File
    val session: StateFlow<Session?>
    val account: StateFlow<AccountState>
    val company: StateFlow<CompanyProfile>
    val settings: StateFlow<AppSettings>
    val edits: StateFlow<ChecklistEdits>
    val inspections: StateFlow<Map<String, InspectionBundle>>
    /** Platform-level settings (not scoped to a user or company). */
    val platform: StateFlow<PlatformSettings>
    fun updatePlatform(f: (PlatformSettings) -> PlatformSettings)

    /** Loads the user's + company's data (or clears everything for null). `persist` remembers it for the next launch. */
    suspend fun activate(session: Session?, persist: Boolean = true)

    fun updateAccount(f: (AccountState) -> AccountState)
    fun updateCompany(f: (CompanyProfile) -> CompanyProfile)
    fun updateSettings(f: (AppSettings) -> AppSettings)
    fun updateEdits(f: (ChecklistEdits) -> ChecklistEdits)

    fun putBundle(bundle: InspectionBundle)
    fun updateInspection(id: String, f: (Inspection) -> Inspection)
    fun updateAnswers(id: String, section: String, f: (SectionAnswers) -> SectionAnswers)
    fun updatePhotos(id: String, f: (List<Photo>) -> List<Photo>)
    fun updateFindings(id: String, f: (List<Finding>) -> List<Finding>)
    fun updateDefs(id: String, defs: Map<String, SectionDef>)

    /** vims/users/<userId>/inspections/<id> */
    fun inspectionDir(id: String): File
    /** vims/companies/<companyId> (logo, agreement) */
    fun companyDir(): File
    fun photoFile(photo: Photo): File = File(root.parentFile, photo.file)
    /** Company members' profile photos by lowercased email (for the Inspectors list); includes the signed-in user. */
    val memberPhotos: StateFlow<Map<String, String>>
    /** The signed-in user's own profile photo (relative to filesDir), or null → initials. */
    val userPhoto: StateFlow<String?>
    fun setUserPhoto(relative: String?)
    /** Deletes the signed-in user (and, for a sole owner, the company). Returns an error message when blocked. */
    suspend fun deleteAccount(): String?

    /** Records the signed-in user's EULA acceptance. */
    suspend fun acceptEula(version: String)
    /** Waits until every queued write has reached the database (tests / sign-out). */
    suspend fun flush()
}

@OptIn(ExperimentalCoroutinesApi::class)
class RoomRepository(filesDir: File, private val dao: VimsDao, private val owners: PlatformOwners = PlatformOwners(emptyList())) : VimsRepository {
    override val root: File = File(filesDir, "vims").apply { mkdirs() }
    private val json = ChecklistLoader.json
    private val writer = Dispatchers.IO.limitedParallelism(1)
    private val io = CoroutineScope(SupervisorJob() + writer)

    private val _session = MutableStateFlow<Session?>(null)
    private val _account = MutableStateFlow(AccountState())
    private val _company = MutableStateFlow(CompanyProfile())
    private val _settings = MutableStateFlow(AppSettings())
    private val _edits = MutableStateFlow(ChecklistEdits())
    private val _inspections = MutableStateFlow<Map<String, InspectionBundle>>(emptyMap())
    private val _platform = MutableStateFlow(PlatformSettings())
    private val _memberPhotos = MutableStateFlow<Map<String, String>>(emptyMap())
    private val _userPhoto = MutableStateFlow<String?>(null)
    override val memberPhotos = _memberPhotos.asStateFlow()
    override val userPhoto = _userPhoto.asStateFlow()

    override val session = _session.asStateFlow()
    override val account = _account.asStateFlow()
    override val company = _company.asStateFlow()
    override val settings = _settings.asStateFlow()
    override val edits = _edits.asStateFlow()
    override val inspections = _inspections.asStateFlow()
    override val platform = _platform.asStateFlow()

    /** Loads platform settings from the kv table, seeding them from the shared JSON defaults the first time. */
    suspend fun loadPlatform(defaults: PlatformSettings) = withContext(writer) {
        val raw = dao.kv(KEY_PLATFORM)
        _platform.value = raw?.let { dec(PlatformSettings.serializer(), it, defaults) } ?: defaults.also { dao.putKv(KvEntity(KEY_PLATFORM, enc(PlatformSettings.serializer(), it))) }
    }

    override fun updatePlatform(f: (PlatformSettings) -> PlatformSettings) {
        if (_session.value?.platformOwner != true) return // only the VIMS platform owner may change these
        _platform.update(f); val v = enc(PlatformSettings.serializer(), _platform.value); write { dao.putKv(KvEntity(KEY_PLATFORM, v)) }
    }

    private val defsSer = MapSerializer(String.serializer(), SectionDef.serializer())
    private fun <T> enc(ser: KSerializer<T>, v: T) = json.encodeToString(ser, v)
    private fun <T> dec(ser: KSerializer<T>, s: String, fallback: T): T = try { json.decodeFromString(ser, s) } catch (_: Exception) { fallback }

    private val uid get() = _session.value?.userId
    private val cid get() = _session.value?.companyId

    override suspend fun activate(session: Session?, persist: Boolean) = withContext(writer) {
        if (session == null) {
            if (persist) dao.deleteKv(KEY_SESSION)
            clearMemory()
            return@withContext
        }
        val user = dao.user(session.userId)
        val co = dao.company(session.companyId)
        if (user == null || co == null) { clearMemory(); return@withContext }
        // TODO(backend): the platform-owner flag comes from the server; locally it is `support.platformOwners` in the shared JSON.
        @Suppress("NAME_SHADOWING") val session = session.copy(platformOwner = owners.isOwner(user.email), eulaVersion = user.eulaVersion)
        val ins = dao.inspectionsFor(user.id)
        val answers = dao.answersFor(user.id).groupBy { it.inspectionId }
        val photos = dao.photosFor(user.id).groupBy { it.inspectionId }
        val findings = dao.findingsFor(user.id).groupBy { it.inspectionId }
        val bundles = ins.mapNotNull { e ->
            val insp = try { json.decodeFromString(Inspection.serializer(), e.json) } catch (_: Exception) { return@mapNotNull null }
            InspectionBundle(
                inspection = insp,
                answers = answers[e.id].orEmpty().associate { it.section to dec(SectionAnswers.serializer(), it.json, SectionAnswers()) },
                photos = photos[e.id].orEmpty().mapNotNull { p -> try { json.decodeFromString(Photo.serializer(), p.json) } catch (_: Exception) { null } },
                findings = findings[e.id].orEmpty().mapNotNull { f -> try { json.decodeFromString(Finding.serializer(), f.json) } catch (_: Exception) { null } },
                defs = dec(defsSer, e.defsJson, emptyMap()),
            )
        }.associateBy { it.id }
        _company.value = dec(CompanyProfile.serializer(), co.profileJson, CompanyProfile()).copy(agreementText = co.agreementText, agreementEditedAt = co.agreementEditedAt)
        _account.value = dec(AccountState.serializer(), co.accountJson, AccountState())
        _edits.value = dec(ChecklistEdits.serializer(), co.editsJson, ChecklistEdits())
        _settings.value = dec(AppSettings.serializer(), user.settingsJson, AppSettings())
        _inspections.value = bundles
        _userPhoto.value = user.photoFile
        _memberPhotos.value = dao.usersInCompany(co.id).mapNotNull { u -> u.photoFile?.let { u.email.lowercase() to it } }.toMap()
        _session.value = session
        if (persist) dao.putKv(KvEntity(KEY_SESSION, enc(Session.serializer(), session)))
    }

    private fun clearMemory() {
        _session.value = null
        _userPhoto.value = null; _memberPhotos.value = emptyMap()
        _inspections.value = emptyMap()
        _account.value = AccountState(); _company.value = CompanyProfile(); _settings.value = AppSettings(); _edits.value = ChecklistEdits()
    }

    /** Restores the last session (app start). */
    suspend fun restore(): Session? {
        val raw = withContext(writer) { dao.kv(KEY_SESSION) } ?: return null
        val s = try { json.decodeFromString(Session.serializer(), raw) } catch (_: Exception) { return null }
        activate(s)
        return _session.value
    }

    override suspend fun flush() { withContext(writer) {} }

    override fun setUserPhoto(relative: String?) {
        val s = _session.value ?: return
        _userPhoto.value = relative
        _memberPhotos.update { m -> if (relative == null) m - s.email.lowercase() else m + (s.email.lowercase() to relative) }
        write { dao.updateUserPhoto(s.userId, relative) }
    }

    override suspend fun deleteAccount(): String? = withContext(writer) {
        val s = _session.value ?: return@withContext "Not signed in"
        val others = dao.usersInCompany(s.companyId).filter { it.id != s.userId }
        val acct = _account.value
        val isOwner = acct.inspectors.firstOrNull { it.email.equals(s.email, true) }?.owner == true || s.role == Role.OWNER
        if (isOwner && others.isNotEmpty()) return@withContext "Make another admin the owner first (Inspectors → Make owner)."
        dao.deleteInspectionsOf(s.userId) // answers, photos, findings cascade
        File(root, "users/${s.userId}").deleteRecursively()
        if (isOwner) {
            // Sole owner: the company goes too (its users row cascades). TODO(backend): cancel the Square subscription server-side.
            dao.deleteCompany(s.companyId)
            File(root, "companies/${s.companyId}").deleteRecursively()
        } else {
            dao.deleteUser(s.userId)
            val updated = acct.copy(inspectors = acct.inspectors.filterNot { it.email.equals(s.email, true) })
            dao.updateCompanyAccount(s.companyId, enc(AccountState.serializer(), updated))
        }
        dao.deleteKv(KEY_SESSION)
        clearMemory()
        null
    }

    override suspend fun acceptEula(version: String) = withContext(writer) {
        val s = _session.value ?: return@withContext
        dao.acceptEula(s.userId, version, System.currentTimeMillis())
        val n = s.copy(eulaVersion = version)
        _session.value = n
        dao.putKv(KvEntity(KEY_SESSION, enc(Session.serializer(), n)))
    }

    private fun write(block: suspend () -> Unit) { io.launch { block() } }

    override fun updateAccount(f: (AccountState) -> AccountState) {
        val c = cid ?: return; _account.update(f); val v = enc(AccountState.serializer(), _account.value); write { dao.updateCompanyAccount(c, v) }
    }
    override fun updateCompany(f: (CompanyProfile) -> CompanyProfile) {
        val c = cid ?: return; _company.update(f); val p = _company.value; val v = enc(CompanyProfile.serializer(), p)
        // The edited agreement lives in its own columns (not in profileJson). TODO(backend): sync the edited agreement to the server.
        write { dao.updateCompanyRecord(c, v, p.agreementText, p.agreementEditedAt) }
    }
    override fun updateSettings(f: (AppSettings) -> AppSettings) {
        val u = uid ?: return; _settings.update(f); val v = enc(AppSettings.serializer(), _settings.value); write { dao.updateUserSettings(u, v) }
    }
    override fun updateEdits(f: (ChecklistEdits) -> ChecklistEdits) {
        val c = cid ?: return; _edits.update(f); val v = enc(ChecklistEdits.serializer(), _edits.value); write { dao.updateCompanyEdits(c, v) }
    }

    override fun inspectionDir(id: String): File = File(root, "users/${uid ?: "_"}/inspections/$id").apply { mkdirs() }
    override fun companyDir(): File = File(root, "companies/${cid ?: "_"}").apply { mkdirs() }

    private fun entities(b: InspectionBundle, userId: String, companyId: String) = Triple(
        InspectionEntity(b.id, userId, companyId, enc(Inspection.serializer(), b.inspection), enc(defsSer, b.defs), System.currentTimeMillis()),
        b.answers.map { (sec, a) -> AnswerEntity(b.id, sec, userId, enc(SectionAnswers.serializer(), a)) },
        b.photos.mapIndexed { i, p -> PhotoEntity(p.id, b.id, userId, i, enc(Photo.serializer(), p)) } to
            b.findings.mapIndexed { i, f -> FindingEntity(f.id, b.id, userId, i, enc(Finding.serializer(), f)) },
    )

    override fun putBundle(bundle: InspectionBundle) {
        val u = uid ?: return; val c = cid ?: return
        _inspections.update { it + (bundle.id to bundle) }
        val (i, a, pf) = entities(bundle, u, c)
        write { dao.putBundle(i, a, pf.first, pf.second) }
    }

    private fun mutate(id: String, f: (InspectionBundle) -> InspectionBundle): InspectionBundle? {
        var out: InspectionBundle? = null
        _inspections.update { map -> val b = map[id] ?: return@update map; val n = f(b); out = n; map + (id to n) }
        return out
    }

    override fun updateInspection(id: String, f: (Inspection) -> Inspection) {
        val u = uid ?: return
        mutate(id) { it.copy(inspection = f(it.inspection)) }?.let { b -> val v = enc(Inspection.serializer(), b.inspection); write { dao.updateInspectionJson(id, u, v, System.currentTimeMillis()) } }
    }

    override fun updateAnswers(id: String, section: String, f: (SectionAnswers) -> SectionAnswers) {
        val u = uid ?: return
        mutate(id) { b -> b.copy(answers = b.answers + (section to f(b.answers[section] ?: SectionAnswers()))) }
            ?.let { b -> val v = enc(SectionAnswers.serializer(), b.answers.getValue(section)); write { dao.upsertAnswer(AnswerEntity(id, section, u, v)) } }
    }

    override fun updatePhotos(id: String, f: (List<Photo>) -> List<Photo>) {
        val u = uid ?: return
        mutate(id) { it.copy(photos = f(it.photos)) }?.let { b ->
            val rows = b.photos.mapIndexed { i, p -> PhotoEntity(p.id, id, u, i, enc(Photo.serializer(), p)) }
            write { dao.replacePhotos(id, u, rows) }
        }
    }

    override fun updateFindings(id: String, f: (List<Finding>) -> List<Finding>) {
        val u = uid ?: return
        mutate(id) { it.copy(findings = f(it.findings)) }?.let { b ->
            val rows = b.findings.mapIndexed { i, x -> FindingEntity(x.id, id, u, i, enc(Finding.serializer(), x)) }
            write { dao.replaceFindings(id, u, rows) }
        }
    }

    override fun updateDefs(id: String, defs: Map<String, SectionDef>) {
        val u = uid ?: return
        mutate(id) { it.copy(defs = defs) }?.let { b -> val v = enc(defsSer, b.defs); write { dao.updateDefs(id, u, v) } }
    }

    companion object { const val KEY_SESSION = "session"; const val KEY_PLATFORM = "platformSettings" }
}

/**
 * VIMS platform owners (system admins) = `support.platformOwners` in vims-checklists.json (data v1.5), matched
 * case-insensitively on the trimmed email. Several addresses are allowed so there are always at least two system admins.
 * No password is stored or seeded for them: the owner creates an account / signs in with that email and their own
 * password, and gets the VIMS owner settings (Report quality copy, Feedback & support).
 * TODO(backend): the server owns this list and sends the flag with the session.
 */
class PlatformOwners(emails: List<String>) {
    private val set: Set<String> = emails.map { it.trim().lowercase(java.util.Locale.US) }.filter { it.isNotEmpty() }.toSet()
    fun isOwner(email: String): Boolean = email.trim().lowercase(java.util.Locale.US) in set
}
