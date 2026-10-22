package com.vims.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.FlowRowScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.autofill.ContentDataType
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDataType
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.vims.app.ui.theme.T
import com.vims.app.ui.theme.V
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Filters

/* ---------------------------------------------------------------- header / screen shell */

data class HdrAction(val icon: ImageVector, val label: String, val onClick: () -> Unit)

/** Sync status shown in the blue top strip (the prototype's "Offline · 1 queued" badge). */
data class NetState(val pending: Int, val synced: Boolean, val online: Boolean = true)

@Composable
fun NetBadge(net: NetState) {
    // Sync badge: queued = amber ("N queued" online, "Offline · N queued" offline), Synced = green, Offline (nothing waiting) = gray.
    val (bg, fg) = when {
        net.pending > 0 -> Color(0x38E4A11B) to Color(0xFFF2C869)
        net.online -> Color(0x422F9E6B) to Color(0xFF7CE0AF)
        else -> Color(0x33FFFFFF) to Color(0xFFD7E3F7)
    }
    val text = if (net.pending > 0) (if (net.online) "${net.pending} queued" else "Offline · ${net.pending} queued") else if (net.online) "Synced" else "Offline"
    Row(
        Modifier.clip(RoundedCornerShape(20.dp)).background(bg).padding(horizontal = 9.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Box(Modifier.size(6.dp).clip(CircleShape).background(fg))
        Text(text, style = T.mono(11.sp, color = fg))
    }
}

@Composable
fun TopStrip(net: NetState) {
    Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 16.dp, top = 2.dp, bottom = 4.dp), horizontalArrangement = Arrangement.End) { NetBadge(net) }
}

@Composable
fun HdrButton(icon: ImageVector, label: String, onClick: () -> Unit) {
    Box(
        Modifier.size(44.dp).clip(RoundedCornerShape(11.dp)).background(Color.White.copy(alpha = .12f))
            .clickable(role = Role.Button, onClickLabel = label, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Icon(icon, contentDescription = label, tint = Color.White, modifier = Modifier.size(20.dp)) }
}

@Composable
fun AppHeader(title: String, subtitle: String, net: NetState, left: HdrAction?, actions: List<HdrAction> = emptyList(), subtitleLeading: (@Composable () -> Unit)? = null) {
    Column(Modifier.fillMaxWidth().background(V.hdr).statusBarsPadding()) {
        TopStrip(net)
        androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxWidth()) {
            // The title gets what the buttons leave. Long section titles ("Wood Destroying Organism Inspection") wrap to a
            // second, slightly smaller line; when even two lines don't fit (small phones, large font sizes — team QA Oct 22)
            // the title moves under the buttons and uses the full width instead of ending in "…".
            val measurer = androidx.compose.ui.text.rememberTextMeasurer()
            val density = LocalDensity.current
            val big = T.display(17.sp, FontWeight.Bold, Color.White)
            val small = T.display(15.sp, FontWeight.Bold, Color.White, lineHeight = 18.sp)
            val colW = maxWidth - 24.dp - (if (left != null) 54.dp else 0.dp) - (if (actions.isNotEmpty()) (actions.size * 51 + 3).dp else 0.dp)
            val mode = remember(title, colW, density.fontScale) {
                val px = with(density) { colW.roundToPx() }.coerceAtLeast(1)
                fun fits(style: TextStyle, lines: Int) = !measurer.measure(title, style, maxLines = lines, constraints = androidx.compose.ui.unit.Constraints(maxWidth = px)).hasVisualOverflow
                when {
                    title.length <= 24 && fits(big, 1) -> 0
                    fits(small, 2) -> 1
                    else -> 2
                }
            }
            @Composable
            fun Titles(modifier: Modifier, style: TextStyle, lines: Int) = Column(modifier) {
                Text(title, style = style, maxLines = lines, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (subtitleLeading != null) { subtitleLeading(); Spacer(Modifier.width(6.dp)) }
                    Text(subtitle, style = T.ui(12.sp, color = V.hdrSub), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
            }
            if (mode < 2) {
                Row(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 2.dp, bottom = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    if (left != null) HdrButton(left.icon, left.label, left.onClick)
                    Titles(Modifier.weight(1f), if (mode == 0) big else small, if (mode == 0) 1 else 2)
                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) { actions.forEach { HdrButton(it.icon, it.label, it.onClick) } }
                }
            } else Column(Modifier.fillMaxWidth().padding(start = 12.dp, end = 12.dp, top = 2.dp, bottom = 12.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                    if (left != null) HdrButton(left.icon, left.label, left.onClick)
                    Spacer(Modifier.weight(1f))
                    actions.forEach { HdrButton(it.icon, it.label, it.onClick) }
                }
                Titles(Modifier.fillMaxWidth().padding(start = 2.dp, top = 8.dp), big.copy(lineHeight = 21.sp), 3)
            }
        }
    }
}

/** Screen with the blue header and a scrolling body (16dp padding, like `.screen`). */
@Composable
fun VScreen(
    title: String, subtitle: String, net: NetState, left: HdrAction?, actions: List<HdrAction> = emptyList(),
    scroll: Boolean = true, padding: PaddingValues = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 34.dp),
    overlay: @Composable BoxScope.() -> Unit = {}, subtitleLeading: (@Composable () -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Box(Modifier.fillMaxWidth().background(V.paper2)) {
        Column(Modifier.fillMaxWidth()) {
            AppHeader(title, subtitle, net, left, actions, subtitleLeading)
            if (scroll) {
                Column(
                    Modifier.fillMaxWidth().weight(1f).imePadding().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(padding),
                    content = { ContentWidth { content() } },
                )
            } else {
                Column(Modifier.fillMaxWidth().weight(1f).imePadding().navigationBarsPadding(), content = content)
            }
        }
        overlay()
    }
}

/** Keeps content at phone width on tablets (the prototype's 430px column). */
@Composable
fun ContentWidth(content: @Composable ColumnScope.() -> Unit) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 600.dp).fillMaxWidth(), content = content)
    }
}

