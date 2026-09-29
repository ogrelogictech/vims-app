package com.vims.app.util

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.util.Locale

/*
 * One rule set for every form — docs/validation-rules.md.
 *  - Filters run while typing (every text field: no leading space, never two spaces in a row).
 *  - Checks run on submit and then live, so an error clears as soon as the value is valid.
 */

object Filters {
    private val multiSpace = Regex(" {2,}")

    /** Every text field: tabs/newlines in single-line fields become spaces, no leading space, no double spaces. */
    fun base(v: String, max: Int = 2000, multiline: Boolean = false): String {
        var s = if (multiline) v.replace('\t', ' ') else v.replace(Regex("[\\t\\r\\n]"), " ")
        s = s.replace(multiSpace, " ").trimStart(' ')
        if (multiline) s = s.replace(Regex("\n{3,}"), "\n\n")
        return s.take(max)
    }
    fun email(v: String) = v.filterNot { it.isWhitespace() }.take(254)
    fun password(v: String) = v.filterNot { it.isWhitespace() }.take(128)
    fun personName(v: String) = base(v.filter { it.isLetter() || it == ' ' || it in ".'-’" }, 60)
    fun companyName(v: String) = base(v, 80)
    fun address(v: String) = base(v, 120)
    /** Phone digits only (formatted on screen by [PhoneTransform]). */
    fun phone(v: String) = v.filter { it.isDigit() }.let { if (it.length == 11 && it.startsWith("1")) it.drop(1) else it }.take(10)
    /** Join code stored as letters+digits ("VIS4827"); [JoinCodeTransform] shows "VIS-4827". */
    fun joinCode(v: String): String {
        val up = v.uppercase(Locale.US).filter { it.isLetterOrDigit() }
        val letters = up.takeWhile { it.isLetter() }.take(3)
        val digits = up.drop(letters.length).filter { it.isDigit() }.take(4)
        return letters + if (letters.length == 3) digits else ""
    }
    fun license(v: String) = base(v.filter { it.isLetterOrDigit() || it == ' ' || it == '-' }, 20)
    fun policy(v: String) = v.filter { it.isLetterOrDigit() || it == '-' }.take(30)
    fun year(v: String) = v.filter { it.isDigit() }.take(4)
    /** Digits + one decimal point (sq ft, valuation, lot size, amps, `num` checklist items). */
    fun decimal(v: String, max: Int = 12): String {
        val sb = StringBuilder(); var dot = false
        v.forEach { c -> if (c.isDigit()) sb.append(c) else if ((c == '.') && !dot) { dot = true; sb.append(c) } }
        return sb.toString().take(max)
    }
    /** Digits, a comma is accepted and dropped (valuation "450,000"). */
    fun money(v: String) = decimal(v.replace(",", ""))
    fun temperature(v: String): String { val neg = v.trimStart().startsWith("-"); return (if (neg) "-" else "") + v.filter { it.isDigit() }.take(3) }
    fun url(v: String) = v.filterNot { it.isWhitespace() }.take(300)
    /** Digits + ".", at most 2 decimals. */
    fun price(v: String): String { val d = decimal(v, 10); val i = d.indexOf('.'); return if (i >= 0) d.take(i + 3) else d }
    fun cardNumber(v: String): String { val d = v.filter { it.isDigit() }; return d.take(if (CardBrand.of(d) == CardBrand.AMEX) 15 else 19) }
    /** Expiry digits "MMYY" ([ExpiryTransform] shows "MM/YY"). A leading 2–9 month gets a 0 prefix. */
    fun expiry(v: String): String { var d = v.filter { it.isDigit() }; if (d.length == 1 && d[0] in '2'..'9') d = "0$d"; return d.take(4) }
    fun cvc(v: String, amex: Boolean) = v.filter { it.isDigit() }.take(if (amex) 4 else 3)
    fun zip(v: String) = v.filter { it.isDigit() }.take(5)
    fun sectionName(v: String) = base(v, 60)
    fun question(v: String) = base(v, 120)
    fun option(v: String) = base(v, 60)
}

enum class CardBrand(val label: String) {
    VISA("Visa"), MASTERCARD("Mastercard"), AMEX("American Express"), DISCOVER("Discover"), UNKNOWN("");
    companion object {
        fun of(digits: String): CardBrand = when {
            digits.startsWith("34") || digits.startsWith("37") -> AMEX
            digits.startsWith("4") -> VISA
            digits.take(2).toIntOrNull() in 51..55 || digits.take(4).toIntOrNull() in 2221..2720 -> MASTERCARD
            digits.startsWith("6011") || digits.startsWith("65") || digits.take(3).toIntOrNull() in 644..649 -> DISCOVER
            else -> UNKNOWN
        }
    }
}

