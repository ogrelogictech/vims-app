package com.vims.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Client Nov 17 (shared v1.25.0): three states now require the client to own the report. Against the real shared JSON. */
class Nov17ReportOwnershipTest {
    private val config = TestData.config
    private val agreement = TestData.agreement

    @Test fun data_version() {
        // Shared v1.25.0 or later (Nov18CoversAndWeatherTest pins the current version).
        assertTrue(config.version, config.version.split(".").map { it.toInt() }.let { (a, b, _) -> a > 1 || (a == 1 && b >= 25) })
        assertEquals("2026-11-17", agreement.version)
    }

    @Test fun coverFooter_preparedBy_notProperty() {
        val text = config.covers.layout.footer.text
        assertEquals("This inspection report was prepared by {companyName}.\nAny reproduction or distribution without written consent is prohibited.", text)
        assertFalse(text.contains("property of"))
        // The bundled fallback matches the shared data.
        assertEquals(text, CoverFooterDef().text)
    }

    @Test fun agreementTerms_AtoE() {
        val texts = agreement.body.map { it.text }
        val i = texts.indexOfFirst { it.endsWith("Inspection Agreement TERMS AND CONDITIONS:") }
        assertTrue(i >= 0)
        val terms = texts.subList(i + 1, i + 6)
        assertEquals(listOf("A.", "B.", "C.", "D.", "E."), terms.map { it.take(2) })
        assertTrue(terms[0].startsWith("A. The Client agrees that the inspection report reflects the condition of the property at the time of the inspection only."))
        assertTrue(terms[1].startsWith("B. The Client agrees that the inspection report is for their sole benefit"))
        assertTrue(terms[1].contains("\$100.00 fee for each additional report"))
        assertTrue(terms[2].startsWith("C. If there is a claim of missed defect"))
        assertTrue(terms[4].startsWith("E. The Client agrees that this agreement represents the entire agreement"))
        assertFalse(texts.any { "licensed to receive a copy" in it })
        assertTrue(texts[i + 6].startsWith("STATUTE OF LIMITATIONS"))
    }
}
