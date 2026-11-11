package com.vims.app.data

import kotlinx.serialization.Serializable

/* App data model. Everything here is @Serializable and persisted as JSON in the app's filesDir
 * (see FileRepository). Field names mirror the prototype so the Laravel API can map 1:1 later. */

@Serializable
data class Plan(
    val id: String,
    val name: String,
    val price: Double,
    val desc: String = "",
    val unit: String? = null,
    val perReport: Boolean = false,
    /** Data v1.11 (client Oct 28): yearly price; null = no yearly option (Pay per report). */
    val priceYearly: Double? = null,
    /** Data v1.11: shown with a "Coming soon" label but not selectable (Portal + App until Phase 2). */
    val comingSoon: Boolean = false,
) {
    val selectable: Boolean get() = !comingSoon
    val hasYearly: Boolean get() = priceYearly != null && !perReport
}

/** Billing period of a company subscription (data v1.11 `subscription.billingPeriods`). */
object BillingPeriod {
    const val MONTHLY = "monthly"
    const val YEARLY = "yearly"
    fun label(p: String) = if (p == YEARLY) "Yearly" else "Monthly"
    fun unit(p: String) = if (p == YEARLY) "/yr" else "/mo"
}

/**
 * VIMS subscription pricing (data v1.11): platform-level — the same for every company — and edited only by VIMS master admins
 * (`support.platformOwners`) in Plans & pricing. Defaults come from `subscription` in vims-checklists.json; a master admin's
 * edits are kept in [PlatformSettings]. With features.planEditing false the shipped plans are used and store prices are what is shown.
 */
data class Pricing(val plans: List<Plan>, val extraMonthly: Double, val extraYearly: Double?) {
    val selectablePlans: List<Plan> get() = plans.filter { it.selectable }
    /** The company's plan; a deleted or not-yet-selectable plan falls back to the first selectable one. */
    fun plan(a: AccountState): Plan = plan(a.planId)
    fun plan(id: String): Plan = plans.firstOrNull { it.id == id } ?: selectablePlans.firstOrNull() ?: plans.firstOrNull() ?: Plan("app", "App", 0.0)
    /** The period actually billed: yearly only when the company chose it and the plan has a yearly price. */
    fun period(a: AccountState): String = period(plan(a), a.billingPeriod)
    fun period(plan: Plan, chosen: String): String = if (chosen == BillingPeriod.YEARLY && plan.hasYearly) BillingPeriod.YEARLY else BillingPeriod.MONTHLY
    /** Additional inspector rate for a period (follows the company's period; yearly falls back to 12 × monthly when unset). */
    fun extra(period: String): Double = if (period == BillingPeriod.YEARLY) extraYearly ?: (extraMonthly * 12) else extraMonthly
    fun price(plan: Plan, period: String): Double = if (period == BillingPeriod.YEARLY) plan.priceYearly ?: plan.price else plan.price
    /** Plan + additional inspectors for one period (0 for Pay per report). */
    fun total(plan: Plan, period: String, seats: Int): Double = if (plan.perReport) 0.0 else price(plan, period) + maxOf(0, seats - 1) * extra(period)
    fun total(a: AccountState): Double = total(plan(a), period(a), a.seatCount)
    /** "/report", "/mo" or "/yr". */
    fun unit(plan: Plan, period: String): String = if (plan.perReport) plan.unit ?: "/report" else BillingPeriod.unit(period)
}

@Serializable
data class CoverChoice(
    val color: String = "Blue",
    /** Theme category (Activities, Hobbies, Holidays, Seasonal). Before data v1.8 "Solid" was a category (no picture, Solid style). */
    val category: String = "Activities",
    /** Theme picture, or [NO_PICTURE] (data v1.8 `covers.noThemeOption`). */
    val option: String = "Mountains",
    /** Shaded, Framed or Solid (data v1.8: Solid is a style and can carry a picture). */
    val style: String = "Framed",
) {
    /** A cover saved before v1.8 with the old "Solid" category becomes style Solid + No picture (client, Oct 17). */
    val isLegacySolid: Boolean get() = category == LEGACY_SOLID
    fun normalized(): CoverChoice = if (isLegacySolid) copy(category = "", option = NO_PICTURE, style = LEGACY_SOLID) else this
    val hasPicture: Boolean get() = !isLegacySolid && option.isNotBlank() && option != NO_PICTURE
    /** "Blue · Mountains · Framed" / "Blue · No picture · Solid". */
    fun label(): String = normalized().let { "${it.color} · ${if (it.hasPicture) it.option else NO_PICTURE} · ${it.style}" }
    fun artLabel(): String = normalized().let { if (it.hasPicture) it.option else it.color }

    companion object {
        const val NO_PICTURE = "No picture"
        private const val LEGACY_SOLID = "Solid"
    }
}

