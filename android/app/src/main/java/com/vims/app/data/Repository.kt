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
    /** Waits until every queued write has reached the database (tests / sign-out). */
    suspend fun flush()
}

@OptIn(ExperimentalCoroutinesApi::class)
class RoomRepository(filesDir: File, private val dao: VimsDao) : VimsRepository {
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

    override val session = _session.asStateFlow()
    override val account = _account.asStateFlow()
    override val company = _company.asStateFlow()
    override val settings = _settings.asStateFlow()
    override val edits = _edits.asStateFlow()
    override val inspections = _inspections.asStateFlow()

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
        _company.value = dec(CompanyProfile.serializer(), co.profileJson, CompanyProfile())
        _account.value = dec(AccountState.serializer(), co.accountJson, AccountState())
        _edits.value = dec(ChecklistEdits.serializer(), co.editsJson, ChecklistEdits())
        _settings.value = dec(AppSettings.serializer(), user.settingsJson, AppSettings())
        _inspections.value = bundles
        _session.value = session
        if (persist) dao.putKv(KvEntity(KEY_SESSION, enc(Session.serializer(), session)))
    }

    private fun clearMemory() {
        _session.value = null
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

    private fun write(block: suspend () -> Unit) { io.launch { block() } }

    override fun updateAccount(f: (AccountState) -> AccountState) {
        val c = cid ?: return; _account.update(f); val v = enc(AccountState.serializer(), _account.value); write { dao.updateCompanyAccount(c, v) }
    }
    override fun updateCompany(f: (CompanyProfile) -> CompanyProfile) {
        val c = cid ?: return; _company.update(f); val v = enc(CompanyProfile.serializer(), _company.value); write { dao.updateCompanyProfile(c, v) }
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

    companion object { const val KEY_SESSION = "session" }
}
