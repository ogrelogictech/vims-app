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
) {
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
)

@Serializable
data class CoverColorDef(val name: String, val from: String, val to: String)

@Serializable
data class SubscriptionDef(
    val trialDays: Int = 30,
    val plans: List<Plan> = emptyList(),
    val extraInspectorMonthly: Double = 0.0,
)

@Serializable
data class SupportDef(val feedbackEmail: String = "")

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
