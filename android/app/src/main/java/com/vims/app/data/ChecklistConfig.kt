package com.vims.app.data

import android.content.Context
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Typed view of `shared/data/vims-checklists.json` (packaged as assets/data/vims-checklists.json).
 * This file is the single source of truth for all checklist content and config shared with iOS.
 * Never hardcode checklist content in Kotlin — read it from here.
 */
@Serializable
data class ChecklistConfig(
    val version: String = "",
    val depths: List<DepthDef> = emptyList(),
    val depthRules: Map<String, String> = emptyMap(),
    val itemTypes: Map<String, String> = emptyMap(),
    val overallCondition: List<String> = emptyList(),
    val overallConditionDefault: String = "Good",
    val sectionGroups: List<SectionGroupDef> = emptyList(),
    val sections: List<SectionDef> = emptyList(),
    val checklistBuilder: ChecklistBuilderDef = ChecklistBuilderDef(),
    val wizard: WizardDef = WizardDef(),
    val findings: FindingsDef = FindingsDef(),
    val covers: CoversDef = CoversDef(),
    val subscription: SubscriptionDef = SubscriptionDef(),
    val support: SupportDef = SupportDef(),
    val sample: SampleDef? = null,
    /** Badge text for state / insurance form sections, keyed by SectionDef.form (texas | fourPoint). */
    val formLabels: Map<String, String> = emptyMap(),
    /** Page order of the PDF per inspection type (`typeToLayout` picks the layout). */
    val reportLayouts: JsonObject = JsonObject(emptyMap()),
    /** Property states for the wizard's required "State" dropdown (50 + DC, data v1.3). */
    val states: List<StateDef> = emptyList(),
    /** Per-state rules keyed by state code (TX / OK / OR / LA); non-object keys such as `_about` are ignored. */
    val stateRules: JsonObject = JsonObject(emptyMap()),
    /** Data v1.10 (client Oct 25): feature switches; missing key = Phase 1 defaults (see [FeaturesDef]). */
    val features: FeaturesDef = FeaturesDef(),
) {
    /** Parsed [stateRules] (tolerant: unknown keys inside a rule are ignored, malformed entries skipped). */
    private val rules: Map<String, StateRule> by lazy {
        stateRules.mapNotNull { (code, v) ->
            val o = v as? JsonObject ?: return@mapNotNull null
            runCatching { ChecklistLoader.json.decodeFromJsonElement(StateRule.serializer(), o) }.getOrNull()?.let { code.uppercase() to it }
        }.toMap()
    }

    fun stateRule(code: String?): StateRule? = code?.takeIf { it.isNotBlank() }?.let { rules[it.uppercase()] }
    fun stateName(code: String?): String = states.firstOrNull { it.code.equals(code, true) }?.name ?: code.orEmpty()

    fun section(name: String): SectionDef? = sections.firstOrNull { it.name == name }
    fun depthId(label: String): String = depths.firstOrNull { it.label == label }?.id ?: "standard"
    fun depthLabel(id: String): String = depths.firstOrNull { it.id == id }?.label ?: "Standard"

    /** Report layout for an inspection type: [LAYOUT_TEXAS], [LAYOUT_FOUR_POINT] or [LAYOUT_STANDARD]. */
    fun reportLayout(inspType: String): String {
        val map = (reportLayouts["typeToLayout"] as? JsonObject).orEmpty()
        val key = (map[inspType] ?: map["*"])?.jsonPrimitive?.contentOrNull ?: return LAYOUT_STANDARD
        return when {
            key == "texas" -> LAYOUT_TEXAS
            key == "4 Point Inspection" || key.equals("fourPoint", true) || key.equals("4point", true) -> LAYOUT_FOUR_POINT
            else -> LAYOUT_STANDARD
        }
    }

    companion object {
        const val LAYOUT_STANDARD = "standard"
        const val LAYOUT_TEXAS = "texas"
        const val LAYOUT_FOUR_POINT = "fourPoint"
    }
}

/**
 * `features` (data v1.10). [sync] = cross-device sync (Phase 2). Phase 1 ships `false`: no sync pill / badges, no Settings
 * "Sync" section or Sync now, no automatic sync stub and no sync wording anywhere. The sync code stays behind this flag.
 * Defaults to false when the key is missing (Phase 1 never syncs).
 */
@Serializable
data class FeaturesDef(val sync: Boolean = false)