/* ---------------------------------------------------------------- text */

/** Minimal inline markup: **bold** segments. */
fun rich(text: String, boldColor: Color? = null): AnnotatedString = buildAnnotatedString {
    val parts = text.split("**")
    parts.forEachIndexed { i, p ->
        if (i % 2 == 1) pushStyle(SpanStyle(fontWeight = FontWeight.Bold, color = boldColor ?: Color.Unspecified))
        append(p)
        if (i % 2 == 1) pop()
    }
}

@Composable
fun Lbl(text: String, first: Boolean = false, modifier: Modifier = Modifier, required: Boolean = false) {
    val t = if (!required) AnnotatedString(text.uppercase()) else buildAnnotatedString {
        append(text.uppercase()); withStyle(SpanStyle(color = V.c1)) { append(" *") }
    }
    Text(
        t, style = T.mono(10.5.sp, color = V.ink3, letterSpacing = 0.12.em),
        modifier = modifier.padding(top = if (first) 2.dp else 20.dp, bottom = 10.dp).semantics { if (required) contentDescription = "$text, required" },
    )
}

@Composable
fun Hint(text: String, modifier: Modifier = Modifier, size: Float = 13f) {
    Text(rich(text), style = T.ui(size.sp, color = V.ink3, lineHeight = (size * 1.45f).sp), modifier = modifier)
}

/* ---------------------------------------------------------------- buttons */

/** Danger = c1 filled (confirm destructive); GhostDanger = ghost with c1 text (e.g. Cancel subscription). */
enum class BtnKind { Primary, Signal, Ghost, Danger, GhostDanger }

@Composable
fun VBtn(
    text: String, onClick: () -> Unit, modifier: Modifier = Modifier, kind: BtnKind = BtnKind.Primary, icon: ImageVector? = null,
    minHeight: Dp = 52.dp, enabled: Boolean = true,
) {
    val shape = RoundedCornerShape(13.dp)
    val (bg, fg) = when (kind) {
        BtnKind.Primary -> V.brand to Color.White
        BtnKind.Signal -> V.signal to V.signalInk
        BtnKind.Ghost -> V.paper to V.ink
        BtnKind.Danger -> V.c1 to Color.White
        BtnKind.GhostDanger -> V.paper to V.c1
    }
    var m = modifier.fillMaxWidth().heightIn(min = minHeight)
    if (kind == BtnKind.Primary) m = m.shadow(10.dp, shape, ambientColor = V.brand, spotColor = V.brand)
    m = m.clip(shape).background(if (enabled) bg else bg.copy(alpha = .5f))
    if (kind == BtnKind.Ghost || kind == BtnKind.GhostDanger) m = m.border(1.dp, V.line, shape)
    Row(
        m.clickable(enabled = enabled, role = Role.Button, onClick = onClick).padding(horizontal = 18.dp, vertical = 12.dp),
        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) { Icon(icon, null, tint = fg, modifier = Modifier.size(19.dp)); Spacer(Modifier.width(9.dp)) }
        Text(text, style = T.ui(15.sp, FontWeight.SemiBold, fg), textAlign = TextAlign.Center)
    }
}

@Composable
fun BtnRow(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(modifier.fillMaxWidth().padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp), content = content)
}

@Composable
fun TextLink(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) {
        Text(text, style = T.ui(12.5.sp, color = V.ink3), modifier = Modifier.clip(RoundedCornerShape(8.dp)).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 12.dp))
    }
}

/* ---------------------------------------------------------------- surfaces */

fun Modifier.vCard(radius: Dp = 14.dp, bg: Color = V.paper, border: Color = V.line): Modifier =
    this.clip(RoundedCornerShape(radius)).background(bg).border(1.dp, border, RoundedCornerShape(radius))

@Composable
fun VCard(modifier: Modifier = Modifier, padding: PaddingValues = PaddingValues(horizontal = 16.dp, vertical = 15.dp), bottom: Dp = 12.dp, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.padding(bottom = bottom).fillMaxWidth().vCard().padding(padding), content = content)
}