enum class Role { OWNER, ADMIN, INSPECTOR }

@Serializable
data class Session(
    val name: String,
    val email: String,
    val role: Role = Role.OWNER,
    val signedInAt: Long = System.currentTimeMillis(),
    /** Owner of inspections / answers / photos / findings / reports. */
    val userId: String = "",
    /** Owner of the company profile, logo, checklist customizations, plans, inspectors, subscription. */
    val companyId: String = "",
    /** VIMS master admin / platform owner (not a company role): may edit platform settings — plans & prices, feedback email, report BCC. */
    val platformOwner: Boolean = false,
    /** EULA version this user has accepted (null = never). */
    val eulaVersion: String? = null,
) {
    val isAdmin: Boolean get() = role != Role.INSPECTOR
    val initials: String get() = name.split(" ").filter { it.isNotBlank() }.take(2).joinToString("") { it.first().uppercase() }.ifEmpty { "?" }
}

@Serializable
data class Inspector(
    val id: String,
    val name: String,
    val email: String = "",
    val owner: Boolean = false,
    val admin: Boolean = false,
) {
    val initials: String get() = name.split(" ").filter { it.isNotBlank() }.take(2).joinToString("") { it.first().uppercase() }.ifEmpty { "?" }
    val roleLabel: String get() = if (owner) "Owner · Admin" else if (admin) "Admin" else "Inspector"
}

/**
 * Company-level licensing state: the trial, the inspectors and the plan choice. Subscriptions are the store's, see
 * [com.vims.app.services.BillingManager]. Earlier test builds stored a simulated subscription here (active, card, cardLast4,
 * subscribedEpochDay, cancelled, cancelledEpochDay, refundAmount): those keys are ignored on decoding and count for nothing.
 */
@Serializable
data class AccountState(
    val companyCode: String = "",
    /** Legacy (≤ v0.21.0): a per-company copy of the plans. Not read since v0.22.0 — plans and prices are platform-level ([Pricing]). */
    val plans: List<Plan> = emptyList(),
    /** Legacy (≤ v0.21.0), not read — see [plans]. */
    val extraInspectorMonthly: Double = 0.0,
    val planId: String = "app",
    /** Data v1.11: [BillingPeriod.MONTHLY] or [BillingPeriod.YEARLY]; additional inspectors follow it. */
    val billingPeriod: String = BillingPeriod.MONTHLY,
    val seats: Int = 1,
    val trialDays: Int = 30,
    val trialStartEpochDay: Long = 0,
    val inspectors: List<Inspector> = emptyList(),
    val feedbackEmail: String = "",
    /** Client Oct 25: created on a device whose one free trial was already used — starts with no trial days (Subscribe shown). */
    val trialUsedOnDevice: Boolean = false,
) {
    val seatCount: Int get() = maxOf(seats, inspectors.size, 1)
}

/**
 * VIMS platform-level settings — owned by the platform owner, shared by every company on this install and NOT per
 * company. TODO(backend): served by the Laravel API; the server sends the report-quality copy when a report is emailed.
 */
