import java.security.KeyFactory
import java.security.spec.X509EncodedKeySpec
import java.util.Base64

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
}

// Store builds: ./gradlew bundleRelease -PvimsStore=true (shared subscription.store.storeAppID). Every other build keeps
// subscription.store.testAppID, so installs over the client's test app keep working. `namespace` never changes.
val vimsStore = providers.gradleProperty("vimsStore").map { it == "true" }.getOrElse(false)
// Optional: Play Console > Monetization setup > Google Play Billing > Licensing public key (Base64). Absent = signature check skipped.
val vimsPlayLicenseKey = providers.gradleProperty("vimsPlayLicenseKey").map { it.trim() }.getOrElse("")
if (vimsPlayLicenseKey.isNotEmpty()) {
    // A key that can't be read would reject (and so refund) every purchase: fail the build, never the customer.
    try {
        KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(Base64.getDecoder().decode(vimsPlayLicenseKey)))
    } catch (e: Exception) {
        throw GradleException("vimsPlayLicenseKey is not a Base64 RSA public key: ${e.message}")
    }
}

android {
    namespace = "com.vims.app"
    compileSdk = 37

    defaultConfig {
        applicationId = if (vimsStore) "com.vimsinspect.app" else "com.vims.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 33
        versionName = "0.32.0"
        buildConfigField("String", "PLAY_LICENSE_KEY", "\"$vimsPlayLicenseKey\"")
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    // Checklist data + fonts come from the repo's shared/ folder (single source of truth for iOS and Android).
    sourceSets {
        getByName("main") {
            assets.directories.add("../../shared")
        }
    }

    testOptions {
        // Pure Kotlin access and billing rules; android.util.Log is a no-op in unit tests.
        unitTests.isReturnDefaultValues = true
    }
}

ksp {
    arg("room.schemaLocation", "$projectDir/schemas")
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.compose.ui.tooling.preview)
    debugImplementation(libs.compose.ui.tooling)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.camerax.core)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    // Local database (Room / SQLite) — on-device store; MySQL is the Phase 2 server database.
    implementation(libs.room.runtime)
    implementation(libs.room.ktx)
    ksp(libs.room.compiler)
    // Launch splash video + Android 12+ SplashScreen API
    implementation(libs.media3.exoplayer)
    implementation(libs.media3.ui)
    implementation(libs.core.splashscreen)
    // Google Play subscriptions and report credits (shared subscription.store)
    implementation(libs.billing.ktx)
    testImplementation(libs.junit)
}

// Fail the build (instead of shipping a blank EULA screen / a dead "View" button / a cover without its artwork) if a
// required shared/ asset is missing from the checkout: the EULA, icons, checklist data, the state documents, every PDF
// referenced by stateRules.<STATE>.docs and every cover artwork in covers.themeArt (v1.6) in vims-checklists.json
// (paths relative to shared/).
val verifySharedAssets = tasks.register("verifySharedAssets") {
    val shared = rootProject.file("../shared")
    val checklist = File(shared, "data/vims-checklists.json")
    val required = listOf(
        "legal/eula.json", "legal/inspection-agreement.json", "icons/icons.json", "data/vims-checklists.json",
        "legal/state/oregon-home-inspection-consumer-notice.pdf",
        "legal/state/louisiana-standards-of-practice-code-of-ethics.pdf",
        "media/vims-splash.mp4", "media/vims-splash-wide.mp4",
    )
    inputs.files(required.map { File(shared, it) }.filter { it.isFile })
    doLast {
        val docs = if (checklist.isFile) {
            @Suppress("UNCHECKED_CAST")
            val data = groovy.json.JsonSlurper().parse(checklist) as Map<String, Any?>
            val rules = data["stateRules"] as? Map<String, Any?> ?: emptyMap()
            val art = ((data["covers"] as? Map<*, *>)?.get("themeArt") as? Map<*, *>).orEmpty().values.mapNotNull { (it as? Map<*, *>)?.get("file") as? String }
            rules.values.filterIsInstance<Map<*, *>>().flatMap { r -> (r["docs"] as? List<*>).orEmpty().mapNotNull { (it as? Map<*, *>)?.get("file") as? String } } + art
        } else emptyList()
        val missing = (required + docs).distinct().map { File(shared, it) }.filter { !it.isFile || it.length() == 0L }
        if (missing.isNotEmpty()) throw GradleException("Missing shared assets (pull shared/): " + missing.joinToString())
    }
}
tasks.named("preBuild") { dependsOn(verifySharedAssets) }
