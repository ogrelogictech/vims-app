package com.vims.app

import android.app.Application
import android.os.StrictMode
import android.os.SystemClock
import android.util.Log
import com.vims.app.data.ChecklistConfig
import com.vims.app.data.ChecklistEngine
import com.vims.app.data.ChecklistLoader
import com.vims.app.data.JsonMigration
import com.vims.app.data.RoomRepository
import com.vims.app.data.VimsRepository
import com.vims.app.data.db.VimsDatabase
import com.vims.app.demo.DemoSeed
import com.vims.app.services.AuthService
import com.vims.app.services.LocalAuthService
import com.vims.app.services.LocalSubscriptionService
import com.vims.app.services.LocalSyncService
import com.vims.app.services.SubscriptionService
import com.vims.app.services.SyncService
import com.vims.app.ui.theme.VIcons
import com.vims.app.ui.theme.VimsFonts
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Simple manual DI container (no framework needed at this size). */
class AppContainer(private val app: Application) {
    val config: ChecklistConfig = ChecklistLoader.load(app)
    /** EULA loaded once at app start, off the main thread, before any screen is shown (survives into every screen / after process death via Application). */
    val eulaResult: Result<com.vims.app.data.Eula> = com.vims.app.data.Eula.load(app)
    /** VIMS default inspection agreement (shared/legal/inspection-agreement.json), loaded here off the main thread like the EULA. */
    val agreementResult: Result<com.vims.app.data.InspectionAgreement> = com.vims.app.data.InspectionAgreement.load(app)
    val db: VimsDatabase = VimsDatabase.open(app)
    private val roomRepo = RoomRepository(app.filesDir, db.dao())
    val repo: VimsRepository = roomRepo
    val auth: AuthService = LocalAuthService(db.dao(), config)
    val subscriptions: SubscriptionService = LocalSubscriptionService()
    val sync: SyncService = LocalSyncService(repo)

    fun engine(): ChecklistEngine = ChecklistEngine(config, repo.edits.value)

    /** Startup: one-time JSON → Room import, demo account, then restore the last signed-in user (their data only). */
    suspend fun start() {
        JsonMigration.runIfNeeded(roomRepo.root.parentFile!!, db.dao(), config)
        // DEMO DATA: remove this line (and demo/DemoSeed.kt) to ship without the demo account.
        DemoSeed.ensureDemoAccount(db.dao(), repo, ChecklistEngine(config, com.vims.app.data.ChecklistEdits()))
        DemoSeed.ensureDemoLogo(db.dao(), app.filesDir, app.resources)
        roomRepo.loadPlatform(com.vims.app.data.PlatformSettings(
            feedbackEmail = config.support.feedbackEmail, reportBccOn = config.support.reportBcc.on, reportBccEmail = config.support.reportBcc.email,
        ))
        roomRepo.restore()
    }
}

class VimsApplication : Application() {
    /** Application-lifetime scope for startup work; never runs on the main thread. */
    private val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val _ready = MutableStateFlow(false)
    /**
     * True once [container] is built and [AppContainer.start] has finished (Room open, one-time JSON → Room migration,
     * demo account, EULA + checklist config + icons loaded, last session restored). Nothing may read [container] before
     * this — `MainActivity` keeps the system splash on screen and only creates the UI / `AppViewModel` once it is true.
     */
    val ready: StateFlow<Boolean> = _ready.asStateFlow()

    @Volatile private var _container: AppContainer? = null
    val container: AppContainer
        get() = checkNotNull(_container) { "AppContainer read before startup finished — wait for VimsApplication.ready" }

    override fun onCreate() {
        super.onCreate()
        if (BuildConfig.DEBUG) {
            // Debug only: log any disk read/write that lands on the main thread (startup work must stay off it).
            StrictMode.setThreadPolicy(StrictMode.ThreadPolicy.Builder().detectDiskReads().detectDiskWrites().penaltyLog().build())
        }
        val t0 = SystemClock.uptimeMillis()
        // Startup I/O (DB open, migration, assets) runs in the background so a slow device never ANRs on first launch.
        // An exception here still crashes the app, exactly as the old synchronous start did.
        appScope.launch {
            VimsFonts.init(assets)
            VIcons.init(assets)
            val c = AppContainer(this@VimsApplication)
            c.start()
            _container = c
            _ready.value = true
            if (BuildConfig.DEBUG) Log.i("VIMS-Startup", "ready in ${SystemClock.uptimeMillis() - t0} ms (background)")
        }
    }
}
