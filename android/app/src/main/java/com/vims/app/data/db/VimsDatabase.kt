package com.vims.app.data.db

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Transaction
import androidx.room.Upsert

/*
 * On-device database (Room / SQLite). MySQL is the Phase 2 *server* database behind the Laravel API; this is the
 * phone's offline store. Ownership:
 *   - user-owned (userId): inspections, section answers, photos, findings, reports (files in vims/users/<userId>/)
 *   - company-owned (companyId): company profile + logo, checklist customizations, plans, inspectors, subscription
 * Payloads are stored as JSON columns of the existing @Serializable models, keyed and indexed by owner.
 */

@Entity(tableName = "companies", indices = [Index(value = ["code"], unique = true)])
data class CompanyEntity(
    @PrimaryKey val id: String,
    /** Join code, e.g. VIS-4827 (uppercase). */
    val code: String,
    val profileJson: String,
    val accountJson: String,
    val editsJson: String,
    val createdAt: Long,
    /** The company's edited copy of the VIMS agreement (plain text), or null = not edited (v4). TODO(backend): sync to the server. */
    val agreementText: String? = null,
    /** When [agreementText] was saved (epoch ms), or null (v4). */
    val agreementEditedAt: Long? = null,
)

@Entity(
    tableName = "users",
    indices = [Index(value = ["email"], unique = true), Index("companyId")],
    foreignKeys = [ForeignKey(entity = CompanyEntity::class, parentColumns = ["id"], childColumns = ["companyId"], onDelete = ForeignKey.CASCADE)],
)
data class UserEntity(
    @PrimaryKey val id: String,
    /** Always lowercased + trimmed. */
    val email: String,
    val name: String,
    val companyId: String,
    // TODO(backend): Laravel API owns real credentials. Local stub keeps a salted PBKDF2 hash only.
    val salt: String,
    val passwordHash: String,
    val settingsJson: String,
    val createdAt: Long,
    /** EULA version the user accepted (eula.json "version") and when. TODO(backend): send to the server. */
    val eulaVersion: String? = null,
    val eulaAcceptedAt: Long? = null,
    /** The user's own profile photo (relative to filesDir: vims/users/<id>/profile.jpg), never the company logo. */
    val photoFile: String? = null,
)

@Entity(tableName = "inspections", indices = [Index("userId"), Index("companyId")])
data class InspectionEntity(
    @PrimaryKey val id: String,
    val userId: String,
    val companyId: String,
    val json: String,
    /** Checklist definition snapshot taken when the checklist was built. */
    val defsJson: String,
    val updatedAt: Long,
)

@Entity(
    tableName = "section_answers", primaryKeys = ["inspectionId", "section"], indices = [Index("inspectionId"), Index("userId")],
    foreignKeys = [ForeignKey(entity = InspectionEntity::class, parentColumns = ["id"], childColumns = ["inspectionId"], onDelete = ForeignKey.CASCADE)],
)
data class AnswerEntity(val inspectionId: String, val section: String, val userId: String, val json: String)

@Entity(
    tableName = "photos", indices = [Index("inspectionId"), Index("userId")],
    foreignKeys = [ForeignKey(entity = InspectionEntity::class, parentColumns = ["id"], childColumns = ["inspectionId"], onDelete = ForeignKey.CASCADE)],
)
data class PhotoEntity(@PrimaryKey val id: String, val inspectionId: String, val userId: String, val sortOrder: Int, val json: String)

@Entity(
    tableName = "findings", indices = [Index("inspectionId"), Index("userId")],
    foreignKeys = [ForeignKey(entity = InspectionEntity::class, parentColumns = ["id"], childColumns = ["inspectionId"], onDelete = ForeignKey.CASCADE)],
)
data class FindingEntity(@PrimaryKey val id: String, val inspectionId: String, val userId: String, val sortOrder: Int, val json: String)

/** Small key/value table: current session, one-time migration flags. */
@Entity(tableName = "kv")
data class KvEntity(@PrimaryKey val key: String, val value: String)

@Dao
interface VimsDao {
    // users / companies
    @Query("SELECT * FROM users WHERE email = :email LIMIT 1") suspend fun userByEmail(email: String): UserEntity?
    @Query("SELECT * FROM users WHERE id = :id LIMIT 1") suspend fun user(id: String): UserEntity?
    @Query("SELECT COUNT(*) FROM users") suspend fun userCount(): Int
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insertUser(u: UserEntity)
    @Query("UPDATE users SET settingsJson = :json WHERE id = :id") suspend fun updateUserSettings(id: String, json: String)
    @Query("UPDATE users SET name = :name WHERE id = :id") suspend fun updateUserName(id: String, name: String)
    @Query("UPDATE users SET eulaVersion = :version, eulaAcceptedAt = :at WHERE id = :id") suspend fun acceptEula(id: String, version: String, at: Long)
    @Query("UPDATE users SET photoFile = :file WHERE id = :id") suspend fun updateUserPhoto(id: String, file: String?)
    @Query("SELECT * FROM users WHERE companyId = :companyId") suspend fun usersInCompany(companyId: String): List<UserEntity>
    @Query("DELETE FROM inspections WHERE userId = :userId") suspend fun deleteInspectionsOf(userId: String)
    @Query("DELETE FROM users WHERE id = :id") suspend fun deleteUser(id: String)
    @Query("DELETE FROM companies WHERE id = :id") suspend fun deleteCompany(id: String)

