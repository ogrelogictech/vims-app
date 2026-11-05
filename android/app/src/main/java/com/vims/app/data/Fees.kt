package com.vims.app.data

import java.math.BigDecimal
import java.math.RoundingMode
import java.util.Locale

/**
 * `wizard.fees` (client Nov 4): the amounts of wizard step 4, added up exactly (in cents, never in Double). Pure Kotlin.
 * Bundled Secondary Testing = the selected options' amounts, utilities and testing together; Total = Inspection Fee + Bundled.
 */
object Fees {
    /** Largest amount a $ box takes (0 to 99,999.99). */
    const val MAX = 99_999.99

    data class Totals(val options: Map<String, Long>, val inspection: Long, val bundled: Long, val total: Long)

    /** Cents of an amount as typed ("150.5", "1,250", "$12"); 0 for empty, partial ("." ) or unreadable text. */
    fun cents(amount: String): Long = try {
        val c = amount.trim().removePrefix("$").replace(",", "")
        if (c.isEmpty() || c == ".") 0L else BigDecimal(c).setScale(2, RoundingMode.HALF_UP).movePointRight(2).toLong().coerceAtLeast(0L)
    } catch (_: NumberFormatException) { 0L }

    /** "150.00". */
    fun format(cents: Long): String = String.format(Locale.US, "%d.%02d", cents / 100, cents % 100)

    /** "1,500.00", for the wizard's read-only boxes. */
    fun grouped(cents: Long): String = String.format(Locale.US, "%,d.%02d", cents / 100, cents % 100)

    /** Agreement lines stay blank at zero. */
    fun agreementValue(cents: Long): String = if (cents > 0) format(cents) else ""

    /**
     * The totals for [sel]. With [areasLocked] (`wizard.areasLockedTypes`) the utility options aren't in use, so their kept
     * amounts don't count until another type unlocks them. An amount only counts while its option is selected.
     */
    fun totals(sel: WizardSelections, areasLocked: Boolean): Totals {
        val selected = (if (areasLocked) emptyList() else sel.utilities) + sel.tests
        val options = selected.distinct().associateWith { cents(sel.fees[it].orEmpty()) }.filterValues { it > 0 }
        val inspection = cents(sel.inspectionFee)
        val bundled = options.values.sum()
        return Totals(options, inspection, bundled, inspection + bundled)
    }
}
