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
import com.vims.app.ui.SplashVideo
import com.vims.app.ui.AppViewModel
import com.vims.app.ui.DebugLaunch
import com.vims.app.ui.VimsRoot
import com.vims.app.ui.theme.VimsTheme

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()
    private var debug by mutableStateOf<DebugLaunch?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        installSplashScreen() // Android 12+ SplashScreen API (light gray, no icon) → then the splash video below
        super.onCreate(savedInstanceState)
        // Blue header runs under the status bar (light icons); light navigation bar over the paper background.
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
        )
        var showVideo = false
        if (savedInstanceState == null) {
            debug = parseDebug(intent)
            showVideo = debug == null || intent.getBooleanExtra("video", false)
            // Free-look splash: a restored session counts as a sign-in during the trial.
            if (debug == null && vm.session.value != null) vm.maybeShowSplash()
        }
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
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        parseDebug(intent)?.let { debug = it }
    }

    /** Debug builds only: `adb shell am start -n com.vims.app/.MainActivity --es screen summary [--es insp ID] [--es section Roof] [--es depth high] [--ez splash true]`. */
    private fun parseDebug(i: Intent?): DebugLaunch? {
        if (!BuildConfig.DEBUG || i == null) return null
        val screen = i.getStringExtra("screen") ?: return null
        return DebugLaunch(
            screen = screen, insp = i.getStringExtra("insp"), section = i.getStringExtra("section"), cat = i.getStringExtra("cat"),
            photo = i.getStringExtra("photo"), depth = i.getStringExtra("depth"), splash = i.getBooleanExtra("splash", false),
            step = i.getIntExtra("step", 1), coverStep = i.getIntExtra("coverStep", 1),
        )
    }
}
