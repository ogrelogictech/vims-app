package com.vims.app

import android.app.Application
import com.vims.app.data.ChecklistConfig
import com.vims.app.data.ChecklistEngine
import com.vims.app.data.ChecklistLoader
import com.vims.app.data.FileRepository
import com.vims.app.data.VimsRepository
import com.vims.app.demo.DemoSeed
import com.vims.app.services.AuthService
import com.vims.app.services.LocalAuthService
import com.vims.app.services.LocalSubscriptionService
import com.vims.app.services.LocalSyncService
import com.vims.app.services.SubscriptionService
import com.vims.app.services.SyncService
import com.vims.app.ui.theme.VimsFonts
import java.time.LocalDate

/** Simple manual DI container (no framework needed at this size). */
class AppContainer(app: Application) {
    val config: ChecklistConfig = ChecklistLoader.load(app)
    val repo: VimsRepository = FileRepository(app.filesDir)
    val auth: AuthService = LocalAuthService(repo)
    val subscriptions: SubscriptionService = LocalSubscriptionService()
    val sync: SyncService = LocalSyncService(repo)

    fun engine(): ChecklistEngine = ChecklistEngine(config, repo.edits.value)
}

class VimsApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        VimsFonts.init(assets)
        container = AppContainer(this)
        val repo = container.repo
        val cfg = container.config
        // Company account defaults come from the shared JSON (plans, per-inspector rate, trial length, feedback email).
        if (repo.account.value.plans.isEmpty()) {
            repo.updateAccount {
                it.copy(
                    plans = cfg.subscription.plans,
                    extraInspectorMonthly = cfg.subscription.extraInspectorMonthly,
                    planId = cfg.subscription.plans.firstOrNull()?.id ?: "app",
                    trialDays = cfg.subscription.trialDays,
                    trialStartEpochDay = LocalDate.now().toEpochDay(),
                    feedbackEmail = cfg.support.feedbackEmail,
                )
            }
        }
        // DEMO DATA: remove this line (and demo/DemoSeed.kt) to ship without the sample inspections.
        DemoSeed.seedIfNeeded(repo, container.engine())
    }
}