@Serializable
data class PlatformSettings(
    val feedbackEmail: String = "",
    /**
     * "Report quality copy": every emailed report also goes to [reportBccEmail] (disclosed in the VIMS EULA). Client Oct 30: sent
     * separately by the VIMS server, never as a Bcc on the device's email compose. Field names kept so stored settings load.
     */
    val reportBccOn: Boolean = false,
    val reportBccEmail: String = "",
    /** Data v1.11: VIMS plans as edited by a master admin in Plans & pricing; null = the shipped `subscription.plans`. */
    val plans: List<Plan>? = null,
    /** Master-admin edited additional-inspector rates; null = the shipped `subscription.extraInspectorMonthly / Yearly`. */
    val extraInspectorMonthly: Double? = null,
    val extraInspectorYearly: Double? = null,
) {
    fun pricing(def: SubscriptionDef): Pricing = Pricing(plans ?: def.plans, extraInspectorMonthly ?: def.extraInspectorMonthly, extraInspectorYearly ?: def.extraInspectorYearly)

    /** The report-quality address the server should copy (TODO(backend)), or null when the setting is off. Not put on the device compose. */
    val activeBcc: String? get() = reportBccEmail.trim().takeIf { reportBccOn && it.isNotEmpty() }

    /**
     * Data v1.9.2 (client Oct 22, vimsinspect.com): an address still equal (trimmed, case-insensitive) to an old shipped
     * default in `support.replacedDefaults` moves to the current default; anything the owner typed in is kept.
     */
    fun replacingOldDefaults(defaults: PlatformSettings, replaced: ReplacedDefaultsDef): PlatformSettings {
        fun swap(v: String, old: List<String>, now: String) =
            if (now.isNotBlank() && old.any { it.trim().equals(v.trim(), ignoreCase = true) }) now else v
        return copy(feedbackEmail = swap(feedbackEmail, replaced.feedbackEmail, defaults.feedbackEmail),
            reportBccEmail = swap(reportBccEmail, replaced.reportBccEmail, defaults.reportBccEmail))
    }
}

@Serializable
data class CompanyProfile(
    val name: String = "",
    val address: String = "",
    val inspectorName: String = "",
    val license: String = "",
    /** Client Nov 4 (`wizard._licenseStateAbout`): the state code of [license], optional. Prefills wizard step 1, like [license]. */
    val licenseState: String = "",
    /**
     * Client Nov 11 (`agreementPrefill._cancellationFeeAbout`): Day-of cancellation fee (%), a whole number from 0 to 100, optional
     * (null = blank). Fills the agreement's "a fee totaling ____%" blank. Company-wide; there is no per-inspection field.
     * Part of profileJson, so a profile saved before reads null: no database change.
     */
    val cancellationFeePercent: Int? = null,
    val phone: String = "",
    val email: String = "",
    val reviewUrl: String = "",
    /** Relative to filesDir; null = use the bundled VIMS logo. */
    val logoFile: String? = null,
    val agreementName: String? = null,
    val agreementFile: String? = null,
    /**
     * The company's edited copy of the VIMS agreement as plain text (Company profile → Edit), or null. Never part of
     * profileJson: stored in its own `companies.agreementText` / `agreementEditedAt` columns (DB v4) and filled in by
     * [RoomRepository]. At most one of the edit and the upload ([agreementFile]) is in use; setting one clears the other.
     */
    @kotlinx.serialization.Transient val agreementText: String? = null,
    /** When [agreementText] was last saved (epoch ms). */
    @kotlinx.serialization.Transient val agreementEditedAt: Long? = null,
) {
    /** [cancellationFeePercent] as the agreement prints it ("25"; the agreement already has the %), or "" (blank: the underscores stay). */
    val cancellationFee: String get() = cancellationFeePercent?.takeIf { it in 0..CANCELLATION_FEE_MAX }?.toString().orEmpty()

    companion object {
        const val CANCELLATION_FEE_MAX = 100
    }

    /** The company's own uploaded agreement file name, or null. */
    val uploadedAgreement: String? get() = agreementName?.takeIf { agreementFile != null }
    /** The edited agreement text in use, or null (an upload always wins over a stale edit). */
    val editedAgreement: String? get() = agreementText?.takeIf { it.isNotBlank() && uploadedAgreement == null }
}

@Serializable
data class AppSettings(
    val seeded: Boolean = false,
    val defaultDepth: String = "standard",
    val autoSync: Boolean = true,
    val defaultCover: CoverChoice = CoverChoice(),
    val lastSyncAt: Long? = null,
)

/** Admin checklist edits layered over the shared JSON. Applied to new inspections. */
@Serializable
data class ChecklistEdits(
    val overrides: Map<String, SectionOverride> = emptyMap(),
    val custom: List<CustomSection> = emptyList(),
    /**
     * Client Oct 28: VIMS sections whose company edits were removed with Restore original. Inspections started while the edit was
     * in place keep their saved checklist, so data-added items are never merged into these sections' snapshots
     * ([ChecklistEngine.mergeAdded] would otherwise put back items the company had removed).
     */
    val restored: Set<String> = emptySet(),
)

@Serializable
data class SectionOverride(
    val items: List<ItemDef>? = null,
    val itemsHigh: List<ItemDef>? = null,
)

@Serializable
data class CustomSection(val group: String, val def: SectionDef)

