package com.vims.app.data

import java.io.File

/** The real shared files, the ones the app ships (Gradle runs unit tests in android/app). */
internal object TestData {
    private fun shared(path: String) = listOf("../../shared/$path", "../shared/$path").map(::File).first { it.exists() }.readText()
    val config: ChecklistConfig by lazy { ChecklistLoader.json.decodeFromString(ChecklistConfig.serializer(), shared("data/vims-checklists.json")) }
    val agreement: InspectionAgreement by lazy { ChecklistLoader.json.decodeFromString(InspectionAgreement.serializer(), shared("legal/inspection-agreement.json")) }
    val prefill: AgreementPrefillDef get() = config.agreementPrefill
    /** The form block as the viewer shows it. */
    val pieces: List<AgreementPiece> get() = agreement.pieces("Acme", "UT") { it }
    /** A line of the original form block, by something it contains. */
    fun original(part: String): String = agreement.formLines("Acme").first { part in it }
}