@Composable
fun Banner(text: String, icon: ImageVector = VIcons.info, modifier: Modifier = Modifier, blue: Boolean = false) {
    val shape = RoundedCornerShape(12.dp)
    val bg = if (blue) V.brand.copy(alpha = .08f) else V.c2Bg
    val border = if (blue) Color(0xFFC3D2F2) else V.bannerBorder
    val fg = if (blue) V.brandDeep else V.bannerText
    Row(modifier.padding(bottom = 14.dp).fillMaxWidth().clip(shape).background(bg).border(1.dp, border, shape).padding(horizontal = 14.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(11.dp)) {
        Icon(icon, null, tint = if (blue) V.brand else V.signalDeep, modifier = Modifier.padding(top = 1.dp).size(19.dp))
        Text(rich(text, if (blue) V.brandDeep else V.bannerBold), style = T.ui(12.5.sp, color = fg, lineHeight = 18.sp))
    }
}

/* ---------------------------------------------------------------- inputs */

/** Field label — the one style for every form field (prototype `label`: IBM Plex Sans 12.5sp semibold, ink-2). Required → red " *". */
val FieldLabelStyle: TextStyle @Composable get() = T.ui(12.5.sp, FontWeight.SemiBold, V.ink2)

@Composable
fun FieldLabel(text: String, required: Boolean = false, modifier: Modifier = Modifier) {
    val t = if (!required) androidx.compose.ui.text.AnnotatedString(text) else androidx.compose.ui.text.buildAnnotatedString {
        append(text); withStyle(androidx.compose.ui.text.SpanStyle(color = V.c1)) { append(" *") }
    }
    Text(t, style = FieldLabelStyle, modifier = modifier.padding(bottom = 7.dp).semantics { if (required) contentDescription = "$text, required" })
}

/** Small "* Required" legend for the top of longer forms. */
@Composable
fun RequiredHint(modifier: Modifier = Modifier) {
    Text(androidx.compose.ui.text.buildAnnotatedString {
        withStyle(androidx.compose.ui.text.SpanStyle(color = V.c1)) { append("*") }; append(" Required")
    }, style = T.ui(12.sp, color = V.ink3), modifier = modifier.padding(bottom = 10.dp))
}

/** Inline error under a field (c1 red, 12.5sp). */
@Composable
fun FieldError(error: String?) {
    if (error != null) Text(error, style = T.ui(12.5.sp, color = V.c1, lineHeight = 16.sp), modifier = Modifier.padding(start = 2.dp, top = 6.dp))
}

/**
 * True inside forms whose fields hold someone else's details (the New inspection wizard: client, agent, property).
 * Their [VInput]s opt out of Android Autofill: Compose reports every text field to the autofill service, which
 * classifies "Client email" as an email and "Inspection address" as a street address and offers the PHONE OWNER's saved
 * profile — picking that suggestion fills the whole dataset at once (client email AND the inspection address).
 */
val LocalNoAutofill = staticCompositionLocalOf { false }

/**
 * A String field's [TextFieldValue] (docs/validation-rules.md "Text selection"): focusing a field never selects its text.
 * Focus from the keyboard's Next / programmatically puts the cursor at the END (Compose's String overload leaves it at the
 * start; iOS selected everything); a tap puts it where the user tapped (the tap places it right after focus). While typing
 * the user's cursor is kept, also when a filter drops characters. Unfocused, the cursor rests at 0 so a long single-line
 * value shows its beginning. Hook [focus] up with `Modifier.onFocusChanged`.
 */
class FieldText internal constructor() {
    private var last by mutableStateOf(TextFieldValue(""))
    private var focused = false
    private var focusedAt = 0L
    /** What the field shows for [value]: the user's own selection while it matches, else [value] with the cursor at the end (focused) or start. */
    fun shown(value: String): TextFieldValue = if (last.text == value) last else TextFieldValue(value, TextRange(if (focused) value.length else 0))
    fun focus(isFocused: Boolean, value: String) {
        if (isFocused == focused) return
        focused = isFocused
        focusedAt = if (isFocused) android.os.SystemClock.uptimeMillis() else 0L
        last = TextFieldValue(value, TextRange(if (isFocused) value.length else 0))
    }
    /**
     * Applies [filter] to an edit; keeps the cursor where the user was (moved back by any characters the filter dropped).
     * QA Oct 14: a select-ALL that arrives right after focus without any typing (some keyboards / hardware Tab focus traversal
     * do this) is dropped — the cursor stays at the end. A user's own long-press / double-tap selection later is kept.
     */
    fun change(new: TextFieldValue, filter: (String) -> String): String {
        val t = filter(new.text)
        val autoSelectAll = t == new.text && t == last.text && t.isNotEmpty() && new.selection.min == 0 && new.selection.max == t.length &&
            last.selection.collapsed && android.os.SystemClock.uptimeMillis() - focusedAt < 600
        last = when {
            autoSelectAll -> TextFieldValue(t, TextRange(t.length))
            t == new.text -> new
            else -> TextFieldValue(t, TextRange((new.selection.end - (new.text.length - t.length)).coerceIn(0, t.length)))
        }
        return t
    }
}

@Composable
fun rememberFieldText(): FieldText = remember { FieldText() }

/**
 * Text input. Every value goes through a while-typing filter (default: no leading space, never two spaces in a row;
 * email/password strip spaces) — see util/Validation.kt. `error` turns the border red and shows the message below.
 */
@Composable
fun VInput(
    value: String, onChange: (String) -> Unit, modifier: Modifier = Modifier, placeholder: String = "",
    keyboard: KeyboardType = KeyboardType.Text, multiline: Boolean = false, mono: Boolean = false,
    visual: VisualTransformation = VisualTransformation.None, trailing: (@Composable () -> Unit)? = null,
    minHeight: Dp = if (multiline) 84.dp else 48.dp, textSize: Float = 15f, caps: KeyboardCapitalization = KeyboardCapitalization.None,
    error: String? = null, filter: ((String) -> String)? = null, imeAction: ImeAction = ImeAction.Default,
    /** null = on for text, off for email / password / URL; false for codes (no suggestions, no composing text). */
    autoCorrect: Boolean? = null,
    /** Whole-number field with this max: a "." and what follows are rejected, with a "Whole numbers only" hint ([com.vims.app.util.WholeNumberInput]). */
    wholeNumberMax: Double? = null,
) {
    val interaction = remember { MutableInteractionSource() }
    val noAutofill = LocalNoAutofill.current
    val focused by interaction.collectIsFocusedAsState()
    val shape = RoundedCornerShape(11.dp)
    val style: TextStyle = if (mono) T.mono(textSize.sp, FontWeight.Medium, V.ink, 0.14.em) else T.ui(textSize.sp, color = V.ink, lineHeight = if (multiline) (textSize * 1.5f).sp else androidx.compose.ui.unit.TextUnit.Unspecified)
    val noAuto = keyboard == KeyboardType.Email || keyboard == KeyboardType.Password || keyboard == KeyboardType.Uri
    val whole = if (wholeNumberMax != null) remember(wholeNumberMax) { com.vims.app.util.WholeNumberInput(wholeNumberMax, value) } else null
    val apply: (String) -> String = whole?.let { w -> { v: String -> w.apply(v) } } ?: filter ?: when (keyboard) {
        KeyboardType.Email -> Filters::email
        KeyboardType.Password -> Filters::password
        KeyboardType.Uri -> Filters::url
        else -> { v -> Filters.base(v, multiline = multiline) }
    }
    val field = rememberFieldText()
    Column(modifier.fillMaxWidth()) {
        BasicTextField(
            value = field.shown(value), onValueChange = { onChange(field.change(it, apply)) }, singleLine = !multiline, textStyle = style, interactionSource = interaction,
            keyboardOptions = KeyboardOptions(
                keyboardType = keyboard, autoCorrectEnabled = autoCorrect ?: !noAuto,
                capitalization = if (noAuto) KeyboardCapitalization.None else if (keyboard == KeyboardType.Text && caps == KeyboardCapitalization.None && !mono) KeyboardCapitalization.Sentences else caps,
                imeAction = imeAction,
            ),
            visualTransformation = visual, cursorBrush = SolidColor(V.brand),
            modifier = Modifier.fillMaxWidth().keepsKeyboard().onFocusChanged { field.focus(it.isFocused, value); whole?.reset(value) }
                .then(if (noAutofill) Modifier.semantics { contentDataType = ContentDataType.None } else Modifier),
            decorationBox = { inner ->
                Row(
                    Modifier.fillMaxWidth().heightIn(min = minHeight).clip(shape).background(V.paper)
                        .border(if (focused || error != null) (if (error != null && !focused) 1.5.dp else 2.dp) else 1.dp, if (error != null) V.c1 else if (focused) V.brand else V.line, shape)
                        .padding(start = 14.dp, end = if (trailing != null) 2.dp else 14.dp, top = if (trailing != null) 2.dp else 12.dp, bottom = if (trailing != null) 2.dp else 12.dp),
                    verticalAlignment = if (multiline) Alignment.Top else Alignment.CenterVertically,
                ) {
                    Box(Modifier.weight(1f)) {
                        if (value.isEmpty()) Text(placeholder, style = style.copy(color = V.placeholder, letterSpacing = style.letterSpacing))
                        inner()
                    }
                    trailing?.invoke()
                }
            },
        )
        if (whole?.blocked == true && error == null) Text("Whole numbers only", style = T.ui(12.5.sp, color = V.ink2, lineHeight = 16.sp), modifier = Modifier.padding(start = 2.dp, top = 6.dp))
        FieldError(error)
    }
}

@Composable
fun VField(
    label: String?, value: String, onChange: (String) -> Unit, modifier: Modifier = Modifier, placeholder: String = "",
    keyboard: KeyboardType = KeyboardType.Text, multiline: Boolean = false, mono: Boolean = false, bottom: Dp = 13.dp,
    caps: KeyboardCapitalization = KeyboardCapitalization.None, error: String? = null, filter: ((String) -> String)? = null,
    visual: VisualTransformation = VisualTransformation.None, required: Boolean = false, autoCorrect: Boolean? = null,
    imeAction: ImeAction = ImeAction.Default,
) {
    Column(modifier.padding(bottom = bottom)) {
        if (label != null) FieldLabel(label, required)
        VInput(value, onChange, placeholder = placeholder, keyboard = keyboard, multiline = multiline, mono = mono, caps = caps, error = error, filter = filter, visual = visual,
            autoCorrect = autoCorrect, imeAction = imeAction)
    }
}

@Composable
fun PasswordField(label: String, value: String, onChange: (String) -> Unit, placeholder: String = "", error: String? = null, modifier: Modifier = Modifier, required: Boolean = false) {
    var show by remember { mutableStateOf(false) }
    Column(modifier.padding(bottom = 13.dp)) {
        FieldLabel(label, required)
        VInput(
            value, onChange, placeholder = placeholder, keyboard = KeyboardType.Password, error = error,
            visual = if (show) VisualTransformation.None else PasswordVisualTransformation(),
            trailing = {
                Box(
                    Modifier.size(44.dp).clip(RoundedCornerShape(9.dp)).clickable(onClickLabel = if (show) "Hide password" else "Show password") { show = !show },
                    contentAlignment = Alignment.Center,
                ) { Icon(VIcons.eye, if (show) "Hide password" else "Show password", tint = if (show) V.brand else V.ink3, modifier = Modifier.size(20.dp)) }
            },
        )
    }
}

/** Read-only field that opens a picker (date / time). */
@Composable
fun PickerField(value: String, placeholder: String, icon: ImageVector, onClick: () -> Unit, modifier: Modifier = Modifier, minHeight: Dp = 48.dp, error: String? = null) {
    val shape = RoundedCornerShape(11.dp)
    // Opens its picker directly: drop focus first so a text field typed in before doesn't keep the keyboard up.
    val focus = LocalFocusManager.current
    Column(modifier.fillMaxWidth()) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = minHeight).clip(shape).background(V.paper).border(if (error != null) 1.5.dp else 1.dp, if (error != null) V.c1 else V.line, shape)
            .clickable(role = Role.Button) { focus.clearFocus(); onClick() }.padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(value.ifEmpty { placeholder }, style = T.ui(15.sp, color = if (value.isEmpty()) V.placeholder else V.ink), modifier = Modifier.weight(1f))
        Icon(icon, null, tint = V.ink, modifier = Modifier.size(18.dp))
    }
    FieldError(error)
    }
}