/** Everything the new-inspection wizard collects. Field/chip values are keyed by their JSON label. */
@Serializable
data class WizardSelections(
    val fields: Map<String, String> = emptyMap(),
    val chips: Map<String, String> = emptyMap(),
    val inspType: String = "Real Estate Sale",
    val component: List<String> = emptyList(),
    val structure: String = "Single Family",
    val unitMix: Map<String, Int> = emptyMap(),
    val storiesOther: String = "",
    val depth: String = "standard",
    val counts: Map<String, Int> = emptyMap(),
    val rooms: List<String> = emptyList(),
    val exterior: List<String> = emptyList(),
    val utilOpt: List<String> = emptyList(),
    val tests: List<String> = emptyList(),
    /** Property state code (e.g. "OR"); required on wizard step 1 (data v1.3). Empty on inspections made before v1.3. */
    val state: String = "",
    /** The state's required documents (stateRules.<CODE>.docs) were provided to the client with the inspection agreement. */
    val stateDocsAck: Boolean = false,
    /** When [stateDocsAck] was confirmed (epoch ms). */
    val stateDocsAckAt: Long? = null,
    /** "Send the report to the real estate agent" (step 1, data v1.4). Set to the state's `agentCopyDefault` when the state changes. */
    val sendToAgent: Boolean = true,
    /**
     * Client Nov 4 (`wizard.fees`): option key (a `utilityOptions` / `testOptions` entry) -> amount as typed, e.g. "150.5". Only
     * the inspection agreement reads these, the report doesn't. Empty on inspections saved before v0.31.0.
     */
    val fees: Map<String, String> = emptyMap(),
    /** `wizard.fees.inspectionFee`, as typed. */
    val inspectionFee: String = "",
) {
    fun field(label: String): String = fields[label].orEmpty().trim()
    fun chip(label: String): String = chips[label].orEmpty()
    /**
     * A wizard count. Client Nov 6 (`wizard._roomCountsAbout`): an inspection saved before these counts existed has no value for
     * them, so HVAC Units / Water Heaters / Electrical Panels read 1 and Kitchen reads from its chip: its checklist doesn't change.
     * Client Nov 11: a stored 0 for HVAC Units / Water Heaters / Electrical Panels reads 0 (that section is left out), like Kitchen.
     */
    fun count(key: String): Int = when {
        key in SYSTEM_COUNTS -> (counts[key] ?: 1).coerceAtLeast(0)
        key == KITCHENS -> counts[key] ?: if (KITCHEN in rooms) 1 else 0
        else -> counts[key] ?: 0
    }

    /** A step 3 stepper changed. `syncsRoom`: above 0 turns the room's chip on, 0 turns it off. */
    fun withRoomCount(rc: RoomCountDef, n: Int): WizardSelections {
        val v = n.coerceIn(rc.lowest, rc.highest)
        val room = rc.syncsRoom
        return copy(counts = counts + (rc.key to v), rooms = when {
            room == null -> rooms
            v == 0 -> rooms - room
            room in rooms -> rooms
            else -> rooms + room
        })
    }

    /** A tap on an interior room chip. A chip with a stepper (`syncsRoom`) sets it to 1 when turned on and 0 when turned off. */
    fun withRoomToggled(room: String, roomCounts: List<RoomCountDef>): WizardSelections {
        val on = room !in rooms
        val next = copy(rooms = if (on) rooms + room else rooms - room)
        val rc = roomCounts.firstOrNull { it.syncsRoom == room } ?: return next
        return next.copy(counts = counts + (rc.key to if (on) 1 else 0))
    }

    val address: String get() = field(F_ADDRESS)
    /**
     * Client Oct 17: the address is split into "Inspection address" (street), "City", State and "ZIP code". Inspections made
     * before keep their combined "Street, City, ZIP" text in [F_ADDRESS] and no City / ZIP keys — they read as before.
     */
    val splitAddress: Boolean get() = F_CITY in fields || F_ZIP in fields
    val street: String get() = if (splitAddress) address else address.substringBefore(",").trim()
    val city: String get() = field(F_CITY)
    val zip: String get() = field(F_ZIP)
    /** Cover line 2 / list subtitle: "Ogden, UT 84403" (split address), or the older free text's city part with the State merged in. */
    val cityLine: String get() = if (splitAddress) listOf(city, listOf(state.trim().uppercase(), zip).filter { it.isNotBlank() }.joinToString(" ")).filter { it.isNotBlank() }.joinToString(", ")
        else withState(if (address.contains(",")) address.substringAfter(",").trim() else "", state)
    /** Street + city line (incl. state), e.g. for email bodies. */
    val fullAddress: String get() = listOf(street, cityLine).filter { it.isNotBlank() }.joinToString(", ")
    val clientName: String get() = field(F_CLIENT)
    val clientEmail: String get() = field(F_CLIENT_EMAIL)
    val agentName: String get() = field(F_AGENT)
    val agentEmail: String get() = field(F_AGENT_EMAIL)
    val date: String get() = field(F_DATE)
    val time: String get() = field(F_TIME)
    val license: String get() = field(F_LICENSE)
    /** Inspector's license state code (step 1); never taken from the inspection [state]. */
    val licenseState: String get() = field(F_LICENSE_STATE).uppercase()
    val walkThrough: String get() = field(F_WALK_THROUGH)

    /**
     * What Utility & systems shows as selected. Before shared v1.19.0 Chimney was an exterior area, so a saved inspection keeps
     * it in [exterior] (`wizard._chimneyAbout`) until the wizard saves it again.
     */
    val utilities: List<String> get() = (utilOpt + exterior.filter { it == CHIMNEY }).distinct()

    /** The edit wizard's form of a saved inspection: Chimney saved under exterior moves to [utilOpt]. Only stored on Update checklist. */
    fun chimneyMovedToUtilities(): WizardSelections =
        if (CHIMNEY !in exterior) this else copy(exterior = exterior - CHIMNEY, utilOpt = (utilOpt + CHIMNEY).distinct())

    /** Tap on a step 4 chip: deselecting clears its amount (`wizard.fees.amounts`). */
    fun toggleFeeOption(option: String, utility: Boolean): WizardSelections {
        val list = if (utility) utilOpt else tests
        return if (option in list) withList(utility, list - option).copy(fees = fees - option) else withList(utility, list + option)
    }

    /** An amount typed in a step 4 $ box: above 0 selects its option; clearing it leaves the option as it is. */
    fun withFeeAmount(option: String, utility: Boolean, amount: String): WizardSelections {
        val next = copy(fees = if (amount.isEmpty()) fees - option else fees + (option to amount))
        val list = if (utility) utilOpt else tests
        return if (Fees.cents(amount) > 0 && option !in list) next.withList(utility, list + option) else next
    }

    private fun withList(utility: Boolean, list: List<String>) = if (utility) copy(utilOpt = list) else copy(tests = list)

    companion object {
        /** The one option whose chip (Utility & systems) and checklist place (Property Exterior) differ, see [ChecklistEngine]. */
        const val CHIMNEY = "Chimney"
        /** Client Nov 6 (`wizard.roomCounts`): the counts a saved inspection doesn't have, see [count]. */
        const val KITCHENS = "kitchens"
        const val KITCHEN = "Kitchen"
        /** HVAC Units, Water Heaters, Electrical Panels: missing reads 1 (saved before Nov 6), 0 leaves the section out (Nov 11). */
        val SYSTEM_COUNTS = setOf("hvacUnits", "waterHeaters", "electricalPanels")
        /** Stored value before Mobile Home / Manufactured Home split (`wizard._structureLegacyAbout`); the wizard highlights Mobile Home for it. */
        const val STRUCTURE_LEGACY_MOBILE = "Mobile / Manufactured"
        const val STRUCTURE_MOBILE = "Mobile Home"
        const val STRUCTURE_MANUFACTURED = "Manufactured Home"

        // Labels from wizard.step1 in vims-checklists.json (used as keys).
        const val F_CLIENT = "Client name"
        const val F_CLIENT_PHONE = "Client phone"
        const val F_CLIENT_EMAIL = "Client email"
        const val F_ADDRESS = "Inspection address"
        /** Client Oct 17 (not in wizard.step1 of the shared data): shown after Inspection address / after State. */
        const val F_CITY = "City"
        const val F_ZIP = "ZIP code"
        const val F_AGENT = "Real estate agent name"
        const val F_AGENT_EMAIL = "Real estate agent email"
        const val F_DATE = "Date"
        const val F_TIME = "Time"
        const val F_LICENSE = "Inspector License #"
        const val F_LICENSE_STATE = "License state"
        const val F_WALK_THROUGH = "Time of walk through"

        val ZIP = Regex("^\\d{5}(-\\d{4})?$")

        /**
         * Splits an older combined "Street, City, ZIP" / "Street, City, ST ZIP" address into (street, city, zip) for the
         * edit wizard. The state is dropped (it has its own field); nothing that can't be placed is lost — it stays in the city.
         */
        fun splitLegacy(address: String, state: String): Triple<String, String, String> {
            val parts = address.split(",").map { it.trim() }.filter { it.isNotEmpty() }
            if (parts.size <= 1) return Triple(address.trim(), "", "")
            val street = parts.first()
            var rest = parts.drop(1).joinToString(", ")
            var zip = ""
            Regex("(\\d{5}(-\\d{4})?)\\s*$").find(rest)?.let { m -> zip = m.groupValues[1]; rest = rest.substring(0, m.range.first).trim().trimEnd(',').trim() }
            val st = state.trim().uppercase()
            if (st.isNotEmpty()) rest = rest.replace(Regex("(,\\s*|\\s+)$st$", RegexOption.IGNORE_CASE), "").let { if (it.equals(st, true)) "" else it }.trim().trimEnd(',').trim()
            // Any other trailing ", ST" (a state typed into the old free text that differs from the State field) is left out too.
            rest = rest.replace(Regex(",\\s*[A-Za-z]{2}$"), "").trim()
            return Triple(street, rest, zip)
        }

        /** Adds the state code to an address's city part unless it's already there (addresses typed before v1.3). */
        fun withState(city: String, state: String): String {
            val st = state.trim().uppercase()
            val parts = city.split(",").map { it.trim() }.filter { it.isNotEmpty() }
            if (st.isEmpty() || parts.any { p -> p.uppercase().let { it == st || it.startsWith("$st ") } }) return city
            if (parts.isEmpty()) return st
            val last = parts.last()
            return if (ZIP.matches(last)) (parts.dropLast(1) + "$st $last").joinToString(", ") else (parts + st).joinToString(", ")
        }
    }
}

