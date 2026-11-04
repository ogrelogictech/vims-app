package com.vims.app.services

import android.app.Application
import android.content.Intent
import com.vims.app.AppContainer
import com.vims.app.data.AndroidStoreDef

/** Release builds: Google Play only. The fake store and every debug hook live in src/debug and aren't compiled into this build. */
object BillingFlavor {
    fun backend(app: Application, ids: AndroidStoreDef): StoreBackend = PlayBillingBackend(app, ids)
    @Suppress("UNUSED_PARAMETER") fun handleIntent(app: Application, intent: Intent?, container: AppContainer) {}
}
