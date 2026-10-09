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
)

@Serializable
data class CoverChoice(
    val color: String = "Blue",
    val category: String = "Activities",
    val option: String = "Mountains",
    val style: String = "Framed",
) {
    /** "Blue · Mountains · Framed" (or "Blue · Solid · Solid") — same label as the prototype. */
    fun label(): String = "$color · ${if (category == "Solid") "Solid" else option} · $style"
    fun artLabel(): String = if (category == "Solid") color else option
    fun tag(): String = if (category == "Solid") "$color · Solid" else "$color · $category · $option · $style"
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
    /** The VIMS platform owner (not a company role): may edit platform settings — feedback email, report BCC. */
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

/** Company-level subscription / licensing state (Square billing is stubbed in Phase 1). */
@Serializable
data class AccountState(
    val companyCode: String = "",
    val plans: List<Plan> = emptyList(),
    val extraInspectorMonthly: Double = 0.0,
    val planId: String = "app",
    val active: Boolean = false,
    val seats: Int = 1,
    val trialDays: Int = 30,
    val trialStartEpochDay: Long = 0,
    val inspectors: List<Inspector> = emptyList(),
    val feedbackEmail: String = "",
    val cardLast4: String? = null,
    val subscribedEpochDay: Long? = null,
    /** Cancelled subscriptions stay active until the end of the current billing period (EULA 12.3). */
    val cancelled: Boolean = false,
) {
    /** Next billing date (or, when cancelled, the date access ends). */
    val periodEndEpochDay: Long? get() = subscribedEpochDay?.let { java.time.LocalDate.ofEpochDay(it).plusMonths(1).toEpochDay() }
    val plan: Plan get() = plans.firstOrNull { it.id == planId } ?: plans.firstOrNull() ?: Plan("app", "App", 0.0)
    val seatCount: Int get() = maxOf(seats, inspectors.size, 1)
}

/**
 * VIMS platform-level settings — owned by the platform owner, shared by every company on this install and NOT per
 * company. TODO(backend): served by the Laravel API; the server always adds the report BCC when sending.
 */
@Serializable
data class PlatformSettings(
    val feedbackEmail: String = "",
    /** "Report quality copy (BCC)": blind-copy every emailed report (disclosed in the VIMS EULA). */
    val reportBccOn: Boolean = false,
    val reportBccEmail: String = "",
) {
    /** The BCC address to add to a report email, or null when the setting is off. */
    val activeBcc: String? get() = reportBccEmail.trim().takeIf { reportBccOn && it.isNotEmpty() }
}

@Serializable
data class CompanyProfile(
    val name: String = "",
    val address: String = "",
    val inspectorName: String = "",
    val license: String = "",
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
) {
    fun field(label: String): String = fields[label].orEmpty().trim()
    fun chip(label: String): String = chips[label].orEmpty()
    fun count(key: String): Int = counts[key] ?: 0

    val address: String get() = field(F_ADDRESS)
    val street: String get() = address.substringBefore(",").trim()
    /** City line with the State field merged in: "Portland, 97201" + OR → "Portland, OR 97201". */
    val cityLine: String get() = withState(if (address.contains(",")) address.substringAfter(",").trim() else "", state)
    /** Street + city line (incl. state), e.g. for email bodies. */
    val fullAddress: String get() = listOf(street, cityLine).filter { it.isNotBlank() }.joinToString(", ")
    val clientName: String get() = field(F_CLIENT)
    val clientEmail: String get() = field(F_CLIENT_EMAIL)
    val agentName: String get() = field(F_AGENT)
    val agentEmail: String get() = field(F_AGENT_EMAIL)
    val date: String get() = field(F_DATE)
    val time: String get() = field(F_TIME)
    val license: String get() = field(F_LICENSE)

    companion object {
        // Labels from wizard.step1 in vims-checklists.json (used as keys).
        const val F_CLIENT = "Client name"
        const val F_CLIENT_PHONE = "Client phone"
        const val F_CLIENT_EMAIL = "Client email"
        const val F_ADDRESS = "Inspection address"
        const val F_AGENT = "Real estate agent name"
        const val F_AGENT_EMAIL = "Real estate agent email"
        const val F_DATE = "Date"
        const val F_TIME = "Time"
        const val F_LICENSE = "Inspector License #"

        private val ZIP = Regex("^\\d{5}(-\\d{4})?$")

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

@Serializable
data class SectionAnswers(
    val status: String = SecStatus.TODO,
    /** Chip selections per item key (single → at most one value). */
    val values: Map<String, List<String>> = emptyMap(),
    /** num/text/date/time answers and optional High Detail "Detail / measurement" notes, per item key. */
    val inputs: Map<String, String> = emptyMap(),
    /** Fast Entry "Items reviewed" chips (labelled "Items present" before data v1.5). */
    val present: List<String> = emptyList(),
    val overall: String? = null,
    val comments: String = "",
) {
    val hasContent: Boolean get() = values.any { it.value.isNotEmpty() } || inputs.any { it.value.isNotBlank() } || present.isNotEmpty() || comments.isNotBlank()
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
)

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
}

/** "Bathroom 2" → "Bathroom" (numbered room instances share the base section's checklist). */
fun baseName(name: String): String = name.replace(Regex("\\s+\\d+$"), "")