/** One group in the built checklist (Sections overview). `link` groups navigate (Inspection Info / Summary). */
@Serializable
data class BuiltGroup(
    val heading: String,
    val icon: String? = null,
    val link: String? = null,
    val sections: List<String> = emptyList(),
    val sub: BuiltGroup? = null,
) {
    val leaves: List<String> get() = sections + (sub?.sections ?: emptyList())
}

object InspStatus {
    const val SCHEDULED = "scheduled"
    const val IN_PROGRESS = "in_progress"
    const val QUEUED = "queued"
    const val DONE = "done"
}

object SecStatus {
    const val TODO = "todo"
    const val PROG = "prog"
    const val DONE = "done"
}

@Serializable
data class Inspection(
    val id: String,
    val createdAt: Long,
    val status: String = InspStatus.IN_PROGRESS,
    val selections: WizardSelections = WizardSelections(),
    val groups: List<BuiltGroup> = emptyList(),
    val cover: CoverChoice = CoverChoice(),
    val pendingSync: Boolean = true,
    val reportFile: String? = null,
    val reportPages: Int = 0,
    val reportGeneratedAt: Long? = null,
) {
    val leafSections: List<String> get() = groups.flatMap { it.leaves }
    /** Layouts without a Summary link (4 Point) skip the summary everywhere. */
    val hasSummary: Boolean get() = groups.any { it.link == "summary" }
}

