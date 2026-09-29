package com.vims.app.services

import com.vims.app.data.AccountState
import com.vims.app.data.AppSettings
import com.vims.app.data.ChecklistConfig
import com.vims.app.data.ChecklistEdits
import com.vims.app.data.ChecklistLoader
import com.vims.app.data.CompanyProfile
import com.vims.app.data.Inspector
import com.vims.app.data.Plan
import com.vims.app.data.Role
import com.vims.app.data.Session
import com.vims.app.data.VimsRepository
import com.vims.app.data.db.CompanyEntity
import com.vims.app.data.db.UserEntity
import com.vims.app.data.db.VimsDao
import com.vims.app.util.PasswordHasher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.util.Locale
import java.util.UUID

/*
 * Backend-dependent services. Phase 1 ships local stub implementations so the app is fully usable offline;
 * each stub is marked TODO(backend) and should be swapped for a Laravel API client in Phase 2.
 */

sealed interface AuthResult {
    data class Success(val session: Session) : AuthResult
    /** `field` names the form field the error belongs to (email, password, code…), or null for a general error. */
    data class Error(val message: String, val field: String? = null) : AuthResult
}

interface AuthService {
    suspend fun signIn(email: String, password: String): AuthResult
    suspend fun createAccount(name: String, company: String, email: String, password: String): AuthResult
    suspend fun joinCompany(name: String, email: String, code: String, password: String): AuthResult
    suspend fun sendPasswordReset(email: String): Boolean
    suspend fun companyExists(code: String): Boolean
    suspend fun signOut()
}

data class SubscriptionResult(val ok: Boolean, val cardLast4: String? = null, val message: String? = null)

interface SubscriptionService {
    /** Card details go straight to Square's tokenizer in production; the app never stores the card number. */
    suspend fun startSubscription(plan: Plan, seats: Int, cardNumber: String): SubscriptionResult
}

interface SyncService {
    /** Number of local changes waiting to upload. */
    fun pendingCount(): Int
    suspend fun syncNow(): Boolean
}

/**
 * TODO(backend): Laravel API — POST /auth/login, /auth/register, /companies/join, /auth/password/email.
 * Local stub: a users table (UUID id, unique lowercased email, name, companyId, salted PBKDF2 hash) and a companies table.
 * Create account = new user + new company (owner). Join with code = new user attached to that company.
 */
class LocalAuthService(private val dao: VimsDao, private val config: ChecklistConfig) : AuthService {
    private val json = ChecklistLoader.json

    private fun roleFor(email: String, account: AccountState): Role {
        val ins = account.inspectors.firstOrNull { it.email.equals(email, ignoreCase = true) }
        return when { ins == null -> Role.INSPECTOR; ins.owner -> Role.OWNER; ins.admin -> Role.ADMIN; else -> Role.INSPECTOR }
    }

    private fun account(c: CompanyEntity) = try { json.decodeFromString(AccountState.serializer(), c.accountJson) } catch (_: Exception) { AccountState() }

    override suspend fun signIn(email: String, password: String): AuthResult = withContext(Dispatchers.IO) {
        val e = email.trim().lowercase(Locale.US)
        val u = dao.userByEmail(e) ?: return@withContext AuthResult.Error("No account uses that email. Create an account or join a company with a code.", "email")
        if (!PasswordHasher.verify(password, u.salt, u.passwordHash)) return@withContext AuthResult.Error("That password isn't right.", "password")
        val c = dao.company(u.companyId) ?: return@withContext AuthResult.Error("This account's company is missing on this device.")
        AuthResult.Success(Session(u.name, u.email, roleFor(u.email, account(c)), userId = u.id, companyId = c.id))
    }

    override suspend fun createAccount(name: String, company: String, email: String, password: String): AuthResult = withContext(Dispatchers.IO) {
        val e = email.trim().lowercase(Locale.US)
        if (dao.userByEmail(e) != null) return@withContext AuthResult.Error("An account with that email already exists.", "email")
        val cid = UUID.randomUUID().toString()
        val acct = newAccount(config, joinCode(company)).copy(inspectors = listOf(Inspector(UUID.randomUUID().toString(), name.trim(), e, owner = true, admin = true)))
        dao.insertCompany(
            CompanyEntity(cid, acct.companyCode,
                json.encodeToString(CompanyProfile.serializer(), CompanyProfile(name = company.trim(), inspectorName = name.trim(), email = e)),
                json.encodeToString(AccountState.serializer(), acct),
                json.encodeToString(ChecklistEdits.serializer(), ChecklistEdits()), System.currentTimeMillis())
        )
        val u = newUser(name, e, password, cid, config)
        dao.insertUser(u)
        AuthResult.Success(Session(u.name, u.email, Role.OWNER, userId = u.id, companyId = cid))
    }

