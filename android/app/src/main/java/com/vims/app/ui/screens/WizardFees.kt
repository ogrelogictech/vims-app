package com.vims.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.vims.app.data.Fees
import com.vims.app.data.WizardSelections
import com.vims.app.data.sectionTitle
import com.vims.app.ui.AgreementR
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.components.BtnKind
import com.vims.app.ui.components.Hint
import com.vims.app.ui.components.Lbl
import com.vims.app.ui.components.LockedNote
import com.vims.app.ui.components.VBtn
import com.vims.app.ui.components.VChip
import com.vims.app.ui.components.VInput
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.util.Filters
import com.vims.app.util.GroupedNumberTransform

private val AMOUNT_W = 126.dp
private val PAIR_GAP = 14.dp
/** A column narrower than this holds one pair per row (phones): at this width every chip but the longest fits beside its box. */
private val MIN_COLUMN = 276.dp

/**
 * Wizard step 4 "Utilities, testing & fees" (`wizard.fees`, client's mockup Nov 4): Utility & systems and Testing, each chip with a
 * $ box, then Out of service area surcharge (client Nov 13, its own row), Inspection Fee, Bundled Secondary Testing and Total Cost
 * of Inspection, then the agreement button (Back / Build checklist follow in the wizard). Nothing here is required. Utilities stay
 * locked for `wizard.areasLockedTypes`, boxes included; the surcharge never is.
 */
@Composable
fun WizardFeesStep(vm: AppViewModel, nav: NavHostController, sel: WizardSelections) {
    val cfg = vm.config.wizard
    val locked = cfg.areasLocked(sel.inspType)
    Lbl("Utility & systems", first = true)
    if (locked) LockedNote("Utility & systems aren't used for a ${inspectionNoun(sel.inspType)}.", Modifier.padding(bottom = 10.dp))
    FeeGrid(cfg.utilityOptions, sel, utility = true, enabled = !locked, vm)
    Hint("Add any secondary testing for this inspection.", Modifier.padding(top = 18.dp, bottom = 12.dp))
    FeeGrid(cfg.testOptions, sel, utility = false, enabled = true, vm)
    Box(Modifier.padding(top = 10.dp, bottom = 18.dp).fillMaxWidth().height(1.5.dp).background(V.ink3))

    val totals = Fees.totals(sel, locked)
    Columns { two ->
        val surcharge: @Composable (Modifier) -> Unit = { m ->
            FeeLine("Out of service area surcharge", m) { w -> AmountBox(sel.surcharge, { v -> vm.updateSel { it.copy(surcharge = v) } }, w, "Out of service area surcharge amount") }
        }
        val inspection: @Composable (Modifier) -> Unit = { m ->
            FeeLine("Inspection Fee", m) { w -> AmountBox(sel.inspectionFee, { v -> vm.updateSel { it.copy(inspectionFee = v) } }, w, "Inspection fee amount") }
        }
        val bundled: @Composable (Modifier) -> Unit = { m -> FeeLine("Bundled Secondary Testing", m) { w -> ReadOnlyAmount(totals.bundled, w, "Bundled secondary testing") } }
        val total: @Composable (Modifier) -> Unit = { m -> FeeLine("Total Cost of Inspection", m) { w -> ReadOnlyAmount(totals.total, w, "Total cost of inspection") } }
        if (two) {
            // Client Nov 13 screen print: the surcharge alone on its row, right above Inspection Fee.
            Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(PAIR_GAP)) { surcharge(Modifier.weight(1f)); Spacer(Modifier.weight(1f)) }
            Row(Modifier.fillMaxWidth().padding(bottom = 10.dp), horizontalArrangement = Arrangement.spacedBy(PAIR_GAP)) { inspection(Modifier.weight(1f)); bundled(Modifier.weight(1f)) }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(PAIR_GAP)) { total(Modifier.weight(1f)); Spacer(Modifier.weight(1f)) }
        } else {
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) { surcharge(Modifier); inspection(Modifier); bundled(Modifier); total(Modifier) }
        }
        Box(Modifier.padding(top = 20.dp).fillMaxWidth(if (two) .5f else 1f)) {
            VBtn("View Pre-filled Inspection Agreement", { nav.navigate(AgreementR(sel.state, wizard = true)) }, kind = BtnKind.Ghost)
        }
    }
}

/** Two columns when each is wide enough for a chip and its box (tablets), else one (phones, large text). */
@Composable
private fun Columns(content: @Composable (two: Boolean) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val fs = LocalDensity.current.fontScale.coerceAtLeast(1f)
        val two = (maxWidth - PAIR_GAP) / 2 >= MIN_COLUMN * fs
        Column(Modifier.fillMaxWidth()) { content(two) }
    }
}