/** "3", "3 Mild", "1 Good" → rating digit (see [SectionAnswers.airRating]). */
private val airRatingRx = Regex("^([1-6])(\\D.*)?$")

@Serializable
data class SectionAnswers(
    val status: String = SecStatus.TODO,
    /** Chip selections per item key (single → at most one value). */
    val values: Map<String, List<String>> = emptyMap(),
    /**
     * num/text/date/time answers and optional High Detail "Detail / measurement" notes, per item key.
     * `airReading` (data v1.7, Indoor Air Quality) uses both maps under its one key: the 1–6 rating in [values]
     * (a single chip, like `single`) and the optional "Level measured" number in [inputs] (plain decimal text, unit not
     * stored). Read them through [airRating] / [airLevel]; no schema change was needed.
     * `countChoice` (data v1.13, client Oct 30 receptacles) likewise uses both maps under its one key: the selected options in
     * [values] (like `multi`, in button order — `{selected}`) and the counts in [inputs] as a small JSON object
     * (`{"GFCI":4,"Standard":6}` — `{counts}`, only options with a count typed). Read them through [countSelected] / [counts];
     * see [CountChoice]. No Room schema change: both maps were already stored in the section's answers JSON.
     */
    val inputs: Map<String, String> = emptyMap(),
    /** Fast Entry "Items reviewed" chips (labelled "Items present" before data v1.5). */
    val present: List<String> = emptyList(),
    val overall: String? = null,
    val comments: String = "",
) {
    val hasContent: Boolean get() = values.any { it.value.isNotEmpty() } || inputs.any { it.value.isNotBlank() } || present.isNotEmpty() || comments.isNotBlank()

    /**
     * `airReading` rating "1"…"6", or null. Answers saved by the pre-v1.7 single-choice IAQ lines ("1 Good", "3 Mild", "2")
     * map to their leading digit; anything else is ignored.
     */
    fun airRating(key: String): String? =
        values[key]?.firstOrNull()?.trim()?.let { airRatingRx.find(it)?.groupValues?.get(1) }

    /** `airReading` "Level measured" (decimal text without the unit), or "" when not measured or not a valid number (e.g. "."). */
    fun airLevel(key: String): String = inputs[key].orEmpty().trim().takeIf { (com.vims.app.util.Num.parse(it) ?: -1.0) >= 0.0 }.orEmpty()

    /** `countChoice` selected options (answered = at least one). */
    fun countSelected(key: String): List<String> = values[key].orEmpty()
    /** `countChoice` counts per option (whole numbers 0–999); empty when none typed or not readable. */
    fun counts(key: String): Map<String, Int> = CountChoice.decode(inputs[key])
}

