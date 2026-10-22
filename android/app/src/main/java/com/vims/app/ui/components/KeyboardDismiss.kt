package com.vims.app.ui.components

import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalFocusManager

/*
 * Team QA Oct 22 (docs/validation-rules.md): tapping anywhere outside the active field closes the keyboard, on every screen.
 * The tap is only watched (PointerEventPass.Initial, nothing consumed), so the button / chip / row under the finger still gets
 * it, and a drag past the touch slop (scrolling) never counts as a tap. Text fields register their bounds with
 * [keepsKeyboard]: tapping a field (the active one, or moving to another) leaves focus alone, so the keyboard doesn't flicker.
 */

/** Window-coordinate bounds of the text fields currently on screen (one registry per window). */
class TextFieldBounds internal constructor() {
    internal val rects = HashMap<Any, Rect>()
    internal fun hit(x: Float, y: Float): Boolean = rects.values.any { it.contains(androidx.compose.ui.geometry.Offset(x, y)) }
}

val LocalTextFieldBounds = staticCompositionLocalOf<TextFieldBounds?> { null }

/** Marks a text field (or anything that must keep the keyboard up when tapped). */
fun Modifier.keepsKeyboard(): Modifier = composed {
    val reg = LocalTextFieldBounds.current ?: return@composed this
    val key = remember { Any() }
    DisposableEffect(reg) { onDispose { reg.rects.remove(key) } }
    onGloballyPositioned { reg.rects[key] = it.boundsInWindow() }
}

/**
 * A tap (down + up within the touch slop) outside every registered text field clears focus, which closes the keyboard.
 * Used at the root of the app ([TapOutsideClosesKeyboard]) and inside dialogs that hold a field.
 */
fun Modifier.closeKeyboardOnTapOutside(): Modifier = composed {
    val focus = LocalFocusManager.current
    val reg = LocalTextFieldBounds.current
    val origin = remember { FloatArray(2) } // this layout's top-left in the window (pointer positions are local)
    onGloballyPositioned { val o = it.positionInWindow(); origin[0] = o.x; origin[1] = o.y }.pointerInput(reg) {
        awaitEachGesture {
            val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
            val up = waitForUpOrCancellation(PointerEventPass.Initial) ?: return@awaitEachGesture
            if ((up.position - down.position).getDistance() > viewConfiguration.touchSlop) return@awaitEachGesture
            if (reg == null || !reg.hit(up.position.x + origin[0], up.position.y + origin[1])) focus.clearFocus()
        }
    }
}

/** Provides a fresh field registry for one window (the activity, or a dialog) and closes the keyboard on taps outside fields. */
@Composable
fun TapOutsideClosesKeyboard(modifier: Modifier = Modifier, content: @Composable (Modifier) -> Unit) {
    val reg = remember { TextFieldBounds() }
    CompositionLocalProvider(LocalTextFieldBounds provides reg) { content(modifier.closeKeyboardOnTapOutside()) }
}
