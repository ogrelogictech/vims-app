package com.vims.app

import android.app.Application
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking

/** Simple manual DI container (no framework needed at this size). */
class AppContainer(private val app: Application) {
    val config: ChecklistConfig = ChecklistLoader.load(app)
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
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        VimsFonts.init(assets)
        VIcons.init(assets)
        container = AppContainer(this)
        // Small, one-off local work; the system splash screen covers it.
        runBlocking(Dispatchers.IO) { container.start() }
    }
}