/**
 * Data v1.13 `itemTypes.countChoice` (client Oct 30): option buttons where some options carry a whole-number count — the
 * combined Receptacles item None / GFCI + count / Standard + count. Rules (same as the prototype's ccTap / ccCount):
 *  - an `exclusive` option (None) clears every other choice and every count when tapped on;
 *  - other options toggle and combine (GFCI and Standard together); tapping one on clears the exclusive ones; deselecting one
 *    clears its count;
 *  - typing a count clears the exclusive options, and a count above 0 selects its option; counts are optional, 0–999.
 * Stored as described on [SectionAnswers] (selected in `values[key]`, counts JSON in `inputs[key]`).
 */
object CountChoice {
    private val json = kotlinx.serialization.json.Json { ignoreUnknownKeys = true; isLenient = true }

    fun decode(raw: String?): Map<String, Int> {
        val t = raw?.trim().orEmpty()
        if (!t.startsWith("{")) return emptyMap()
        return try {
            json.parseToJsonElement(t).let { it as? kotlinx.serialization.json.JsonObject }.orEmpty().mapNotNull { (k, v) ->
                (v as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim()?.toIntOrNull()?.takeIf { it in 0..ItemDef.COUNT_MAX.toInt() }?.let { k to it }
            }.toMap()
        } catch (_: Exception) { emptyMap() }
    }

    fun encode(counts: Map<String, Int>): String =
        if (counts.isEmpty()) "" else kotlinx.serialization.json.JsonObject(counts.mapValues { kotlinx.serialization.json.JsonPrimitive(it.value) }).toString()

    /** [sel] in the item's button order (anything not offered any more stays, at the end). */
    private fun ordered(item: ItemDef, sel: Collection<String>): List<String> {
        val opts = item.options.orEmpty()
        return opts.filter { it in sel } + sel.filter { it !in opts }.distinct()
    }

    private fun write(a: SectionAnswers, key: String, sel: List<String>, counts: Map<String, Int>): SectionAnswers {
        val enc = encode(counts)
        return a.copy(values = a.values + (key to sel), inputs = if (enc.isEmpty()) a.inputs - key else a.inputs + (key to enc))
    }

    /** Taps [option] on / off. */
    fun tap(a: SectionAnswers, key: String, item: ItemDef, option: String): SectionAnswers {
        val sel = a.countSelected(key)
        val counts = a.counts(key)
        return when {
            option in sel -> write(a, key, sel - option, counts - option)
            item.isExclusive(option) -> write(a, key, listOf(option), emptyMap())
            else -> write(a, key, ordered(item, sel.filterNot { item.isExclusive(it) } + option), counts)
        }
    }

    /** The count field of [option] changed to [text] (digits only, already filtered; "" clears it). */
    fun setCount(a: SectionAnswers, key: String, item: ItemDef, option: String, text: String): SectionAnswers {
        val n = text.trim().toIntOrNull()?.coerceIn(0, ItemDef.COUNT_MAX.toInt())
        var sel = a.countSelected(key)
        val counts = a.counts(key).let { if (n == null) it - option else it + (option to n) }
        if (n != null) {
            sel = sel.filterNot { item.isExclusive(it) }
            if (n > 0 && option !in sel) sel = ordered(item, sel + option)
        }
        return write(a, key, sel, counts)
    }

    /** Report / preview text: "GFCI (4), Standard (6)", "GFCI" (no count), "None"; "" when nothing is selected. */
    fun text(a: SectionAnswers, key: String): String {
        val counts = a.counts(key)
        return a.countSelected(key).joinToString(", ") { o -> counts[o]?.let { n -> "$o ($n)" } ?: o }
    }

    /** "Number of GFCI receptacles" for the count field of [option] on "Receptacles" / "Receptacles (outside)" / "Electrical Receptacles". */
    fun fieldDescription(item: ItemDef, option: String): String {
        val noun = item.q.orEmpty().replace(Regex("\\s*\\(.*\\)\\s*$"), "").replace(Regex("^Electrical\\s+", RegexOption.IGNORE_CASE), "").trim().lowercase(java.util.Locale.US)
        return "Number of $option${if (noun.isEmpty()) "" else " $noun"}"
    }
}

@Serializable
data class Photo(
    val id: String,
    val section: String,
    val category: String,
    /** Relative to filesDir. */
    val file: String,
    val flag: Int = 0,
    val quickComment: String = "",
    val customComment: String = "",
    val createdAt: Long = System.currentTimeMillis(),
) {
    val caption: String get() = listOf(quickComment, customComment).filter { it.isNotBlank() }.joinToString(" — ")
}

@Serializable
data class Finding(
    val id: String,
    val cat: Int,
    val text: String,
    val section: String,
    val photoId: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
    /** Checklist item question a "Concern(s)" finding was raised from (Standard / High Detail item), else null. */
    val item: String? = null,
    /**
     * The two parts of [text], stored separately since Oct 16 (null on older findings, which only have [text]):
     * the inspector's own words (a Concern finding's is "<item>: <description>", or "<item>") and the picked quick comment.
     */
    val custom: String? = null,
    val quick: String? = null,
) {
    /**
     * What follows the section name on the Summary screen and in the report (client, Oct 16): "custom comment — quick comment",
     * empty parts left out. Findings saved before the split fall back to their stored [text].
     */
    val body: String get() = if (custom == null && quick == null) text
        else listOfNotNull(custom?.trim()?.takeIf { it.isNotEmpty() }, quick?.trim()?.takeIf { it.isNotEmpty() }).joinToString(" — ").ifEmpty { text }
}

/** Everything stored for one inspection. `defs` is the checklist snapshot taken when the checklist was built. */
data class InspectionBundle(
    val inspection: Inspection,
    val answers: Map<String, SectionAnswers> = emptyMap(),
    val photos: List<Photo> = emptyList(),
    val findings: List<Finding> = emptyList(),
    val defs: Map<String, SectionDef> = emptyMap(),
) {
    val id: String get() = inspection.id
    fun status(section: String): String = answers[section]?.status ?: SecStatus.TODO

    /** Data v1.14 `notes` section (Planned Maintenance Recommendations). */
    fun isNotes(section: String): Boolean = defOf(section)?.notes == true

    /** The saved checklist of a section or of one of its copies ([ChecklistEngine.savedDef]). */
    fun defOf(section: String): SectionDef? = ChecklistEngine.savedDef(defs, section)

    /** The written lines of a `notes` section, trimmed, in checklist order (blank lines left out; the report renumbers them). */
    fun notesLines(section: String): List<String> {
        val a = answers[section] ?: return emptyList()
        val d = defOf(section) ?: return emptyList()
        return ChecklistEngine.keyed(d.items).mapNotNull { (k, _) -> k?.let { a.inputs[it]?.trim()?.takeIf { v -> v.isNotEmpty() } } }
    }

    /**
     * Sections that count toward progress (done / left / %): every section except a `notes` section with nothing written, so the
     * optional Planned Maintenance section never holds an inspection below 100% or "left" above 0.
     */
    val progressSections: List<String> get() = inspection.leafSections.filter { !isNotes(it) || notesLines(it).isNotEmpty() }
}

/** "Bathroom 2" → "Bathroom", "Cooling System #2" → "Cooling System" (numbered copies share the base section's checklist). */
fun baseName(name: String): String = name.replace(Regex("\\s+#?\\d+$"), "")
