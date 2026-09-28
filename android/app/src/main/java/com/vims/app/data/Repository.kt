package com.vims.app.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File

/**
 * Offline-first local store. Every piece of state is an in-memory StateFlow backed by a JSON file in
 * filesDir; writes are applied to memory immediately and flushed to disk in order on a background thread.
 * Nothing requires a network. (Phase 2: SyncService pushes pending changes to the Laravel API.)
 */
interface VimsRepository {
    val root: File
    val session: StateFlow<Session?>
    val account: StateFlow<AccountState>
    val company: StateFlow<CompanyProfile>
    val settings: StateFlow<AppSettings>
    val edits: StateFlow<ChecklistEdits>
    val inspections: StateFlow<Map<String, InspectionBundle>>

    fun setSession(session: Session?)
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

    fun inspectionDir(id: String): File
    fun photoFile(photo: Photo): File = File(root.parentFile, photo.file)
}

@OptIn(ExperimentalCoroutinesApi::class)
class FileRepository(filesDir: File) : VimsRepository {
    override val root: File = File(filesDir, "vims").apply { mkdirs() }
    private val json = ChecklistLoader.json
    private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))

    private val sessionFile = File(root, "session.json")
    private val accountFile = File(root, "account.json")
    private val companyFile = File(root, "company.json")
    private val settingsFile = File(root, "settings.json")
    private val editsFile = File(root, "checklist-edits.json")
    private val inspRoot = File(root, "inspections").apply { mkdirs() }

    private val _session = MutableStateFlow(read(sessionFile, Session.serializer()))
    private val _account = MutableStateFlow(read(accountFile, AccountState.serializer()) ?: AccountState())
    private val _company = MutableStateFlow(read(companyFile, CompanyProfile.serializer()) ?: CompanyProfile())
    private val _settings = MutableStateFlow(read(settingsFile, AppSettings.serializer()) ?: AppSettings())
    private val _edits = MutableStateFlow(read(editsFile, ChecklistEdits.serializer()) ?: ChecklistEdits())
    private val _inspections = MutableStateFlow(loadInspections())

    override val session = _session.asStateFlow()
    override val account = _account.asStateFlow()
    override val company = _company.asStateFlow()
    override val settings = _settings.asStateFlow()
    override val edits = _edits.asStateFlow()
    override val inspections = _inspections.asStateFlow()

    private val answersSer = MapSerializer(String.serializer(), SectionAnswers.serializer())
    private val photosSer = ListSerializer(Photo.serializer())
    private val findingsSer = ListSerializer(Finding.serializer())
    private val defsSer = MapSerializer(String.serializer(), SectionDef.serializer())

    override fun setSession(session: Session?) {
        _session.value = session
        if (session == null) io.launch { sessionFile.delete() } else write(sessionFile, Session.serializer(), session)
    }

    override fun updateAccount(f: (AccountState) -> AccountState) { _account.update(f); write(accountFile, AccountState.serializer(), _account.value) }
    override fun updateCompany(f: (CompanyProfile) -> CompanyProfile) { _company.update(f); write(companyFile, CompanyProfile.serializer(), _company.value) }
    override fun updateSettings(f: (AppSettings) -> AppSettings) { _settings.update(f); write(settingsFile, AppSettings.serializer(), _settings.value) }
    override fun updateEdits(f: (ChecklistEdits) -> ChecklistEdits) { _edits.update(f); write(editsFile, ChecklistEdits.serializer(), _edits.value) }

    override fun inspectionDir(id: String): File = File(inspRoot, id).apply { mkdirs() }

    override fun putBundle(bundle: InspectionBundle) {
        _inspections.update { it + (bundle.id to bundle) }
        val dir = inspectionDir(bundle.id)
        write(File(dir, "inspection.json"), Inspection.serializer(), bundle.inspection)
        write(File(dir, "answers.json"), answersSer, bundle.answers)
        write(File(dir, "photos.json"), photosSer, bundle.photos)
        write(File(dir, "findings.json"), findingsSer, bundle.findings)
        write(File(dir, "checklist.json"), defsSer, bundle.defs)
    }

    private fun mutate(id: String, f: (InspectionBundle) -> InspectionBundle): InspectionBundle? {
        var out: InspectionBundle? = null
        _inspections.update { map -> val b = map[id] ?: return@update map; val n = f(b); out = n; map + (id to n) }
        return out
    }

    override fun updateInspection(id: String, f: (Inspection) -> Inspection) {
        mutate(id) { it.copy(inspection = f(it.inspection)) }?.let { write(File(inspectionDir(id), "inspection.json"), Inspection.serializer(), it.inspection) }
    }

    override fun updateAnswers(id: String, section: String, f: (SectionAnswers) -> SectionAnswers) {
        mutate(id) { b -> b.copy(answers = b.answers + (section to f(b.answers[section] ?: SectionAnswers()))) }
            ?.let { write(File(inspectionDir(id), "answers.json"), answersSer, it.answers) }
    }

    override fun updatePhotos(id: String, f: (List<Photo>) -> List<Photo>) {
        mutate(id) { it.copy(photos = f(it.photos)) }?.let { write(File(inspectionDir(id), "photos.json"), photosSer, it.photos) }
    }

    override fun updateFindings(id: String, f: (List<Finding>) -> List<Finding>) {
        mutate(id) { it.copy(findings = f(it.findings)) }?.let { write(File(inspectionDir(id), "findings.json"), findingsSer, it.findings) }
    }

    override fun updateDefs(id: String, defs: Map<String, SectionDef>) {
        mutate(id) { it.copy(defs = defs) }?.let { write(File(inspectionDir(id), "checklist.json"), defsSer, it.defs) }
    }

    private fun loadInspections(): Map<String, InspectionBundle> =
        (inspRoot.listFiles() ?: emptyArray()).filter { it.isDirectory }.mapNotNull { dir ->
            val insp = read(File(dir, "inspection.json"), Inspection.serializer()) ?: return@mapNotNull null
            InspectionBundle(
                inspection = insp,
                answers = read(File(dir, "answers.json"), MapSerializer(String.serializer(), SectionAnswers.serializer())) ?: emptyMap(),
                photos = read(File(dir, "photos.json"), ListSerializer(Photo.serializer())) ?: emptyList(),
                findings = read(File(dir, "findings.json"), ListSerializer(Finding.serializer())) ?: emptyList(),
                defs = read(File(dir, "checklist.json"), MapSerializer(String.serializer(), SectionDef.serializer())) ?: emptyMap(),
            )
        }.associateBy { it.id }

    private fun <T> read(file: File, ser: KSerializer<T>): T? = try {
        if (file.exists()) json.decodeFromString(ser, file.readText()) else null
    } catch (_: Exception) { null }

    /** Serialized immediately (snapshot of the value), written on the single-threaded IO queue via temp file + rename. */
    private fun <T> write(file: File, ser: KSerializer<T>, value: T) {
        val text = json.encodeToString(ser, value)
        io.launch {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(text)
            if (!tmp.renameTo(file)) { file.delete(); tmp.renameTo(file) }
        }
    }
}
