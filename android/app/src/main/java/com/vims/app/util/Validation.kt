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
    /**
     * Company code as typed, in its full form "VIS-4827" (QA Oct 14: the field took only 3 letters — the typed "-" was dropped
     * and the keyboard's composing text was lost). Uppercase; 3 letters, then "-" (typed or inserted automatically once the
     * third letter is typed — [prev] tells typing from deleting, so Backspace can remove it), then up to 4 digits. Pastes
     * like "vis4827" / "VIS 4827" / "VIS-4827" all become "VIS-4827".
     */
    fun joinCode(v: String, prev: String = ""): String {
        val up = v.uppercase(Locale.US).filter { it.isLetterOrDigit() }
        val letters = up.takeWhile { it.isLetter() }.take(3)
        if (letters.length < 3) return letters
        val digits = up.drop(3).filter { it.isDigit() }.take(4)
        return when {
            digits.isNotEmpty() -> "$letters-$digits"
            v.length > prev.length || v.trimEnd().endsWith("-") -> "$letters-"
            else -> letters
        }
    }
    /** City: letters, spaces and . ' - (e.g. "St. George", "Coeur d'Alene"), max 60. */
    fun city(v: String) = base(v.filter { it.isLetter() || it == ' ' || it in ".'-’" }, 60)
    /** ZIP code: 5 digits, or ZIP+4 with the "-" inserted after the 5th digit ("84015-1234"). */
    fun zip(v: String): String { val d = v.filter { it.isDigit() }.take(9); return if (d.length > 5) d.take(5) + "-" + d.drop(5) else d }
    fun license(v: String) = base(v.filter { it.isLetterOrDigit() || it == ' ' || it == '-' }, 20)
    fun policy(v: String) = v.filter { it.isLetterOrDigit() || it == '-' }.take(30)
    fun year(v: String) = v.filter { it.isDigit() }.take(4)
    /** Digits + one decimal point (sq ft, valuation, lot size, amps, `num` checklist items). */
    fun decimal(v: String, max: Int = 12): String {
        val sb = StringBuilder(); var dot = false
        v.forEach { c -> if (c.isDigit()) sb.append(c) else if ((c == '.') && !dot) { dot = true; sb.append(c) } }
        return sb.toString().take(max)
    }
    /** Digits + one ".", grouping commas and a leading "$" are accepted and dropped (valuation "$450,000" → "450000"). */
    fun money(v: String) = decimal(Num.clean(v))
    /**
     * Temperature °F (team QA Oct 22): optional leading "-", digits and one "." with at most one decimal, at most 5 characters
     * in all (-12.5, 105.5); range checked by [Checks.temperature].
     */
    fun temperature(v: String): String {
        val neg = v.trimStart().startsWith("-") || v.trimStart().startsWith("−")
        val d = decimal(v, 6)
        val i = d.indexOf('.')
        val num = if (i >= 0) d.take(3.coerceAtMost(i)) + d.substring(i).take(2) else d.take(3)
        return ((if (neg) "-" else "") + num).take(5)
    }
    /**
     * Numbers with limits enforced while typing (team QA Oct 22, docs/validation-rules.md): digits and, when [decimals] > 0,
     * one "." with at most [decimals] places (0 = whole numbers only: the value is cut at the ".", so a pasted "2450.5" is
     * "2450" — never "24505"; see [WholeNumberInput] for typing). Grouping commas, spaces and a leading "$" in
     * pasted text are dropped. A value above [max] is not accepted: the last characters are dropped until it fits (typing "25"
     * into a 0–20 count leaves "2"). Stateless, so fast typing / pastes give the same result.
     */
    fun number(v: String, decimals: Int, max: Double): String {
        val d = decimal(Num.clean(v), 16)
        val i = d.indexOf('.')
        val out = when {
            i < 0 -> d
            decimals <= 0 -> d.substring(0, i)
            else -> d.take(i + 1 + decimals)
        }
        var r = out
        while (r.isNotEmpty() && (r.toDoubleOrNull() ?: 0.0) > max) r = r.dropLast(1)
        return r
    }
    fun url(v: String) = v.filterNot { it.isWhitespace() }.take(300)
    /** Digits + ".", at most 2 decimals. */
    fun price(v: String): String { val d = decimal(v, 10); val i = d.indexOf('.'); return if (i >= 0) d.take(i + 3) else d }
    fun cardNumber(v: String): String { val d = v.filter { it.isDigit() }; return d.take(if (CardBrand.of(d) == CardBrand.AMEX) 15 else 19) }
    /** Expiry digits "MMYY" ([ExpiryTransform] shows "MM/YY"). A leading 2–9 month gets a 0 prefix. */
    fun expiry(v: String): String { var d = v.filter { it.isDigit() }; if (d.length == 1 && d[0] in '2'..'9') d = "0$d"; return d.take(4) }
    fun cvc(v: String, amex: Boolean) = v.filter { it.isDigit() }.take(if (amex) 4 else 3)
    /** Billing ZIP / postal code: letters, digits, space, "-"; uppercase; max 10 (US 84015 / 84015-1234, Canada K1A 0B1, UK SW1A 1AA). */
    fun postalCode(v: String) = base(v.uppercase(Locale.US).filter { it in 'A'..'Z' || it.isDigit() || it == ' ' || it == '-' }, 10)
    fun sectionName(v: String) = base(v, 60)
    fun question(v: String) = base(v, 120)
    fun option(v: String) = base(v, 60)
    /**
     * Edit agreement: tabs → spaces and Windows line breaks → "\n" only — spacing and blank lines are kept as typed
     * (form lines rely on them). Length is checked on Save ([Checks.agreement]); this only stops runaway pastes.
     */
    fun agreement(v: String, max: Int): String = v.replace("\r\n", "\n").replace('\r', '\n').replace('\t', ' ').take(max * 2)
}