    @Query("SELECT * FROM companies WHERE id = :id LIMIT 1") suspend fun company(id: String): CompanyEntity?
    @Query("SELECT * FROM companies WHERE code = :code LIMIT 1") suspend fun companyByCode(code: String): CompanyEntity?
    @Insert(onConflict = OnConflictStrategy.ABORT) suspend fun insertCompany(c: CompanyEntity)
    @Query("UPDATE companies SET profileJson = :json WHERE id = :id") suspend fun updateCompanyProfile(id: String, json: String)
    /** Profile JSON + the edited agreement in one statement, so clearing an upload and saving an edit can't half-apply. */
    @Query("UPDATE companies SET profileJson = :json, agreementText = :agreementText, agreementEditedAt = :agreementEditedAt WHERE id = :id")
    suspend fun updateCompanyRecord(id: String, json: String, agreementText: String?, agreementEditedAt: Long?)
    @Query("UPDATE companies SET accountJson = :json WHERE id = :id") suspend fun updateCompanyAccount(id: String, json: String)
    @Query("UPDATE companies SET editsJson = :json WHERE id = :id") suspend fun updateCompanyEdits(id: String, json: String)

    // inspections (always filtered by owner)
    @Query("SELECT * FROM inspections WHERE userId = :userId") suspend fun inspectionsFor(userId: String): List<InspectionEntity>
    @Query("SELECT * FROM section_answers WHERE userId = :userId") suspend fun answersFor(userId: String): List<AnswerEntity>
    @Query("SELECT * FROM photos WHERE userId = :userId ORDER BY sortOrder") suspend fun photosFor(userId: String): List<PhotoEntity>
    @Query("SELECT * FROM findings WHERE userId = :userId ORDER BY sortOrder") suspend fun findingsFor(userId: String): List<FindingEntity>

    @Upsert suspend fun upsertInspection(e: InspectionEntity)
    @Query("UPDATE inspections SET json = :json, updatedAt = :at WHERE id = :id AND userId = :userId") suspend fun updateInspectionJson(id: String, userId: String, json: String, at: Long)
    @Query("UPDATE inspections SET defsJson = :json WHERE id = :id AND userId = :userId") suspend fun updateDefs(id: String, userId: String, json: String)
    @Upsert suspend fun upsertAnswer(a: AnswerEntity)
    @Upsert suspend fun upsertAnswers(a: List<AnswerEntity>)
    @Query("DELETE FROM photos WHERE inspectionId = :id AND userId = :userId") suspend fun deletePhotos(id: String, userId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertPhotos(p: List<PhotoEntity>)
    @Query("DELETE FROM findings WHERE inspectionId = :id AND userId = :userId") suspend fun deleteFindings(id: String, userId: String)
    @Insert(onConflict = OnConflictStrategy.REPLACE) suspend fun insertFindings(f: List<FindingEntity>)

    @Transaction
    suspend fun replacePhotos(id: String, userId: String, p: List<PhotoEntity>) { deletePhotos(id, userId); insertPhotos(p) }

    @Transaction
    suspend fun replaceFindings(id: String, userId: String, f: List<FindingEntity>) { deleteFindings(id, userId); insertFindings(f) }

    @Transaction
    suspend fun putBundle(i: InspectionEntity, a: List<AnswerEntity>, p: List<PhotoEntity>, f: List<FindingEntity>) {
        upsertInspection(i); upsertAnswers(a); replacePhotos(i.id, i.userId, p); replaceFindings(i.id, i.userId, f)
    }

    // kv
    @Query("SELECT value FROM kv WHERE `key` = :key") suspend fun kv(key: String): String?
    @Upsert suspend fun putKv(e: KvEntity)
    @Query("DELETE FROM kv WHERE `key` = :key") suspend fun deleteKv(key: String)
}

@Database(
    entities = [CompanyEntity::class, UserEntity::class, InspectionEntity::class, AnswerEntity::class, PhotoEntity::class, FindingEntity::class, KvEntity::class],
    version = 4, exportSchema = true,
)
abstract class VimsDatabase : RoomDatabase() {
    abstract fun dao(): VimsDao

    companion object {
        /** v2: EULA acceptance on users. */
        private val MIGRATION_1_2 = object : androidx.room.migration.Migration(1, 2) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE users ADD COLUMN eulaVersion TEXT")
                db.execSQL("ALTER TABLE users ADD COLUMN eulaAcceptedAt INTEGER")
            }
        }

        /** v3: per-user profile photo. */
        private val MIGRATION_2_3 = object : androidx.room.migration.Migration(2, 3) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) { db.execSQL("ALTER TABLE users ADD COLUMN photoFile TEXT") }
        }

        /** v4: the company's edited inspection agreement (nullable columns; existing rows keep everything and read as "not edited"). */
        val MIGRATION_3_4 = object : androidx.room.migration.Migration(3, 4) {
            override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE companies ADD COLUMN agreementText TEXT")
                db.execSQL("ALTER TABLE companies ADD COLUMN agreementEditedAt INTEGER")
            }
        }

        fun open(context: Context): VimsDatabase =
            Room.databaseBuilder(context, VimsDatabase::class.java, "vims.db").addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4).build()
    }
}
