package com.vims.app.util

import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** American English formatting everywhere (Locale.US). */
object Fmt {
    private val money = NumberFormat.getCurrencyInstance(Locale.US)
    private val longDate = DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US)
    private val shortDate = DateTimeFormatter.ofPattern("MMM d", Locale.US)
    private val dayHeader = DateTimeFormatter.ofPattern("EEE, MMM d", Locale.US)
    private val slashDate = DateTimeFormatter.ofPattern("MM/dd/yyyy", Locale.US)
    private val time12 = DateTimeFormatter.ofPattern("h:mm a", Locale.US)

    fun money(v: Double): String = money.format(v)
    fun price(v: Double): String = String.format(Locale.US, "%.2f", v)

    fun parseDate(iso: String): LocalDate? = try { LocalDate.parse(iso) } catch (_: Exception) { null }
    fun parseTime(hhmm: String): LocalTime? = try { LocalTime.parse(hhmm) } catch (_: Exception) { null }

    /** "Sep 28, 2026" */
    fun date(iso: String): String = parseDate(iso)?.format(longDate) ?: iso
    fun date(d: LocalDate): String = d.format(longDate)
    fun date(epochMs: Long): String = Instant.ofEpochMilli(epochMs).atZone(ZoneId.systemDefault()).toLocalDate().format(longDate)
    /** "Sep 28" */
    fun shortDate(iso: String): String = parseDate(iso)?.format(shortDate) ?: iso
    /** "Mon, Sep 28" */
    fun dayHeader(d: LocalDate): String = d.format(dayHeader)
    /** "09/28/2026" (report cover) */
    fun slash(iso: String): String = parseDate(iso)?.format(slashDate) ?: iso
    /** "9:30 AM" */
    fun time(hhmm: String): String = parseTime(hhmm)?.format(time12) ?: hhmm
    /** ("9:30", "AM") for the time lead tile */
    fun timeParts(hhmm: String): Pair<String, String> {
        val t = parseTime(hhmm) ?: return hhmm to ""
        val s = t.format(time12)
        return s.substringBefore(" ") to s.substringAfter(" ")
    }
}