/**
 * Dropdown select styled like the prototype's `<select class="txt">` (light) or the viewer's `.qcsel` (dark). Options and
 * the chosen value wrap onto as many lines as they need (no ellipsis — quick comments are long); the menu is as wide as
 * the field (at least 260dp).
 */
@Composable
fun SelectBox(placeholder: String, options: List<String>, onSelect: (String) -> Unit, modifier: Modifier = Modifier, dark: Boolean = false, selected: String = "", clearLabel: String? = null) {
    var open by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(if (dark) 9.dp else 11.dp)
    val density = LocalDensity.current
    var anchorW by remember { mutableStateOf(0.dp) }
    val focus = LocalFocusManager.current
    Box(modifier) {
        Row(
            Modifier.fillMaxWidth().onSizeChanged { anchorW = with(density) { it.width.toDp() } }.heightIn(min = if (dark) 44.dp else 48.dp).clip(shape)
                .background(if (dark) Color.White.copy(alpha = .1f) else V.paper)
                .border(1.dp, if (dark) Color.White.copy(alpha = .18f) else V.line, shape)
                .clickable(role = Role.DropdownList) { focus.clearFocus(); open = true }.padding(horizontal = if (dark) 11.dp else 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(selected.ifEmpty { placeholder }, style = T.ui(if (dark) 13.sp else 15.sp, color = if (dark) Color.White else V.ink, lineHeight = if (dark) 17.sp else 20.sp), modifier = Modifier.weight(1f))
            Icon(VIcons.chevDown, null, tint = if (dark) Color.White else V.ink, modifier = Modifier.padding(start = 6.dp).size(16.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }, containerColor = V.paper, modifier = Modifier.width(anchorW.coerceAtLeast(260.dp))) {
            // Optional first row that clears the choice (onSelect("")), shown once something is selected.
            if (clearLabel != null && selected.isNotEmpty()) {
                DropdownMenuItem(text = { Text(clearLabel, style = T.ui(14.sp, color = V.ink3, lineHeight = 19.sp)) }, onClick = { open = false; onSelect("") },
                    modifier = Modifier.fillMaxWidth(), contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp))
            }
            options.forEach { o ->
                // DropdownMenuItem caps its content at 280dp; the full-width item + wrapping text shows every option whole.
                DropdownMenuItem(text = { Text(o, style = T.ui(14.sp, color = V.ink, lineHeight = 19.sp), softWrap = true) }, onClick = { open = false; onSelect(o) },
                    modifier = Modifier.fillMaxWidth(), contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp))
            }
        }
    }
}

