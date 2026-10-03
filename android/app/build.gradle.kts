plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
}

android {
    namespace = "com.vims.app"
    compileSdk = 37

    defaultConfig {
        // TODO: confirm final application ID with the client before store submission.
        applicationId = "com.vims.app"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
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
}

// Fail the build (instead of shipping a blank EULA screen / a dead "View" button) if a required shared/ asset is missing
// from the checkout: the EULA, icons, checklist data, the state documents, and every PDF referenced by
// stateRules.<STATE>.docs in vims-checklists.json (paths relative to shared/).
val verifySharedAssets = tasks.register("verifySharedAssets") {
    val shared = rootProject.file("../shared")
    val checklist = File(shared, "data/vims-checklists.json")
    val required = listOf(
        "legal/eula.json", "icons/icons.json", "data/vims-checklists.json",
        "legal/state/oregon-home-inspection-consumer-notice.pdf",
        "legal/state/louisiana-standards-of-practice-code-of-ethics.pdf",
    )
    inputs.files(required.map { File(shared, it) }.filter { it.isFile })
    doLast {
        val docs = if (checklist.isFile) {
            @Suppress("UNCHECKED_CAST")
            val rules = (groovy.json.JsonSlurper().parse(checklist) as Map<String, Any?>)["stateRules"] as? Map<String, Any?> ?: emptyMap()
            rules.values.filterIsInstance<Map<*, *>>().flatMap { r -> (r["docs"] as? List<*>).orEmpty().mapNotNull { (it as? Map<*, *>)?.get("file") as? String } }
        } else emptyList()
        val missing = (required + docs).distinct().map { File(shared, it) }.filter { !it.isFile || it.length() == 0L }
        if (missing.isNotEmpty()) throw GradleException("Missing shared assets (pull shared/): " + missing.joinToString())
    }
}
tasks.named("preBuild") { dependsOn(verifySharedAssets) }
