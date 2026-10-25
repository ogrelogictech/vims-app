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
    suspend fun createAccount(name: String, company: String, email: String, password: String, eulaVersion: String): AuthResult
    suspend fun joinCompany(name: String, email: String, code: String, password: String, eulaVersion: String): AuthResult
    suspend fun sendPasswordReset(email: String): Boolean
    suspend fun companyExists(code: String): Boolean
    suspend fun signOut()
}

/** [cardId] = Square's card-on-file id once the backend exists (TODO(backend): Square Cards API); null in the local stub. */
data class SubscriptionResult(val ok: Boolean, val cardLast4: String? = null, val message: String? = null, val cardId: String? = null)

interface SubscriptionService {
    /**
     * Card details go straight to Square's tokenizer in production; the app never stores the card number.
     * [cardNumber] null = charge the card on file (TODO(backend): Square Cards API card id).
     */
    suspend fun startSubscription(plan: Plan, seats: Int, cardNumber: String?): SubscriptionResult
    /** Stops renewal at the end of the current period (no refunds / proration — EULA 12.3). */
    suspend fun cancelSubscription(): Boolean
    suspend fun resumeSubscription(): Boolean
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
class LocalAuthService(private val dao: VimsDao, private val config: ChecklistConfig, private val deviceTrial: DeviceTrial? = null) : AuthService {
    private val json = ChecklistLoader.json

    private fun roleFor(email: String, account: AccountState): Role {
        val ins = account.inspectors.firstOrNull { it.email.equals(email, ignoreCase = true) }
        return when { ins == null -> Role.INSPECTOR; ins.owner -> Role.OWNER; ins.admin -> Role.ADMIN; else -> Role.INSPECTOR }
    }

    private fun account(c: CompanyEntity) = try { json.decodeFromString(AccountState.serializer(), c.accountJson) } catch (_: Exception) { AccountState() }

    override suspend fun signIn(email: String, password: String): AuthResult = withContext(Dispatchers.IO) {
        val e = email.trim().lowercase(Locale.US)
        val u = dao.userByEmail(e) ?: return@withContext AuthResult.Error("No account found for that email. Check it, or create an account / join a company with a code.", "email")
        if (!PasswordHasher.verify(password, u.salt, u.passwordHash)) return@withContext AuthResult.Error("Incorrect password. Try again or tap Forgot password.", "password")
        val c = dao.company(u.companyId) ?: return@withContext AuthResult.Error("This account's company is missing on this device.")
        AuthResult.Success(Session(u.name, u.email, roleFor(u.email, account(c)), userId = u.id, companyId = c.id))
    }

    override suspend fun createAccount(name: String, company: String, email: String, password: String, eulaVersion: String): AuthResult = withContext(Dispatchers.IO) {
        val e = email.trim().lowercase(Locale.US)
        if (dao.userByEmail(e) != null) return@withContext AuthResult.Error("An account with that email already exists.", "email")
        val cid = UUID.randomUUID().toString()
        // One free trial per device (client Oct 25): the first company created here starts the device's trial; any later
        // company starts with the trial already used (Subscribe shown). TODO(backend): see [DeviceTrial].
        val today = LocalDate.now().toEpochDay()
        val trialUsed = deviceTrial?.used == true
        val acct = newAccount(config, joinCode(company)).copy(
            inspectors = listOf(Inspector(UUID.randomUUID().toString(), name.trim(), e, owner = true, admin = true)),
            trialStartEpochDay = if (trialUsed) today - config.subscription.trialDays else today,
            trialUsedOnDevice = trialUsed,
        )
        dao.insertCompany(
            CompanyEntity(cid, acct.companyCode,
                json.encodeToString(CompanyProfile.serializer(), CompanyProfile(name = company.trim(), inspectorName = name.trim(), email = e)),
                json.encodeToString(AccountState.serializer(), acct),
                json.encodeToString(ChecklistEdits.serializer(), ChecklistEdits()), System.currentTimeMillis())
        )
        // TODO(backend): send the EULA acceptance (version + time) to the server.
        val u = newUser(name, e, password, cid, config).copy(eulaVersion = eulaVersion, eulaAcceptedAt = System.currentTimeMillis())
        dao.insertUser(u)
        if (!trialUsed) deviceTrial?.record(today)
        AuthResult.Success(Session(u.name, u.email, Role.OWNER, userId = u.id, companyId = cid, eulaVersion = eulaVersion))
    }