/* ---------------------------------------------------------------- chips / seg / pills */

@Composable
fun VChip(text: String, on: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(22.dp)
    Box(
        modifier.minimumInteractiveComponentSize().heightIn(min = 44.dp).widthIn(min = 48.dp).clip(shape).background(if (on) V.brand else V.paper).border(1.5.dp, if (on) V.brand else V.line, shape)
            .clickable(role = Role.Checkbox, onClick = onClick).padding(horizontal = 15.dp, vertical = 9.dp),
        contentAlignment = Alignment.Center,
    ) { Text(text, style = T.ui(13.5.sp, FontWeight.Medium, if (on) Color.White else V.ink2)) }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ChipFlow(modifier: Modifier = Modifier, content: @Composable FlowRowScope.() -> Unit) {
    FlowRow(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(4.dp), content = content)
}

/** Single-select chip group: tap again to deselect (unless required). */
@Composable
fun SingleChips(options: List<String>, selected: String?, onSelect: (String?) -> Unit, required: Boolean = false, modifier: Modifier = Modifier) {
    ChipFlow(modifier) {
        options.forEach { o -> VChip(o, o == selected, { onSelect(if (o == selected && !required) null else o) }) }
    }
}

@Composable
fun MultiChips(options: List<String>, selected: Collection<String>, onToggle: (String) -> Unit, modifier: Modifier = Modifier, label: (String) -> String = { it }) {
    ChipFlow(modifier) { options.forEach { o -> VChip(label(o), o in selected, { onToggle(o) }) } }
}

/** Overall-condition segmented control (3-column grid, tap again to clear). */
@Composable
fun Seg(options: List<String>, selected: String?, onSelect: (String?) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
        options.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                row.forEach { o ->
                    val on = o == selected
                    val shape = RoundedCornerShape(10.dp)
                    Box(
                        Modifier.weight(1f).heightIn(min = 48.dp).clip(shape).background(if (on) V.brand else V.paper2)
                            .border(1.5.dp, if (on) V.brand else V.line, shape).clickable(role = Role.RadioButton) { onSelect(if (on) null else o) }
                            .padding(horizontal = 4.dp, vertical = 11.dp),
                        contentAlignment = Alignment.Center,
                    ) { Text(o, style = T.ui(12.sp, FontWeight.SemiBold, if (on) Color.White else V.ink2), textAlign = TextAlign.Center) }
                }
                repeat(3 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

enum class PillKind { Done, Prog, Queued, New }

@Composable
fun Pill(text: String, kind: PillKind, modifier: Modifier = Modifier, dot: Boolean = true, onClick: (() -> Unit)? = null) {
    val (bg, fg) = when (kind) {
        PillKind.Done -> V.c3Bg to V.doneText
        PillKind.Prog -> V.brand.copy(alpha = .13f) to V.brandDeep
        PillKind.Queued -> V.c2Bg to V.signalDeep
        PillKind.New -> V.paper3 to V.ink3
    }
    var m = modifier.clip(RoundedCornerShape(20.dp)).background(bg)
    if (onClick != null) m = m.clickable(role = Role.Button, onClick = onClick).heightIn(min = 36.dp)
    Row(m.padding(horizontal = 10.dp, vertical = 5.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
        if (dot) Box(Modifier.size(6.dp).clip(CircleShape).background(fg))
        Text(text, style = T.mono(10.5.sp, FontWeight.Bold, fg), maxLines = 1)
    }
}

/* ---------------------------------------------------------------- rows */

@Composable
fun LeadIcon(icon: ImageVector, size: Dp = 44.dp, iconSize: Dp = 22.dp, bg: Color = V.paper3, tint: Color = V.brand, radius: Dp = 11.dp) {
    Box(Modifier.size(size).clip(RoundedCornerShape(radius)).background(bg), contentAlignment = Alignment.Center) {
        Icon(icon, null, tint = tint, modifier = Modifier.size(iconSize))
    }
}

@Composable
fun LeadTime(time: String, ampm: String) {
    // Grows with large font sizes instead of clipping ("12:30").
    Column(Modifier.widthIn(min = 44.dp).heightIn(min = 44.dp).clip(RoundedCornerShape(11.dp)).background(V.paper3).padding(horizontal = 4.dp, vertical = 3.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text(time, style = T.mono(15.sp, FontWeight.ExtraBold, V.brandDeep), maxLines = 1, softWrap = false)
        Text(ampm, style = T.mono(10.sp, FontWeight.Bold, V.ink2))
    }
}

@Composable
fun LeadInitials(initials: String, size: Dp = 44.dp, circle: Boolean = false) {
    Box(
        Modifier.size(size).clip(if (circle) CircleShape else RoundedCornerShape(11.dp)).background(Brush.linearGradient(listOf(V.brandBright, V.brandDeep))),
        contentAlignment = Alignment.Center,
    ) { Text(initials, style = T.display(if (circle) 15.sp else 13.sp, FontWeight.Bold, Color.White)) }
}

@Composable
fun ListRow(
    title: String, subtitle: String? = null, onClick: (() -> Unit)? = null, lead: (@Composable () -> Unit)? = null,
    end: (@Composable RowScope.() -> Unit)? = null, chevron: Boolean = false, modifier: Modifier = Modifier, titleMaxLines: Int = 1,
    onLongClick: (() -> Unit)? = null, onLongClickLabel: String? = null, endPadding: Dp = 15.dp,
    /** Shown under the subtitle (e.g. a status pill moved out of [end] on narrow screens). */
    below: (@Composable () -> Unit)? = null,
) {
    var m = modifier.padding(bottom = 10.dp).fillMaxWidth().vCard()
    if (onClick != null && onLongClick != null) {
        m = m.combinedClickable(role = Role.Button, onLongClickLabel = onLongClickLabel, onLongClick = onLongClick, onClick = onClick)
    } else if (onClick != null) m = m.clickable(role = Role.Button, onClick = onClick)
    Row(m.padding(start = 15.dp, end = endPadding, top = 14.dp, bottom = 14.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(13.dp)) {
        lead?.invoke()
        Column(Modifier.weight(1f)) {
            Text(title, style = T.ui(15.sp, FontWeight.SemiBold, V.ink), maxLines = titleMaxLines, overflow = TextOverflow.Ellipsis)
            if (subtitle != null) Text(subtitle, style = T.ui(12.5.sp, FontWeight.Medium, V.ink2))
            if (below != null) Box(Modifier.padding(top = 6.dp)) { below() }
        }
        if (end != null) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), content = end)
        if (chevron) Icon(VIcons.chevRight, null, tint = V.chev, modifier = Modifier.size(18.dp))
    }
}

@Composable
fun BinfoRow(label: @Composable RowScope.() -> Unit, value: @Composable () -> Unit, last: Boolean = false) {
    Column {
        // Team QA Oct 22: a long value ("Square · Visa •••• 4242 (exp 08/28)") squeezed its label into a one-letter column. Both
        // keep their natural width when they fit; otherwise the label keeps up to its full width (at least 40% of the row) and
        // the value wraps in the rest, right-aligned.
        androidx.compose.ui.layout.Layout(
            contents = listOf({ Row(verticalAlignment = Alignment.CenterVertically, content = label) }, { value() }),
            modifier = Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 15.dp, vertical = 12.dp),
        ) { (l, v), c ->
            val gap = 12.dp.roundToPx()
            val avail = (c.maxWidth - gap).coerceAtLeast(0)
            val lMax = l.first().maxIntrinsicWidth(c.maxHeight); val vMax = v.firstOrNull()?.maxIntrinsicWidth(c.maxHeight) ?: 0
            val lw = if (lMax + vMax <= avail) lMax else minOf(lMax, maxOf(avail - vMax, (avail * 0.4f).toInt()))
            val lp = l.first().measure(androidx.compose.ui.unit.Constraints(maxWidth = lw.coerceAtLeast(0)))
            val vp = v.firstOrNull()?.measure(androidx.compose.ui.unit.Constraints(maxWidth = (avail - lp.width).coerceAtLeast(0)))
            val h = maxOf(lp.height, vp?.height ?: 0, c.minHeight)
            layout(c.maxWidth, h) {
                lp.place(0, (h - lp.height) / 2)
                vp?.place(c.maxWidth - vp.width, (h - vp.height) / 2)
            }
        }
        if (!last) Box(Modifier.fillMaxWidth().height(1.dp).background(V.line2))
    }
}

@Composable
fun BinfoRow(label: String, value: String, last: Boolean = false, bold: Boolean = true) {
    BinfoRow(label = { Text(label, style = T.ui(14.sp, color = V.ink)) }, value = { Text(value, style = T.ui(14.sp, if (bold) FontWeight.Bold else FontWeight.Normal, V.ink), textAlign = TextAlign.End) }, last = last)
}

/**
 * Two form fields side by side, each [Modifier.weight] 1, while each half is at least [minEach] wide (scaled with the font
 * size); stacked otherwise (team QA Oct 22: "(801) 555-0134" wrapped inside a half-width Phone field on small phones).
 */
@Composable
fun FieldPair(modifier: Modifier = Modifier, gap: Dp = 10.dp, minEach: Dp = 150.dp, first: @Composable (Modifier) -> Unit, second: @Composable (Modifier) -> Unit) {
    androidx.compose.foundation.layout.BoxWithConstraints(modifier.fillMaxWidth()) {
        val fs = LocalDensity.current.fontScale.coerceAtLeast(1f)
        if ((maxWidth - gap) / 2 >= minEach * fs) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(gap)) { first(Modifier.weight(1f)); second(Modifier.weight(1f)) }
        else Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(11.dp)) { first(Modifier); second(Modifier) }
    }
}

/**
 * A label and its controls (chips, a switch…) on one line while the label fits on ONE line beside them; otherwise the label
 * goes above the controls (team QA Oct 22: "Power is on" was squeezed into "Power / is on" on small phones / large text).
 */
@Composable
fun InlineOrStacked(modifier: Modifier = Modifier, gap: Dp = 10.dp, stackedGap: Dp = 8.dp, label: @Composable () -> Unit, controls: @Composable () -> Unit) {
    androidx.compose.ui.layout.Layout(contents = listOf(label, controls), modifier = modifier) { (l, r), c ->
        val g = gap.roundToPx()
        val rp = r.first().measure(c.copy(minWidth = 0, minHeight = 0))
        val lMax = l.first().maxIntrinsicWidth(c.maxHeight)
        if (lMax + g + rp.width <= c.maxWidth) {
            val lp = l.first().measure(c.copy(minWidth = 0, minHeight = 0, maxWidth = c.maxWidth - g - rp.width))
            val h = maxOf(lp.height, rp.height)
            layout(c.maxWidth, h) { lp.place(0, (h - lp.height) / 2); rp.place(c.maxWidth - rp.width, (h - rp.height) / 2) }
        } else {
            val lp = l.first().measure(c.copy(minWidth = 0, minHeight = 0))
            val sg = stackedGap.roundToPx()
            layout(c.maxWidth, lp.height + sg + rp.height) { lp.place(0, 0); rp.place(0, lp.height + sg) }
        }
    }
}

/** − / + stepper. Number limits (docs/validation-rules.md): − disables at [min], + at [max]. */
@Composable
fun Counter(label: String, value: Int, onMinus: () -> Unit, onPlus: () -> Unit, modifier: Modifier = Modifier, min: Int = 0, max: Int = Int.MAX_VALUE) {
    Row(
        modifier.padding(bottom = 9.dp).fillMaxWidth().vCard(12.dp).padding(horizontal = 14.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = T.ui(14.5.sp, FontWeight.Bold, V.ink), modifier = Modifier.weight(1f))
        CounterBtn("−", onMinus, "Decrease $label", enabled = value > min)
        Text("$value", style = T.mono(16.sp, FontWeight.SemiBold, V.ink), textAlign = TextAlign.Center, modifier = Modifier.width(44.dp))
        CounterBtn("+", onPlus, "Increase $label", enabled = value < max)
    }
}

@Composable
private fun CounterBtn(text: String, onClick: () -> Unit, label: String, enabled: Boolean = true) {
    val shape = RoundedCornerShape(10.dp)
    Box(
        Modifier.size(44.dp).clip(shape).background(if (enabled) V.paper2 else V.paper3).border(1.5.dp, V.line, shape)
            .clickable(enabled = enabled, onClickLabel = label, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) { Text(text, style = T.ui(22.sp, color = if (enabled) V.brand else V.ink3.copy(alpha = .45f))) }
}

@Composable
fun ProgBar(fraction: Float, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(7.dp).clip(RoundedCornerShape(6.dp)).background(V.paper3)) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(7.dp).clip(RoundedCornerShape(6.dp)).background(Brush.horizontalGradient(listOf(V.brand, V.brandBright))))
    }
}