/** On-submit checks. Each returns an error message, or null when the value is fine. */
object Checks {
    private val emailRx = Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$")

    fun required(v: String, message: String): String? = if (v.trim().isEmpty()) message else null
    fun email(v: String, required: Boolean = true): String? = when {
        v.isBlank() -> if (required) "Enter an email address" else null
        v.length > 254 || !emailRx.matches(v.trim()) -> "Enter a valid email, like name@company.com"
        else -> null
    }
    fun passwordNew(v: String): String? = when { v.isEmpty() -> "Create a password"; v.length < 8 -> "Use at least 8 characters"; else -> null }
    fun passwordSignIn(v: String): String? = if (v.isEmpty()) "Enter your password" else null
    fun confirm(pw: String, confirm: String): String? = when { confirm.isEmpty() -> "Re-enter your password"; confirm != pw -> "Passwords don't match"; else -> null }
    fun phone(digits: String): String? = if (digits.isNotEmpty() && digits.length != 10) "Enter a 10-digit phone number" else null
    fun joinCode(raw: String): String? = when {
        raw.isEmpty() -> "Enter your company code"
        !Regex("^[A-Z]{3}[0-9]{4}$").matches(raw) -> "Codes are 3 letters and 4 numbers, like VIS-4827"
        else -> null
    }
    fun year(v: String): String? {
        if (v.isEmpty()) return null
        val y = v.toIntOrNull() ?: return "Enter a year"
        val now = LocalDate.now().year
        return if (y !in 1800..now) "Enter a year between 1800 and $now" else null
    }
    fun positive(v: String, label: String = "a number"): String? =
        if (v.isEmpty()) null else if ((v.replace(",", "").toDoubleOrNull() ?: 0.0) <= 0.0) "Enter $label greater than 0" else null
    fun temperature(v: String): String? {
        if (v.isEmpty() || v == "-") return if (v == "-") "Enter a temperature" else null
        val t = v.toIntOrNull() ?: return "Enter a temperature"
        return if (t !in -60..140) "Enter a temperature between −60 and 140 °F" else null
    }
    fun url(v: String): String? {
        if (v.isEmpty()) return null
        val ok = Regex("^https?://[^\\s/?#]+\\.[^\\s/?#]+.*$", RegexOption.IGNORE_CASE).matches(v)
        return if (!ok) "Enter a full link starting with https://" else null
    }
    fun price(v: String): String? {
        val p = v.toDoubleOrNull() ?: return "Enter a price"
        return if (p < 0.01 || p > 9999.99) "Enter a price from $0.01 to $9,999.99" else null
    }
    fun sectionName(v: String, exists: (String) -> Boolean): String? = when {
        v.trim().isEmpty() -> "Enter a section name"
        exists(v.trim()) -> "A section with that name already exists"
        else -> null
    }
    fun question(v: String): String? = if (v.trim().isEmpty()) "Enter the question text" else null
    fun option(v: String, existing: List<String>): String? = when {
        v.trim().isEmpty() -> "Enter an option"
        existing.any { it.equals(v.trim(), ignoreCase = true) } -> "That option is already on this question"
        else -> null
    }

    // ---- card entry (placeholder until Square's card SDK)
    fun luhn(d: String): Boolean {
        var sum = 0; var alt = false
        for (i in d.indices.reversed()) { var n = d[i] - '0'; if (alt) { n *= 2; if (n > 9) n -= 9 }; sum += n; alt = !alt }
        return d.isNotEmpty() && sum % 10 == 0
    }
    fun cardNumber(d: String): String? {
        if (d.isEmpty()) return "Enter the card number"
        val amex = CardBrand.of(d) == CardBrand.AMEX
        if (amex && d.length != 15 || !amex && d.length !in 13..19) return "Enter the full card number"
        return if (!luhn(d)) "That card number isn't valid" else null
    }
    fun expiry(d: String, today: LocalDate = LocalDate.now()): String? {
        if (d.length != 4) return "Enter the expiry as MM/YY"
        val m = d.take(2).toInt(); val y = 2000 + d.drop(2).toInt()
        if (m !in 1..12) return "Enter a month from 01 to 12"
        val endOfMonth = LocalDate.of(y, m, 1).plusMonths(1).minusDays(1)
        if (endOfMonth.isBefore(today)) return "This card has expired"
        if (y > today.year + 20) return "Check the expiry year"
        return null
    }
    fun cvc(d: String, amex: Boolean): String? = if (d.length != (if (amex) 4 else 3)) "Enter the ${if (amex) 4 else 3}-digit security code" else null
    fun zip(d: String): String? = if (d.length != 5) "Enter a 5-digit ZIP code" else null
}