    override suspend fun joinCompany(name: String, email: String, code: String, password: String): AuthResult = withContext(Dispatchers.IO) {
        val e = email.trim().lowercase(Locale.US)
        val c = dao.companyByCode(normalizeCode(code)) ?: return@withContext AuthResult.Error("No company uses that code. Check it with your company admin.", "code")
        if (dao.userByEmail(e) != null) return@withContext AuthResult.Error("An account with that email already exists — sign in instead.", "email")
        val u = newUser(name, e, password, c.id, config)
        dao.insertUser(u)
        var acct = account(c)
        if (acct.inspectors.none { it.email.equals(e, true) }) {
            acct = acct.copy(inspectors = acct.inspectors + Inspector(UUID.randomUUID().toString(), name.trim(), e), seats = maxOf(acct.seats, acct.inspectors.size + 1))
            dao.updateCompanyAccount(c.id, json.encodeToString(AccountState.serializer(), acct))
        }
        AuthResult.Success(Session(u.name, u.email, roleFor(e, acct), userId = u.id, companyId = c.id))
    }

    override suspend fun companyExists(code: String): Boolean = withContext(Dispatchers.IO) { dao.companyByCode(normalizeCode(code)) != null }

    /** "vis4827" / "VIS-4827" → "VIS-4827" (stored form). */
    private fun normalizeCode(code: String): String = com.vims.app.util.formatJoinCode(code.uppercase(Locale.US).filter { it.isLetterOrDigit() })

    // TODO(backend): send the reset email from the server.
    override suspend fun sendPasswordReset(email: String): Boolean = email.isNotBlank()
    override suspend fun signOut() {}

    /** "Acme Home Inspections" → "ACM-4821" (unique). */
    private suspend fun joinCode(company: String): String {
        val letters = company.uppercase(Locale.US).filter { it in 'A'..'Z' }.padEnd(3, 'X').take(3)
        repeat(50) {
            val code = "$letters-${(1000..9999).random()}"
            if (dao.companyByCode(code) == null) return code
        }
        return "$letters-${UUID.randomUUID().toString().take(4).uppercase(Locale.US)}"
    }

    companion object {
        fun newAccount(config: ChecklistConfig, code: String) = AccountState(
            companyCode = code, plans = config.subscription.plans, extraInspectorMonthly = config.subscription.extraInspectorMonthly,
            planId = config.subscription.plans.firstOrNull()?.id ?: "app", trialDays = config.subscription.trialDays,
            trialStartEpochDay = LocalDate.now().toEpochDay(), feedbackEmail = config.support.feedbackEmail, seats = 1,
        )

        fun newUser(name: String, email: String, password: String, companyId: String, config: ChecklistConfig): UserEntity {
            val salt = PasswordHasher.newSalt()
            val settings = AppSettings(defaultDepth = config.wizard.defaults.depth, defaultCover = config.covers.defaultCover)
            return UserEntity(UUID.randomUUID().toString(), email.trim().lowercase(Locale.US), name.trim(), companyId, salt,
                PasswordHasher.hash(password, salt), ChecklistLoader.json.encodeToString(AppSettings.serializer(), settings), System.currentTimeMillis())
        }
    }
}

// TODO(backend): Laravel API + Square Subscriptions API. Replace the raw card fields with the Square
// In-App Payments SDK card entry (tokenized nonce); never send or persist the card number.
class LocalSubscriptionService : SubscriptionService {
    override suspend fun startSubscription(plan: Plan, seats: Int, cardNumber: String): SubscriptionResult {
        val digits = cardNumber.filter { it.isDigit() }
        return SubscriptionResult(ok = true, cardLast4 = if (digits.length >= 4) digits.takeLast(4) else "4242")
    }
}

// TODO(backend): Laravel API — upload pending inspections, photos, findings, and reports; pull checklist/plan edits.
class LocalSyncService(private val repo: VimsRepository) : SyncService {
    override fun pendingCount(): Int = repo.inspections.value.values.count { it.inspection.pendingSync }
    override suspend fun syncNow(): Boolean {
        // No network in Phase 1: mark everything as synced so the UI reflects a completed sync.
        repo.inspections.value.keys.forEach { id -> repo.updateInspection(id) { it.copy(pendingSync = false) } }
        repo.updateSettings { it.copy(lastSyncAt = System.currentTimeMillis()) }
        return true
    }
}

fun trialDaysLeft(trialDays: Int, trialStartEpochDay: Long, today: LocalDate = LocalDate.now()): Int =
    (trialDays - (today.toEpochDay() - trialStartEpochDay)).toInt().coerceAtLeast(0)