/**
 * Typing into a whole-number field (team QA Oct 22): a "." — typed or pasted — and everything after it is discarded ("2450.5"
 * → "2450"), and digits typed right after the rejected "." are not accepted either (so "2450", ".", "5" stays "2450", never
 * the silent 10× "24505"). [blocked] stays on — and the field shows "Whole numbers only" — until the user deletes a
 * character or leaves the field ([reset]). Keeps its own last value, so fast typing is judged edit by edit.
 */
class WholeNumberInput(private val max: Double, initial: String = "") {
    var blocked by mutableStateOf(false)
        private set
    private var last = initial
    fun apply(v: String): String {
        val raw = Num.clean(v)
        val dot = raw.indexOf('.')
        if (dot >= 0) { blocked = true; return Filters.number(raw.substring(0, dot), 0, max).also { last = it } }
        if (blocked && raw.length > last.length) return last
        if (raw.length < last.length) blocked = false
        return Filters.number(raw, 0, max).also { last = it }
    }
    fun reset(value: String) { blocked = false; last = value }
}

/** Reading numbers: grouping commas, spaces and a leading "$" are ignored everywhere a number is read ("$450,000" = 450000). */
object Num {
    fun clean(v: String): String = v.trim().removePrefix("$").replace(",", "").replace(" ", "")
    fun parse(v: String): Double? = clean(v).takeIf { it.isNotEmpty() }?.toDoubleOrNull()
    /** "100000000" → "100,000,000"; "0.01" stays. */
    fun fmt(n: Double): String = if (n == Math.floor(n)) String.format(Locale.US, "%,d", n.toLong()) else String.format(Locale.US, "%,.2f", n).trimEnd('0').trimEnd('.')
}