@Composable
fun SuccessBlock(title: String, message: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 40.dp, bottom = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(96.dp).clip(CircleShape).background(V.c3Bg), contentAlignment = Alignment.Center) {
            Icon(VIcons.checkBold, null, tint = V.pass, modifier = Modifier.size(46.dp))
        }
        Spacer(Modifier.height(20.dp))
        Text(title, style = T.display(22.sp, FontWeight.Bold), textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Text(rich(message), style = T.ui(14.sp, color = V.ink3, lineHeight = 21.sp), textAlign = TextAlign.Center, modifier = Modifier.widthIn(max = 320.dp).padding(bottom = 22.dp))
        content()
    }
}

/** Dashed-border box (`.addsec` / `.codebox`). */
fun Modifier.dashedBorder(color: Color, radius: Dp, stroke: Dp = 1.dp): Modifier = this.drawBehind {
    val s = stroke.toPx()
    drawRoundRect(
        color = color, cornerRadius = CornerRadius(radius.toPx()), topLeft = Offset(s / 2, s / 2), size = Size(size.width - s, size.height - s),
        style = Stroke(width = s, pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 3.dp.toPx()))),
    )
}

/* ---------------------------------------------------------------- company identity */

/** Company initials for the fallback badge ("Vision Property Inspections" → "VP"). */
fun companyInitials(name: String): String =
    name.split(" ").filter { it.isNotBlank() && it.first().isLetterOrDigit() }.take(2).joinToString("") { it.first().uppercase() }.ifEmpty { "V" }

