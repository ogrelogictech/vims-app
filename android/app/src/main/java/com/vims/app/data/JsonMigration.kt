package com.vims.app.data

import com.vims.app.data.db.AnswerEntity
import com.vims.app.data.db.CompanyEntity
import com.vims.app.data.db.FindingEntity
import com.vims.app.data.db.InspectionEntity
import com.vims.app.data.db.KvEntity
import com.vims.app.data.db.PhotoEntity
import com.vims.app.data.db.VimsDao
import com.vims.app.services.LocalAuthService
import kotlinx.serialization.KSerializer
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File

/**
 * One-time import of the pre-Room JSON store (JSON files in filesDir/vims plus vims/inspections/<id>) into Room.
 * Everything in the old single-user store belonged to the demo account, so it is attached to that user + company;
 * photo/report/logo files move into the per-user / per-company folders. Old JSON files are deleted afterwards.
 */
object JsonMigration {
    private const val KEY = "migratedJsonStore"
    const val LEGACY_EMAIL = "jeremy@visionpropertyinspections.com"
    const val LEGACY_PASSWORD = "inspect2026"
    const val LEGACY_USER_ID = "demo-user-jeremy"
    const val LEGACY_COMPANY_ID = "demo-company-vpi"

    suspend fun runIfNeeded(filesDir: File, dao: VimsDao, config: ChecklistConfig) {
        if (dao.kv(KEY) != null) return
        val root = File(filesDir, "vims")
        val oldAccount = File(root, "account.json")
        val oldInspections = File(root, "inspections")
        if (!oldAccount.exists() && !oldInspections.exists()) { dao.putKv(KvEntity(KEY, "none")); return }
        val json = ChecklistLoader.json
        fun <T> read(f: File, ser: KSerializer<T>): T? = try { if (f.exists()) json.decodeFromString(ser, f.readText()) else null } catch (_: Exception) { null }

        if (dao.userByEmail(LEGACY_EMAIL) == null) {
            val account = read(oldAccount, AccountState.serializer()) ?: LocalAuthService.newAccount(config, "VIS-4827")
            var profile = read(File(root, "company.json"), CompanyProfile.serializer()) ?: CompanyProfile(name = "Vision Property Inspections")
            val edits = read(File(root, "checklist-edits.json"), ChecklistEdits.serializer()) ?: ChecklistEdits()
            val companyDir = File(root, "companies/$LEGACY_COMPANY_ID").apply { mkdirs() }
            fun moveCompanyFile(rel: String?): String? {
                val src = rel?.let { File(filesDir, it) }?.takeIf { it.exists() } ?: return rel
                val dst = File(companyDir, src.name); src.renameTo(dst)
                return dst.relativeTo(filesDir).path
            }
            profile = profile.copy(logoFile = moveCompanyFile(profile.logoFile), agreementFile = moveCompanyFile(profile.agreementFile))
            dao.insertCompany(CompanyEntity(LEGACY_COMPANY_ID, account.companyCode.ifBlank { "VIS-4827" }, json.encodeToString(CompanyProfile.serializer(), profile),
                json.encodeToString(AccountState.serializer(), account), json.encodeToString(ChecklistEdits.serializer(), edits), System.currentTimeMillis()))
            val settings = read(File(root, "settings.json"), AppSettings.serializer()) ?: AppSettings()
            dao.insertUser(LocalAuthService.newUser("Jeremy Heath", LEGACY_EMAIL, LEGACY_PASSWORD, LEGACY_COMPANY_ID, config)
                .copy(id = LEGACY_USER_ID, settingsJson = json.encodeToString(AppSettings.serializer(), settings)))
        }

        val userDir = File(root, "users/$LEGACY_USER_ID/inspections").apply { mkdirs() }
        (oldInspections.listFiles() ?: emptyArray()).filter { it.isDirectory }.forEach { dir ->
            val insp = read(File(dir, "inspection.json"), Inspection.serializer()) ?: return@forEach
            val oldPrefix = "vims/inspections/${insp.id}/"
            val newPrefix = "vims/users/$LEGACY_USER_ID/inspections/${insp.id}/"
            fun fix(p: String) = if (p.startsWith(oldPrefix)) newPrefix + p.removePrefix(oldPrefix) else p
            val answers = read(File(dir, "answers.json"), MapSerializer(String.serializer(), SectionAnswers.serializer())).orEmpty()
            val photos = read(File(dir, "photos.json"), ListSerializer(Photo.serializer())).orEmpty().map { it.copy(file = fix(it.file)) }
            val findings = read(File(dir, "findings.json"), ListSerializer(Finding.serializer())).orEmpty()
            val defs = File(dir, "checklist.json").takeIf { it.exists() }?.readText() ?: "{}"
            listOf("inspection.json", "answers.json", "photos.json", "findings.json", "checklist.json").forEach { File(dir, it).delete() }
            dir.renameTo(File(userDir, insp.id))
            val moved = insp.copy(reportFile = insp.reportFile?.let(::fix))
            dao.putBundle(
                InspectionEntity(insp.id, LEGACY_USER_ID, LEGACY_COMPANY_ID, json.encodeToString(Inspection.serializer(), moved), defs, System.currentTimeMillis()),
                answers.map { (k, v) -> AnswerEntity(insp.id, k, LEGACY_USER_ID, json.encodeToString(SectionAnswers.serializer(), v)) },
                photos.mapIndexed { i, p -> PhotoEntity(p.id, insp.id, LEGACY_USER_ID, i, json.encodeToString(Photo.serializer(), p)) },
                findings.mapIndexed { i, f -> FindingEntity(f.id, insp.id, LEGACY_USER_ID, i, json.encodeToString(Finding.serializer(), f)) },
            )
        }
        // An old signed-in session stays signed in, now as the migrated user.
        read(File(root, "session.json"), Session.serializer())?.let { s ->
            dao.putKv(KvEntity(RoomRepository.KEY_SESSION, json.encodeToString(Session.serializer(), s.copy(userId = LEGACY_USER_ID, companyId = LEGACY_COMPANY_ID, email = LEGACY_EMAIL))))
        }
        listOf("session.json", "account.json", "company.json", "settings.json", "checklist-edits.json").forEach { File(root, it).delete() }
        oldInspections.deleteRecursively()
        File(root, "company").deleteRecursively()
        dao.putKv(KvEntity(KEY, System.currentTimeMillis().toString()))
    }
}