/** Number limits (docs/validation-rules.md "Number limits"): every numeric field and − / + stepper. */
object Limits {
    const val SEATS_MAX = 50
    /** Data v1.14 notes line (Planned Maintenance Recommendations) when the item has no `maxLength`. */
    const val NOTES_LINE = 300
    /** Wizard counts (bedrooms, bathrooms, hallways, unit mix, …) and checklist room counts ("Number of kitchens"). */
    const val COUNT_MAX = 20
    const val SQFT_MAX = 100_000.0
    const val VALUATION_MAX = 100_000_000.0
    const val LOT_MAX = 10_000.0
    const val CHECKLIST_NUM = 99_999.0
    private val roomCount = Regex("^number of (kitchens?|bath(room)?s?|half[- ]baths?|bedrooms?|stories|hallways?|rooms?|living|family|dining|garages?)", RegexOption.IGNORE_CASE)
    /** Septic "System number" (team QA Oct 22): 1 – 99. */
    const val SYSTEM_NUMBER_MAX = 99.0
    /** Radon "Measured level (pCi/L)" (team QA Oct 22): 0 – 999.9. */
    const val RADON_MAX = 999.9
    /**
     * Max for a checklist `num` item: Septic "System number" 99, Radon "Measured level (pCi/L)" 999.9, room counts
     * ("Number of kitchens / bathrooms …") 20, everything else 99,999.
     */
    fun checklistMax(question: String): Double = question.trim().let { q ->
        when {
            q.equals("System number", ignoreCase = true) -> SYSTEM_NUMBER_MAX
            q.startsWith("Measured level (pCi/L)", ignoreCase = true) -> RADON_MAX
            roomCount.containsMatchIn(q) -> COUNT_MAX.toDouble()
            else -> CHECKLIST_NUM
        }
    }
    /** Min for a checklist `num` item: Septic "System number" starts at 1, everything else allows 0. */
    fun checklistMin(question: String): Double = if (question.trim().equals("System number", ignoreCase = true)) 1.0 else 0.0
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
        !Regex("^[A-Z]{3}-?[0-9]{4}$").matches(raw) -> "Codes are 3 letters and 4 numbers, like VIS-4827"
        else -> null
    }
    fun year(v: String): String? {
        if (v.isEmpty()) return null
        val y = v.toIntOrNull() ?: return "Enter a year"
        val now = LocalDate.now().year
        return if (y !in 1800..now) "Enter a year between 1800 and $now" else null
    }
    /** Optional number > 0 (grouping commas / a leading "$" ignored — [Num.parse]) and at most [max] when given. */
    fun positive(v: String, label: String = "a number", max: Double? = null): String? {
        if (v.isBlank()) return null
        val n = Num.parse(v) ?: return "Enter $label"
        return if (n <= 0.0) "Enter $label greater than 0" else if (max != null && n > max) "Enter a number up to ${Num.fmt(max)}" else null
    }
    /** Optional number ≥ [min] (0 by default) and at most [max] (checklist `num` items, Indoor Air Quality level — 0 is a valid reading). */
    fun upTo(v: String, max: Double, min: Double = 0.0, integer: Boolean = false, decimals: Int? = null): String? {
        if (v.isBlank()) return null
        val n = Num.parse(v) ?: return if (integer) "Enter a whole number" else "Enter a number"
        val places = Num.clean(v).substringAfter('.', "").length
        return when {
            integer && n != Math.floor(n) -> "Enter a whole number"
            !integer && decimals != null && places > decimals -> "Use at most $decimals decimal place${if (decimals == 1) "" else "s"}"
            n < min -> if (min == 0.0) "Enter a number of 0 or more" else "Enter a number from ${Num.fmt(min)} to ${Num.fmt(max)}"
            n > max -> if (min > 0.0) "Enter a number from ${Num.fmt(min)} to ${Num.fmt(max)}" else "Enter a number up to ${Num.fmt(max)}"
            else -> null
        }
    }
    /** Indoor Air Quality "Level measured": optional, 0 – 99,999 (0 ppm CO is a valid reading). */
    fun level(v: String): String? = upTo(v, Limits.CHECKLIST_NUM)
    fun temperature(v: String): String? {
        if (v.isEmpty()) return null
        val t = v.toDoubleOrNull()?.takeIf { !v.endsWith(".") } ?: return "Enter a temperature, like 72 or 72.5"
        return if (t < -60.0 || t > 140.0) "Enter a temperature between −60 and 140 °F" else null
    }
    /** Optional ZIP code: 5 digits or ZIP+4. */
    fun zip(v: String): String? = if (v.isEmpty() || com.vims.app.data.WizardSelections.ZIP.matches(v)) null else "Enter a 5-digit ZIP code (or ZIP+4, like 84015-1234)"
    fun url(v: String): String? {
        if (v.isEmpty()) return null
        val ok = Regex("^https?://[^\\s/?#]+\\.[^\\s/?#]+.*$", RegexOption.IGNORE_CASE).matches(v)
        return if (!ok) "Enter a full link starting with https://" else null
    }
    fun price(v: String): String? {
        val p = Num.parse(v) ?: return "Enter a price"
        return if (p < 0.01 || p > 9999.99) "Enter a price from $0.01 to $9,999.99" else null
    }
    fun sectionName(v: String, exists: (String) -> Boolean): String? = when {
        v.trim().isEmpty() -> "Enter a section name"
        exists(v.trim()) -> "A section with that name already exists"
        else -> null
    }
    fun question(v: String): String? = if (v.trim().isEmpty()) "Enter the question text" else null
    fun agreement(v: String, max: Int): String? = when {
        v.isBlank() -> "Enter the agreement text"
        v.length > max -> "Keep the agreement under ${String.format(Locale.US, "%,d", max)} characters (now ${String.format(Locale.US, "%,d", v.length)})"
        else -> null
    }
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
    fun postalCode(v: String): String? = when {
        v.isBlank() -> "Enter the billing ZIP or postal code"
        v.trim().length !in 3..10 -> "Enter a valid ZIP or postal code"
        else -> null
    }
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

/** "450000" (or a stored "450,000") → "450,000"; decimals kept ("1234.5" → "1,234.5"). */
fun formatGrouped(raw: String): String {
    val c = raw.replace(",", "")
    val int = c.substringBefore('.'); val dec = if ('.' in c) "." + c.substringAfter('.') else ""
    return int.reversed().chunked(3).joinToString(",").reversed() + dec
}

/** Digits are shown as "(801) 555-0134"; a value that isn't plain digits (saved formatted by an older build) shows as it is. */
val PhoneTransform: VisualTransformation = Grouping { if (it.all(Char::isDigit)) formatPhone(it) else it }
/** Valuation / sq ft show grouping commas while the stored value stays digits (docs: "may also show grouping commas"). */
val GroupedNumberTransform: VisualTransformation = Grouping(::formatGrouped)
val CardTransform: VisualTransformation = Grouping(::formatCard)
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