/** The company's uploaded logo on a white tile, or an initials badge when no logo has been uploaded. */
@Composable
fun CompanyBadge(logo: java.io.File?, name: String, size: Dp, version: Int = 0, radius: Dp = size * 0.22f, bordered: Boolean = true) {
    // File checks and decoding stay off the main thread (the Home header shows this badge right at startup).
    val img = logo?.let { com.vims.app.util.rememberThumb(it, version, 512).value }
    if (com.vims.app.util.rememberFileExists(logo, version).value) {
        Box(
            Modifier.size(size).clip(RoundedCornerShape(radius)).background(Color.White).let { if (bordered) it.border(1.dp, V.line, RoundedCornerShape(radius)) else it },
            contentAlignment = Alignment.Center,
        ) { if (img != null) androidx.compose.foundation.Image(img, "Company logo", Modifier.size(size * 0.84f), contentScale = androidx.compose.ui.layout.ContentScale.Fit) }
    } else {
        Box(Modifier.size(size).clip(RoundedCornerShape(radius)).background(Brush.linearGradient(listOf(V.brandBright, V.brandDeep))), contentAlignment = Alignment.Center) {
            Text(companyInitials(name), style = T.display((size.value * 0.36f).sp, FontWeight.Bold, Color.White))
        }
    }
}