/** Chips with $ boxes, in the order given: two pairs per row where they fit. A chip too long for half a row takes a whole row, as in the mockup. */
@Composable
private fun FeeGrid(options: List<String>, sel: WizardSelections, utility: Boolean, enabled: Boolean, vm: AppViewModel) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val density = LocalDensity.current
        val fs = density.fontScale.coerceAtLeast(1f)
        val boxW = AMOUNT_W * fs
        val half = (maxWidth - PAIR_GAP) / 2
        val two = half >= MIN_COLUMN * fs
        val measurer = rememberTextMeasurer()
        // VChip: 15dp padding each side, 1.5dp border.
        val chipStyle = T.ui(13.5.sp, FontWeight.Medium)
        fun chipWidth(text: String) = with(density) { measurer.measure(text, chipStyle).size.width.toDp() } + 33.dp
        fun fitsHalf(o: String) = chipWidth(sectionTitle(o)) <= half - boxW - 8.dp
        // Very small phone + large text: a chip that couldn't hold its longest word beside the box goes above it.
        val rowWidth = maxWidth
        fun stacks(o: String) = sectionTitle(o).split(' ').maxOf { chipWidth(it) } > rowWidth - boxW - 8.dp
        val rows = buildList {
            var open: String? = null
            options.forEach { o ->
                when {
                    !two || !fitsHalf(o) -> { open?.let { add(listOf(it, "")) }; open = null; add(listOf(o)) }
                    open == null -> open = o
                    else -> { add(listOf(open!!, o)); open = null }
                }
            }
            open?.let { add(listOf(it, "")) }
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            rows.forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(PAIR_GAP)) {
                    row.forEach { o ->
                        if (o.isEmpty()) Spacer(Modifier.weight(1f))
                        else FeeOption(o, sel, utility, enabled, boxW, vm, Modifier.weight(1f), stacks(o))
                    }
                }
            }
        }
    }
}

@Composable
private fun FeeOption(option: String, sel: WizardSelections, utility: Boolean, enabled: Boolean, boxW: Dp, vm: AppViewModel, modifier: Modifier, stacked: Boolean) {
    val label = sectionTitle(option)
    val chip: @Composable () -> Unit = {
        VChip(label, option in (if (utility) sel.utilities else sel.tests), { vm.updateSel { it.toggleFeeOption(option, utility) } }, enabled = enabled)
    }
    // A locked option's box shows empty; its amount is kept for when another type unlocks it.
    val box: @Composable () -> Unit = { AmountBox(if (enabled) sel.fees[option].orEmpty() else "", { v -> vm.updateSel { it.withFeeAmount(option, utility, v) } }, boxW, "$label amount", enabled) }
    if (stacked) {
        Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp), horizontalAlignment = Alignment.End) {
            Box(Modifier.fillMaxWidth()) { chip() }
            box()
        }
    } else {
        Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f)) { chip() }
            box()
        }
    }
}

/** A typed amount: "$" + decimal keypad, up to 2 decimals, 0 to 99,999.99 (the filter stops anything else while typing). */
@Composable
private fun AmountBox(value: String, onChange: (String) -> Unit, width: Dp, spoken: String, enabled: Boolean = true) {
    Row(Modifier.width(width), verticalAlignment = Alignment.CenterVertically) {
        Text("$", style = T.ui(15.sp, FontWeight.Bold, if (enabled) V.ink else V.ink3), modifier = Modifier.padding(end = 5.dp))
        VInput(value, onChange, Modifier.weight(1f), keyboard = KeyboardType.Decimal, filter = { Filters.number(it, 2, Fees.MAX) }, visual = GroupedNumberTransform,
            imeAction = ImeAction.Next, contentDescription = spoken, enabled = enabled, autoCorrect = false)
    }
}

/** A computed amount, in a box that reads as not editable; 0.00 stays faint until there's something to add up. */
@Composable
private fun ReadOnlyAmount(cents: Long, width: Dp, spoken: String) {
    val shape = RoundedCornerShape(11.dp)
    Row(Modifier.width(width).semantics(mergeDescendants = true) { contentDescription = "$spoken: $${Fees.grouped(cents)}" }, verticalAlignment = Alignment.CenterVertically) {
        Text("$", style = T.ui(15.sp, FontWeight.Bold, V.ink), modifier = Modifier.padding(end = 5.dp))
        Box(Modifier.weight(1f).heightIn(min = 48.dp).clip(shape).background(V.paper3).border(1.dp, V.line, shape).padding(horizontal = 10.dp), contentAlignment = Alignment.CenterStart) {
            Text(Fees.grouped(cents), style = T.ui(15.sp, FontWeight.SemiBold, if (cents > 0) V.ink else V.ink3), maxLines = 1, softWrap = false)
        }
    }
}

/** Label beside its box; above it when the side wouldn't hold the label's longest word (small phones with large text). */
@Composable
private fun FeeLine(label: String, modifier: Modifier, box: @Composable (Dp) -> Unit) {
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val fs = LocalDensity.current.fontScale.coerceAtLeast(1f)
        val boxW = 148.dp * fs
        val text: @Composable (Modifier) -> Unit = { m -> Text(label, style = T.ui(14.sp, FontWeight.Bold, lineHeight = 18.sp), modifier = m) }
        if (maxWidth - boxW - 8.dp >= 120.dp * fs) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                text(Modifier.weight(1f))
                box(boxW)
            }
        } else {
            val full = maxWidth
            Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                text(Modifier)
                box(full)
            }
        }
    }
}
