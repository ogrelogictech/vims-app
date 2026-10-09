package com.vims.app

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.lifecycleScope
import com.vims.app.ui.SplashVideo
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.DebugLaunch
import com.vims.app.ui.VimsRoot
import com.vims.app.ui.theme.VimsTheme
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()
    private var debug by mutableStateOf<DebugLaunch?>(null)

    /** Set (main thread) right after the UI is composed; the system splash stays up until then. */
    private var uiShown = false

    override fun onCreate(savedInstanceState: Bundle?) {
        // Android 12+ SplashScreen API (light gray, no icon) → then the splash video below. It stays on screen while
        // VimsApplication finishes its background startup (Room, migration, EULA, checklist config, session restore).
        installSplashScreen().setKeepOnScreenCondition { !uiShown }
        super.onCreate(savedInstanceState)
        // Blue header runs under the status bar (light icons); light navigation bar over the paper background.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
        )
        val cold = savedInstanceState == null
        var showVideo = false
        if (cold) {
            debug = parseDebug(intent)
            showVideo = debug == null || intent.getBooleanExtra("video", false)
        }
        val launchedWithDebug = debug != null
        // The ViewModel (and everything that reads the AppContainer) is only created once startup is done; this also
        // covers process-death restore, where the activity is recreated before the new process has finished starting.
        val app = application as VimsApplication
        if (app.ready.value) showUi(cold, launchedWithDebug, showVideo)
        else lifecycleScope.launch { app.ready.first { it }; showUi(cold, launchedWithDebug, showVideo) }
    }

    private fun showUi(cold: Boolean, launchedWithDebug: Boolean, showVideo: Boolean) {
        // Free-look splash: a restored session counts as a sign-in during the trial.
        if (cold && !launchedWithDebug && vm.session.value != null) vm.maybeShowSplash()
        setContent {
            VimsTheme {
                var video by rememberSaveable { mutableStateOf(showVideo) }
                Box(Modifier.fillMaxSize()) {
                    VimsRoot(vm, debug)
                    // Cold launch only: the splash video plays over Sign in / Home, which is already composed underneath.
                    if (video) SplashVideo { video = false }
                }
            }
        }
        uiShown = true
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        parseDebug(intent)?.let { debug = it }
    }

    /** Debug builds only: `adb shell am start -n com.vims.app/.MainActivity --es screen summary [--es insp ID] [--es section Roof] [--es depth high] [--ez splash true]`;
     *  cover QA: `--es cover 'Blue|Holidays|4th of July|Shaded' --es inspType Texas --ez generate true`. */
    private fun parseDebug(i: Intent?): DebugLaunch? {
        if (!BuildConfig.DEBUG || i == null) return null
        val screen = i.getStringExtra("screen") ?: return null
        return DebugLaunch(
            screen = screen, insp = i.getStringExtra("insp"), section = i.getStringExtra("section"), cat = i.getStringExtra("cat"),
            photo = i.getStringExtra("photo"), depth = i.getStringExtra("depth"), splash = i.getBooleanExtra("splash", false),
            step = i.getIntExtra("step", 1), coverStep = i.getIntExtra("coverStep", 1), eulaVersion = i.getStringExtra("eulaVersion"),
            state = i.getStringExtra("state"), cover = i.getStringExtra("cover"), inspType = i.getStringExtra("inspType"),
            generate = i.getBooleanExtra("generate", false),
        )
    }
}