/** The user's own profile photo in a circle, or their initials (never the company logo). */
@Composable
fun UserAvatar(photo: java.io.File?, initials: String, size: Dp, version: Int = 0) {
    val img = photo?.let { com.vims.app.util.rememberThumb(it, version, 384).value } // missing file → null (checked off the main thread)
    if (img != null) {
        androidx.compose.foundation.Image(img, "Profile photo", Modifier.size(size).clip(CircleShape), contentScale = androidx.compose.ui.layout.ContentScale.Crop)
    } else LeadInitials(initials, size, circle = true)
}

/** Confirmation dialog in the app's style (Cancel + confirm; `danger` makes the confirm button red). */
@Composable
fun ConfirmDialog(
    title: String, message: String, confirmLabel: String, onConfirm: () -> Unit, onDismiss: () -> Unit,
    danger: Boolean = false, confirmEnabled: Boolean = true, content: @Composable ColumnScope.() -> Unit = {},
) {
    androidx.compose.ui.window.Dialog(onDismissRequest = onDismiss) { TapOutsideClosesKeyboard { tapOutside ->
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(18.dp)).background(V.paper).then(tapOutside).verticalScroll(rememberScrollState()).padding(20.dp)) {
            Text(title, style = T.display(18.sp, FontWeight.Bold), modifier = Modifier.padding(bottom = 8.dp))
            Text(rich(message, V.ink), style = T.ui(13.5.sp, color = V.ink2, lineHeight = 20.sp), modifier = Modifier.padding(bottom = 14.dp))
            content()
            BtnRow(Modifier.padding(top = 2.dp)) {
                VBtn("Cancel", onDismiss, Modifier.weight(1f), BtnKind.Ghost)
                VBtn(confirmLabel, onConfirm, Modifier.weight(1f), if (danger) BtnKind.Danger else BtnKind.Primary, enabled = confirmEnabled)
            }
        }
    } }
}