/* ---------------------------------------------------------------- on-screen formatting */

private class Grouping(private val format: (String) -> String) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val raw = text.text
        val out = format(raw)
        // Map each raw index to its position in `out` (inserted separators are non-digit/letter chars).
        val o2t = IntArray(raw.length + 1)
        var t = 0
        for (i in raw.indices) { while (t < out.length && out[t] != raw[i]) t++; o2t[i] = t; t++ }
        o2t[raw.length] = out.length
        return TransformedText(AnnotatedString(out), object : OffsetMapping {
            override fun originalToTransformed(offset: Int) = o2t[offset.coerceIn(0, raw.length)]
            override fun transformedToOriginal(offset: Int): Int { var i = 0; while (i < raw.length && o2t[i] < offset) i++; return i }
        })
    }
}

/** "8015550134" → "(801) 555-0134" */
fun formatPhone(d: String): String = when {
    d.isEmpty() -> ""
    d.length <= 3 -> "($d"
    d.length <= 6 -> "(${d.take(3)}) ${d.drop(3)}"
    else -> "(${d.take(3)}) ${d.substring(3, 6)}-${d.drop(6)}"
}
fun formatCard(d: String): String =
    if (CardBrand.of(d) == CardBrand.AMEX) listOf(d.take(4), d.drop(4).take(6), d.drop(10)).filter { it.isNotEmpty() }.joinToString(" ")
    else d.chunked(4).joinToString(" ")
fun formatJoinCode(raw: String): String = if (raw.length > 3) raw.take(3) + "-" + raw.drop(3) else raw
fun formatExpiry(d: String): String = if (d.length > 2) d.take(2) + "/" + d.drop(2) else d

val PhoneTransform: VisualTransformation = Grouping(::formatPhone)
val CardTransform: VisualTransformation = Grouping(::formatCard)
val JoinCodeTransform: VisualTransformation = Grouping(::formatJoinCode)
val ExpiryTransform: VisualTransformation = Grouping(::formatExpiry)

/* ---------------------------------------------------------------- form state */

/**
 * Tracks one form's checks. Register a check per field during composition with [check]; [submit] validates all,
 * shows every error, and scrolls to the first one. After a submit, errors are recomputed live and clear once fixed.
 * [fail] shows an error that only a server/stub can decide (e.g. "no company uses that code") until the value changes.
 */
@OptIn(ExperimentalFoundationApi::class)
class FormState internal constructor(private val scope: CoroutineScope) {
    var submitted by mutableStateOf(false)
        private set
    private val checks = LinkedHashMap<String, () -> String?>()
    private val external = mutableStateMapOf<String, Pair<String, String>>()
    private val requesters = HashMap<String, BringIntoViewRequester>()

    fun requester(key: String): BringIntoViewRequester = requesters.getOrPut(key) { BringIntoViewRequester() }

    /** Registers the field's check; returns its current error (null until the first submit). */
    fun check(key: String, value: String = "", rule: () -> String?): String? {
        checks[key] = rule
        external[key]?.let { (msg, at) -> if (at == value) return msg else external.remove(key) }
        return if (submitted) rule() else null
    }

    fun submit(): Boolean {
        submitted = true
        val first = checks.entries.firstOrNull { it.value() != null }?.key
        if (first != null) { scrollTo(first); return false }
        return true
    }

    fun fail(key: String, message: String, value: String) { external[key] = message to value; scrollTo(key) }

    fun reset() { submitted = false; external.clear() }

    private fun scrollTo(key: String) { scope.launch { delay(30); try { requester(key).bringIntoView() } catch (_: Exception) {} } }
}

@Composable
fun rememberForm(): FormState { val scope = rememberCoroutineScope(); return remember { FormState(scope) } }

@OptIn(ExperimentalFoundationApi::class)
fun Modifier.formField(form: FormState, key: String): Modifier = this.bringIntoViewRequester(form.requester(key))