    override suspend fun joinCompany(name: String, email: String, code: String, password: String, eulaVersion: String): AuthResult = withContext(Dispatchers.IO) {
        val e = email.trim().lowercase(Locale.US)
        val c = dao.companyByCode(normalizeCode(code)) ?: return@withContext AuthResult.Error("No company uses that code. Check it with your company admin.", "code")
        if (dao.userByEmail(e) != null) return@withContext AuthResult.Error("An account with that email already exists — sign in instead.", "email")
        val u = newUser(name, e, password, c.id, config).copy(eulaVersion = eulaVersion, eulaAcceptedAt = System.currentTimeMillis())
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
    override suspend fun startSubscription(plan: Plan, seats: Int, cardNumber: String?): SubscriptionResult {
        if (cardNumber == null) return SubscriptionResult(ok = true) // card on file
        val digits = cardNumber.filter { it.isDigit() }
        return SubscriptionResult(ok = true, cardLast4 = if (digits.length >= 4) digits.takeLast(4) else "4242")
    }

    // TODO(backend): Square Subscriptions API — cancel at period end / resume.
    override suspend fun cancelSubscription(): Boolean = true
    override suspend fun resumeSubscription(): Boolean = true
}

// TODO(backend): Laravel API — upload pending inspections, photos, findings, and reports; pull checklist/plan edits.
class LocalSyncService(private val repo: VimsRepository) : SyncService {
    override fun pendingCount(): Int = repo.inspections.value.values.count { it.inspection.pendingSync }
    override suspend fun syncNow(): Boolean {
        // No network in Phase 1: mark everything as synced so the UI reflects a completed sync.
        repo.inspections.value.values.filter { it.inspection.pendingSync }.forEach { b -> repo.updateInspection(b.id) { it.copy(pendingSync = false) } }
        repo.updateSettings { it.copy(lastSyncAt = System.currentTimeMillis()) }
        return true
    }
}

fun trialDaysLeft(trialDays: Int, trialStartEpochDay: Long, today: LocalDate = LocalDate.now()): Int =
    (trialDays - (today.toEpochDay() - trialStartEpochDay)).toInt().coerceAtLeast(0)

/**
 * Whether the company may start NEW inspections (client Oct 25): an active subscription (a cancelled one until the end of its
 * paid period, EULA 12.3) or free-look days left. Existing inspections and their reports stay available either way.
 */
fun hasAccess(a: AccountState, today: LocalDate = LocalDate.now()): Boolean {
    if (a.active) {
        val end = a.periodEndEpochDay
        if (!a.cancelled || end == null || today.toEpochDay() < end) return true
    }
    return trialDaysLeft(a.trialDays, a.trialStartEpochDay, today) > 0
}

/** The free look has run out and there is no subscription: show "trial ended" wording and the Subscribe prompt. */
fun trialEnded(a: AccountState, today: LocalDate = LocalDate.now()): Boolean = !hasAccess(a, today)

/**
 * One free trial per DEVICE (client Oct 25). The first trial start on this device is kept at app level — its own
 * SharedPreferences file `vims_device`, outside every account and company row — so a company created later on the same device
 * starts with the trial already used, and deleting an account or signing up again doesn't reset it. The demo company is not
 * a trial start. Upgrades from builds before v0.21.0 take the earliest trial start of the companies already on the device
 * ([backfill]).
 *
 * Auto Backup: this file is deliberately NOT excluded. Restoring it after a reinstall (or onto a new phone of the same Google
 * account) can only bring back "trial used" — it can never grant a new trial — while excluding it would hand out a fresh
 * trial on every reinstall. (Clearing app data / a reinstall without a backup still resets it on the device; only the server
 * can stop that.)
 *
 * TODO(backend): the server enforces one trial per device across reinstalls and accounts — the app sends ANDROID_ID
 * (Settings.Secure, per app-signing key + user) with a Play Integrity token at sign-up / trial start, and the server refuses a
 * second trial for the same device (and the same email / payment card).
 */
class DeviceTrial(context: android.content.Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, android.content.Context.MODE_PRIVATE)

    /** Epoch day of the first free-trial start on this device, or null when no trial has started here. */
    val firstStartEpochDay: Long? get() = prefs.getLong(KEY_FIRST_START, NONE).takeIf { it != NONE }
    val used: Boolean get() = firstStartEpochDay != null

    /** Records the device's first trial start (never moves an existing record). */
    fun record(epochDay: Long) { if (!used) prefs.edit().putLong(KEY_FIRST_START, epochDay).commit() }

    /** Upgrade from < v0.21.0: the earliest trial start among the companies already created on this device (not the demo). */
    fun backfill(companyTrialStarts: List<Long>) { companyTrialStarts.filter { it > 0 }.minOrNull()?.let { record(it) } }

    /** Debug builds only (testers: `--ez resetDeviceTrial true`). */
    fun clear() { prefs.edit().remove(KEY_FIRST_START).apply() }

    companion object {
        const val PREFS = "vims_device"
        private const val KEY_FIRST_START = "trialFirstStartEpochDay"
        private const val NONE = Long.MIN_VALUE
    }
}
