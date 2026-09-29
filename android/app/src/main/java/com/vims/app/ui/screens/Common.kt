package com.vims.app.ui.screens

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.navigation.NavHostController
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.back
import com.vims.app.ui.components.HdrAction
import com.vims.app.ui.components.NetState
import com.vims.app.ui.goHome
import com.vims.app.ui.theme.VIcons
import com.vims.app.util.Fmt
import java.time.LocalDate
import java.time.LocalTime

@Composable
fun net(vm: AppViewModel): NetState = vm.net.collectAsState().value

@Composable
fun companyName(vm: AppViewModel): String = vm.company.collectAsState().value.name.ifBlank { "VIMS" }

fun backAction(nav: NavHostController) = HdrAction(VIcons.back, "Back") { nav.back() }
fun homeAction(nav: NavHostController) = HdrAction(VIcons.home, "Home") { nav.goHome() }

fun pickDate(ctx: Context, iso: String, onPick: (String) -> Unit) {
    val d = Fmt.parseDate(iso) ?: LocalDate.now()
    DatePickerDialog(ctx, { _, y, m, day -> onPick(LocalDate.of(y, m + 1, day).toString()) }, d.year, d.monthValue - 1, d.dayOfMonth).show()
}

fun pickTime(ctx: Context, hhmm: String, onPick: (String) -> Unit) {
    val t = Fmt.parseTime(hhmm) ?: LocalTime.of(9, 0)
    TimePickerDialog(ctx, { _, h, m -> onPick(String.format(java.util.Locale.US, "%02d:%02d", h, m)) }, t.hour, t.minute, false).show()
}

/** The company logo file for the signed-in company (null until one is uploaded). */
@Composable
fun companyLogo(vm: AppViewModel): java.io.File? {
    val c = vm.company.collectAsState().value
    val ctx = androidx.compose.ui.platform.LocalContext.current
    return c.logoFile?.let { java.io.File(ctx.filesDir, it) }
}

/** Company logo (or initials) badge, refreshed when a new logo is uploaded. */
@Composable
fun CompanyMark(vm: AppViewModel, size: androidx.compose.ui.unit.Dp, bordered: Boolean = true) {
    val version = vm.logoVersion.collectAsState().value
    com.vims.app.ui.components.CompanyBadge(companyLogo(vm), companyName(vm), size, version, bordered = bordered)
}