/** `features` of the loaded shared data, for UI code without a view model (registered by [ChecklistLoader.load]). */
object Features {
    @Volatile var sync: Boolean = false
        private set
    fun register(config: ChecklistConfig) { sync = config.features.sync }
}

@Serializable
data class StateDef(val code: String, val name: String)

/**
 * `stateRules.<CODE>` (see its `_about` in vims-checklists.json):
 * type = auto-selected inspection type · note = info card under the State field · summaryDisclosure = permanent entry at
 * the top of the Summary screen and page 1 of the PDF summary · coverNotice = extra line under the cover's ownership
 * notice · docs = PDFs (paths relative to shared/) that must be given to the client with the inspection agreement ·
 * agentCopyDefault = initial value of the wizard's "Send the report to the real estate agent" checkbox (null = true; NH = false, v1.4).
 */
@Serializable
data class StateRule(
    val type: String? = null,
    val note: String? = null,
    val summaryDisclosure: String? = null,
    val coverNotice: String? = null,
    val docs: List<StateDoc> = emptyList(),
    /** Raw JSON so an unexpected value (e.g. a string) can't drop the whole rule; read through [agentCopy]. */
    val agentCopyDefault: kotlinx.serialization.json.JsonElement? = null,
) {
    /** Default for "Send the report to the real estate agent" in this state (true unless the rule says false). */
    val agentCopy: Boolean get() = (agentCopyDefault as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim()?.lowercase()?.let { it != "false" && it != "no" && it != "0" } ?: true
}

@Serializable
data class StateDoc(val name: String, val file: String)

@Serializable
data class DepthDef(val id: String, val label: String)

@Serializable
data class SectionGroupDef(val group: String, val sections: List<String> = emptyList())

@Serializable
data class SectionDef(
    val name: String,
    val number: Int = 99,
    val icon: String? = null,
    val photoCategories: List<String> = emptyList(),
    val photoCategoriesHigh: List<String>? = null,
    val items: List<ItemDef> = emptyList(),
    val itemsHigh: List<ItemDef>? = null,
    /** State / insurance form (texas | fourPoint): ignores checklist depth, no Overall condition row. */
    val form: String? = null,
    /** Picture page only: opening it goes straight to the photo screen. */
    val photosOnly: Boolean = false,
    /** Data v1.7 (Indoor Air Quality): the report prints this section's `airReading` items as the client's readings table. */
    val airQuality: AirQualityDef? = null,
    /**
     * Data v1.8 `sectionFields.title`: display name in lists, the wizard, section headers and the report ("Septic System",
     * "Wood Destroying Organism Inspection"). [name] stays the stable key saved inspections use. Read through [sectionTitle].
     */
    val title: String? = null,
    /** Data v1.8 `sectionFields.reportNote`: paragraphs printed after the section's items and before Overall condition (Radon). */
    val reportNote: List<String>? = null,
    /**
     * Data v1.9 `formReport` (key of `formReports`): the report prints this section as form pages — "oir-b1-1802" (Wind
     * Mitigation, Florida's Uniform Mitigation Verification Inspection Form) or "wdi" (Wood Destroying Insect report). Only
     * snapshots taken from v1.9 data carry it; older inspections keep the normal checklist page.
     */
    val formReport: String? = null,
) {
    /** What the app and the report show for this section. */
    val displayName: String get() = title?.takeIf { it.isNotBlank() } ?: name
}

/**
 * Display name for a section key, e.g. "Septic" → "Septic System", "Termite" → "Wood Destroying Organism Inspection"
 * (data v1.8 `title`); numbered rooms keep their number ("Bedroom 2"); admin-added sections show their own name.
 * Uses the live shared data (registered by [ChecklistLoader.load]), so inspections built before v1.8 show the new titles too.
 */
fun sectionTitle(name: String): String = SectionTitles.of(name)

object SectionTitles {
    @Volatile private var titles: Map<String, String> = emptyMap()
    fun register(config: ChecklistConfig) {
        titles = config.sections.mapNotNull { s -> s.title?.takeIf { it.isNotBlank() && it != s.name }?.let { s.name to it } }.toMap()
    }
    fun of(name: String): String {
        titles[name]?.let { return it }
        val base = baseName(name)
        return if (base != name) titles[base]?.let { it + name.removePrefix(base) } ?: name else name
    }
}

/**
 * `sections[].airQuality` (data v1.7): legend (top-right of the table), rating → word, the two value column heads and the
 * prefix of each reading's corrective-action line. Defaults = the client's Oct 12 2026 form.
 */
@Serializable
data class AirQualityDef(
    val legend: String = "1 & 2 Good · 3 Mild · 4 Moderate · 5 Severe · 6 Serious",
    val ratings: Map<String, String> = emptyMap(),
    val columns: List<String> = listOf("Level Measured", "Air Quality Rating"),
    val actionPrefix: String = "Corrective action if needed — ",
)

/**
 * One checklist line. Either a sub-section header band (`header`) or a question (`q` + `type`).
 * Types: single · multi · num · text · date · time · airReading (v1.7); an unknown type is shown as a text input.
 * `airReading` also carries [code], [unit], [reference] and [action] for the Indoor Air Quality report table;
 * its answer is stored as described on [SectionAnswers] (rating in `values`, level in `inputs`).
 */
@Serializable
data class ItemDef(
    val q: String? = null,
    val type: String? = null,
    val options: List<String>? = null,
    val header: String? = null,
    val placeholder: String? = null,
    val code: String? = null,
    val unit: String? = null,
    val reference: String? = null,
    val action: String? = null,
    /** Data v1.8 `itemTypes.visibleIf`: shown only when another item in the same section matches (see [VisibleIf]). */
    val visibleIf: VisibleIf? = null,
    /** Data v1.9: starts with an inspection / company value on first open (client, street, city, zip, clientPhone, clientEmail, licenseType, initials). */
    val prefill: String? = null,
    /** Data v1.9 form-report hints: the form question an item answers (q1 … q7, II, license) / the table it fills (q7 chart). */
    val formKey: String? = null,
    val formTable: String? = null,
    /**
     * Data v1.9.1 `num` limits (team QA Oct 22): `integer: true` = whole numbers only (number pad, no "."); `decimals: n` =
     * at most n decimal places (default 2). Null when not set, so older snapshots stay as they were stored.
     */
    val integer: Boolean? = null,
    val decimals: Int? = null,
) {
    val isHeader: Boolean get() = header != null
    /** Decimal places a `num` item accepts while typing: 0 for `integer`, else `decimals` (default 2). */
    val numDecimals: Int get() = if (integer == true) 0 else (decimals ?: 2).coerceIn(0, 6)
    val isChoice: Boolean get() = type == "single" || type == "multi"
    val isAirReading: Boolean get() = type == TYPE_AIR_READING

    companion object {
        const val TYPE_AIR_READING = "airReading"
    }
}

/**
 * `visibleIf` (data v1.8): `{q, atLeast: n}` = that item's single-choice answer is a number ≥ n ("Samples taken" ≥ 2);
 * `{q, includes: option}` = that item's answer (single or multi) includes the option ("Area tested" includes "Other").
 * Hidden items are not validated and not printed. Evaluated by [ChecklistEngine.isVisible].
 */
@Serializable
data class VisibleIf(val q: String, val atLeast: Double? = null, val includes: String? = null)

@Serializable
data class ChecklistBuilderDef(
    val phaseTypes: Map<String, List<LayoutGroupDef>> = emptyMap(),
    val standardLayout: List<LayoutGroupDef> = emptyList(),
)

@Serializable
data class LayoutGroupDef(
    val heading: String,
    val link: String? = null,
    val icon: String? = null,
    val sections: List<String>? = null,
    val always: List<String>? = null,
    val optional: String? = null,
    val order: List<String>? = null,
    val then: List<String>? = null,
    val sub: LayoutGroupDef? = null,
)

@Serializable
data class WizardDef(
    val steps: List<String> = emptyList(),
    val inspectionTypes: List<String> = emptyList(),
    val componentOptions: List<String> = emptyList(),
    val structureTypes: List<String> = emptyList(),
    val structureSideEffects: Map<String, Map<String, String>> = emptyMap(),
    val unitMixDefault: Map<String, Int> = emptyMap(),
    val step1: List<WizardFieldDef> = emptyList(),
    val step2: List<WizardFieldDef> = emptyList(),
    val exteriorOptions: List<String> = emptyList(),
    val roomOptions: List<String> = emptyList(),
    val utilityOptions: List<String> = emptyList(),
    val testOptions: List<String> = emptyList(),
    val roomCounts: List<RoomCountDef> = emptyList(),
    val defaults: WizardDefaults = WizardDefaults(),
    /** Extra step-1 fields per inspection type (Texas sponsor, 4-Point insured / policy #). */
    val typeFields: JsonObject = JsonObject(emptyMap()),
    /**
     * Data v1.10 (client Oct 25): types no longer offered for new inspections ("Code"). An inspection saved with one keeps it
     * and opens / prints normally; the edit wizard still shows it (selected) for that inspection only.
     */
    val retiredInspectionTypes: List<String> = emptyList(),
    /**
     * Data v1.10 (client Oct 25): with one of these types, step 3 locks the exterior, interior room and utility options (shown
     * disabled with a short note) and they add no sections; the room counts stay editable. Another type unlocks them, earlier
     * choices intact.
     */
    val areasLockedTypes: List<String> = emptyList(),
) {
    /** Step 3 areas are locked (not used) for this inspection type. */
    fun areasLocked(inspType: String): Boolean = inspType in areasLockedTypes

    /**
     * Type of inspection chips: the current types, plus [savedType] (the edited inspection's saved type) when it is no longer
     * offered — a retired type such as "Code" — so an older inspection still shows its own type. New inspections pass null.
     */
    fun typeOptions(savedType: String?): List<String> =
        if (!savedType.isNullOrBlank() && savedType !in inspectionTypes) inspectionTypes + savedType else inspectionTypes

    fun typeFieldsFor(inspType: String): List<TypeFieldDef> =
        (typeFields[inspType] as? JsonArray)?.mapNotNull { e ->
            val o = e as? JsonObject ?: return@mapNotNull null
            val label = o["label"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            TypeFieldDef(label, o["key"]?.jsonPrimitive?.contentOrNull ?: label)
        }.orEmpty()
}

data class TypeFieldDef(val label: String, val key: String)



@Serializable
data class WizardFieldDef(
    val kind: String,
    val label: String,
    val type: String? = null,
    val placeholder: String? = null,
    val id: String? = null,
    val single: Boolean = true,
    val options: List<String>? = null,
    val default: String? = null,
    /** Data v1.9.1: the field must be answered on Next (Type of inspection). */
    val required: Boolean = false,
)

@Serializable
data class RoomCountDef(val key: String, val label: String)

@Serializable
data class WizardDefaults(
    /** Data v1.9.1 (team QA Oct 22): null = nothing preselected — Type of inspection is required on step 1. */
    val inspType: String? = null,
    val loan: String? = null,
    val structure: String = "Single Family",
    val depth: String = "standard",
    val bedrooms: Int = 0,
    val bathrooms: Int = 0,
    val hallways: Int = 0,
    val rooms: Map<String, Int> = emptyMap(),
    val exterior: Map<String, Int> = emptyMap(),
    val utilOpt: Map<String, Int> = emptyMap(),
    val tests: Map<String, Int> = emptyMap(),
)

@Serializable
data class FindingsDef(
    val categories: List<FindingCategoryDef> = emptyList(),
    val quickComments: List<String> = emptyList(),
)

@Serializable
data class FindingCategoryDef(val id: Int, val label: String, val note: String = "")

@Serializable
data class CoversDef(
    val colors: List<CoverColorDef> = emptyList(),
    val categories: Map<String, List<String>> = emptyMap(),
    /** Data v1.8: Shaded, Framed, Solid (in that order). Solid is a style like the others and can carry a theme picture. */
    val styles: List<String> = listOf("Shaded", "Framed", "Solid"),
    /** Data v1.8: the theme option for a cover without a picture. */
    val noThemeOption: String = CoverChoice.NO_PICTURE,
    @SerialName("default") val defaultCover: CoverChoice = CoverChoice(),
    /** Data v1.6: the client's cover design (positions in inches on US Letter, origin top-left). */
    val layout: CoverLayoutDef = CoverLayoutDef(),
    /** Data v1.6: theme option → its artwork (asset path under shared/) and where it sits on the cover, in inches. */
    val themeArt: Map<String, ThemeArtDef> = emptyMap(),
) {
    fun art(cover: CoverChoice): ThemeArtDef? = cover.normalized().takeIf { it.hasPicture }?.let { themeArt[it.option] }
}

/**
 * A cover color. light / mid / deep / solid = the client's cover fills (v1.6: Framed page fill + glow, Shaded gradient,
 * Solid fill); from / to = the app's UI swatch gradient.
 */
@Serializable
data class CoverColorDef(
    val name: String,
    val from: String,
    val to: String,
    val light: String = "#F7FAFD",
    val mid: String = "#B5D2EC",
    val deep: String = "#237AD4",
    val solid: String = "#8DBAE9",
)

/** `covers.layout` (v1.6), all in inches on a US Letter page; defaults = the client's "Cover - Master example". */
@Serializable
data class CoverLayoutDef(
    val pageBox: List<Float> = listOf(0.5f, 0.68f, 7.48f, 9.52f),
    val logo: CoverRectDef = CoverRectDef(listOf(0.6f, 0.75f, 1.6f, 1.1f)),
    val companyInfo: CoverRectDef = CoverRectDef(listOf(4.3f, 0.8f, 3.55f, 1.1f)),
    val title: CoverTitleDef = CoverTitleDef(),
    val fields: CoverFieldsDef = CoverFieldsDef(),
    val photoBox: CoverPhotoBoxDef = CoverPhotoBoxDef(),
    val footer: CoverFooterDef = CoverFooterDef(),
)

@Serializable
data class CoverRectDef(val rect: List<Float> = emptyList())

@Serializable
data class CoverTitleDef(val text: String = "Inspection Report", val centerY: Float = 2.17f, val size: Float = 20f)

@Serializable
data class CoverFieldsDef(val top: Float = 2.62f, val lineGap: Float = 0.47f, val left: Float = 1.3f, val right: Float = 7.2f)

/** `covers.layout.footer.box` (data v1.8), [x, y, w, h] in inches: the footer text box, left half (right half when the art is on the left). */
@Serializable
data class CoverFooterBoxDef(
    val left: List<Float> = listOf(0.55f, 9.3f, 3.7f, 0.85f),
    val right: List<Float> = listOf(4.25f, 9.3f, 3.7f, 0.85f),
)

@Serializable
data class CoverPhotoBoxDef(val rect: List<Float> = listOf(1.2f, 5.1f, 6.08f, 4.15f), val border: Float = 1.25f)

@Serializable
data class CoverFooterDef(
    val centerY: Float = 9.65f,
    val size: Float = 11f,
    val text: String = "This inspection report is the property of {companyName}.\nAny reproduction or distribution without written consent is prohibited.",
    val box: CoverFooterBoxDef = CoverFooterBoxDef(),
)

@Serializable
data class ThemeArtDef(val file: String, val rect: List<Float>)

@Serializable
data class SubscriptionDef(
    val trialDays: Int = 30,
    val plans: List<Plan> = emptyList(),
    val extraInspectorMonthly: Double = 0.0,
)

@Serializable
data class SupportDef(
    val feedbackEmail: String = "",
    val reportBcc: ReportBccDef = ReportBccDef(),
    /** Data v1.3: every emailed report is CC'd to the signed-in inspector's own email (present = on). */
    val ccInspector: JsonObject? = null,
    /** Data v1.5: VIMS platform owners (system admins) by email — see [com.vims.app.data.PlatformOwners]. */
    val platformOwners: List<String> = emptyList(),
    /** Data v1.9.2: old shipped defaults; a stored platform setting still equal to one is moved to the current default on launch. */
    val replacedDefaults: ReplacedDefaultsDef = ReplacedDefaultsDef(),
    /** Data v1.9.2: the client's vimsinspect.com mailboxes (informational: masterAdmin, admin, support, quality). */
    val domainEmails: Map<String, String> = emptyMap(),
) {
    val ccInspectorOn: Boolean get() = ccInspector != null
}

/** `support.replacedDefaults` (data v1.9.2): previous default addresses, matched trimmed and case-insensitively. */
@Serializable
data class ReplacedDefaultsDef(val feedbackEmail: List<String> = emptyList(), val reportBccEmail: List<String> = emptyList())

/** Default for the platform owner's "Report quality copy (BCC)" setting (data v1.2). */
@Serializable
data class ReportBccDef(val on: Boolean = false, val email: String = "")

@Serializable
data class SampleDef(
    val company: SampleCompany? = null,
    val inspectors: List<SampleInspector> = emptyList(),
    val findings: List<SampleFinding> = emptyList(),
)

@Serializable
data class SampleCompany(val name: String, val code: String)

@Serializable
data class SampleInspector(val name: String, val email: String = "", val owner: Boolean = false)

@Serializable
data class SampleFinding(val cat: Int, val txt: String, val sec: String)

object ChecklistLoader {
    const val ASSET_PATH = "data/vims-checklists.json"

    val json = Json {
        ignoreUnknownKeys = true
        explicitNulls = false
        encodeDefaults = true
        isLenient = true
    }

    fun load(context: Context): ChecklistConfig =
        context.assets.open(ASSET_PATH).bufferedReader().use { json.decodeFromString(ChecklistConfig.serializer(), it.readText()) }
            .also { SectionTitles.register(it); Features.register(it) }
}
