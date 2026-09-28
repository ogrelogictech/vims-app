package com.vims.app.services

import com.vims.app.data.Plan
import com.vims.app.data.Role
import com.vims.app.data.Session
import com.vims.app.data.VimsRepository
import java.time.LocalDate

/*
 * Backend-dependent services. Phase 1 ships local stub implementations so the app is fully usable offline;
 * each stub is marked TODO(backend) and should be swapped for a Laravel API client in Phase 2.
 */

sealed interface AuthResult {
    data class Success(val session: Session) : AuthResult
    data class Error(val message: String) : AuthResult
}

interface AuthService {
    suspend fun signIn(email: String, password: String): AuthResult
    suspend fun createAccount(name: String, company: String, email: String, password: String): AuthResult
    suspend fun joinCompany(name: String, email: String, code: String): AuthResult
    suspend fun sendPasswordReset(email: String): Boolean
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

// TODO(backend): Laravel API — POST /auth/login, /auth/register, /companies/join, /auth/password/email.
class LocalAuthService(private val repo: VimsRepository) : AuthService {
    override suspend fun signIn(email: String, password: String): AuthResult {
        if (email.isBlank() || password.isBlank()) return AuthResult.Error("Enter your email and password")
        // Stub: any non-empty credentials sign in. Match a known inspector to pick up name + role.
        val acct = repo.account.value
        val known = acct.inspectors.firstOrNull { it.email.equals(email.trim(), ignoreCase = true) }
        val role = when { known == null -> Role.OWNER; known.owner -> Role.OWNER; known.admin -> Role.ADMIN; else -> Role.INSPECTOR }
        val name = known?.name ?: repo.company.value.inspectorName.ifBlank { email.substringBefore("@") }
        return AuthResult.Success(Session(name = name, email = email.trim(), role = role))
    }

    override suspend fun createAccount(name: String, company: String, email: String, password: String): AuthResult {
        if (name.isBlank() || email.isBlank() || password.isBlank()) return AuthResult.Error("Enter your name, email, and password")
        return AuthResult.Success(Session(name = name.trim(), email = email.trim(), role = Role.OWNER))
    }

    override suspend fun joinCompany(name: String, email: String, code: String): AuthResult {
        if (code.isBlank()) return AuthResult.Error("Enter the company code")
        return AuthResult.Success(Session(name = name.trim().ifBlank { email.substringBefore("@").ifBlank { "Inspector" } }, email = email.trim(), role = Role.INSPECTOR))
    }

    override suspend fun sendPasswordReset(email: String): Boolean = email.isNotBlank()
    override suspend fun signOut() {}
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
