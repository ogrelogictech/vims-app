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
)

/** One checklist line. Either a sub-section header band (`header`) or a question (`q` + `type`). */
@Serializable
data class ItemDef(
    val q: String? = null,
    val type: String? = null,
    val options: List<String>? = null,
    val header: String? = null,
    val placeholder: String? = null,
) {
    val isHeader: Boolean get() = header != null
    val isChoice: Boolean get() = type == "single" || type == "multi"
}

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
) {
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
)

@Serializable
data class RoomCountDef(val key: String, val label: String)

@Serializable
data class WizardDefaults(
    val inspType: String = "Real Estate Sale",
    val loan: String = "Conventional",
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
    val styles: List<String> = emptyList(),
    val solidStyle: String = "Solid",
    @SerialName("default") val defaultCover: CoverChoice = CoverChoice(),
    /** Data v1.6: the client's cover design (positions in inches on US Letter, origin top-left). */
    val layout: CoverLayoutDef = CoverLayoutDef(),
    /** Data v1.6: theme option → its artwork (asset path under shared/) and where it sits on the cover, in inches. */
    val themeArt: Map<String, ThemeArtDef> = emptyMap(),
) {
    fun art(cover: CoverChoice): ThemeArtDef? = if (cover.category == "Solid") null else themeArt[cover.option]
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

@Serializable
data class CoverPhotoBoxDef(val rect: List<Float> = listOf(1.2f, 5.1f, 6.08f, 4.15f), val border: Float = 1.25f)

@Serializable
data class CoverFooterDef(
    val centerY: Float = 9.65f,
    val size: Float = 11f,
    val text: String = "This inspection report is the property of {companyName}.\nAny reproduction or distribution without written consent is prohibited.",
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
) {
    val ccInspectorOn: Boolean get() = ccInspector != null
}

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
}
