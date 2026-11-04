package com.vims.app.services

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.ZoneOffset
import java.time.ZonedDateTime

/**
 * The access rules of shared `subscription.store`, as pure Kotlin (AccessRulesTest covers them):
 * allowed when any is true: verified owner code, device trial still running, active store subscription (including a grace
 * period, which Play reports as an active purchase), and, for a NEW inspection after the trial, at least one report credit.
 * Nothing here ever blocks opening, editing, exporting or emailing what is already saved.
 */
object Access {
    /** `subscription.store.offline`: the cached status holds until expiry plus 7 days when the store can't be reached. */
    const val OFFLINE_HOLD_MS = 7L * 24 * 60 * 60 * 1000

    fun canStartNewInspection(ownerVerified: Boolean, trialDaysLeft: Int, subscribed: Boolean, credits: Int): Boolean =
        ownerVerified || trialDaysLeft > 0 || subscribed || credits >= 1

    /** `subscription.store.reportCredit`: what generating this inspection's report costs. */
    fun reportGate(ownerVerified: Boolean, trialDaysLeft: Int, subscribed: Boolean, credits: Int, alreadyGenerated: Boolean): ReportGate = when {
        alreadyGenerated || ownerVerified || trialDaysLeft > 0 || subscribed -> ReportGate.FREE
        credits >= 1 -> ReportGate.USES_CREDIT
        else -> ReportGate.NEEDS_PURCHASE
    }

    /** A cached status with the store out of reach. A store that answers replaces the cache instead (see [BillingManager]). */
    fun cacheHolds(sub: CachedSub?, now: Long): Boolean = sub != null && now <= sub.expiryMillis + OFFLINE_HOLD_MS

    /**
     * The end of the billing period that contains [after]. Play's client API reports no expiry date without a server, so this
     * counts whole periods from the purchase time ([period] is the base plan: yearly, anything else counts as the shorter month).
     */
    fun periodEnd(purchaseTimeMillis: Long, yearly: Boolean, after: Long): Long {
        val start: ZonedDateTime = Instant.ofEpochMilli(purchaseTimeMillis).atZone(ZoneOffset.UTC)
        var n = 1L
        while (true) {
            val end = (if (yearly) start.plusYears(n) else start.plusMonths(n)).toInstant().toEpochMilli()
            if (end > after) return end
            n++
        }
    }

    /** Play's ISO 8601 billing period for the Plans screen: "P1M" = "1 month", "P1Y" = "1 year". */
    fun lengthLabel(iso: String): String {
        val m = Regex("^P(\\d+)([YMWD])$").find(iso) ?: return iso
        val n = m.groupValues[1].toInt()
        val unit = when (m.groupValues[2]) { "Y" -> "year"; "M" -> "month"; "W" -> "week"; else -> "day" }
        return "$n $unit" + if (n == 1) "" else "s"
    }
}

enum class ReportGate { FREE, USES_CREDIT, NEEDS_PURCHASE }

/** The last verified subscription: cached on this device, in [BillingSnapshot]. */
@Serializable
data class CachedSub(
    val token: String,
    /** "monthly" / "yearly" when known. */
    val basePlan: String? = null,
    val verifiedAtMillis: Long = 0,
    val expiryMillis: Long = 0,
    val autoRenewing: Boolean = true,
)

/** Everything billing keeps on the device. One value in one commit, so a credit and its purchase token can't half-save. */
@Serializable
data class BillingSnapshot(
    val sub: CachedSub? = null,
    /** A subscription was seen earlier and the store no longer reports it (wording only; gives no access). */
    val ended: Boolean = false,
    val credits: Int = 0,
    /** Purchase tokens already turned into credits: a consume that failed is retried without granting a second credit. */
    val creditedTokens: List<String> = emptyList(),
)
