import java.io.File
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.androidLibrary)
}

kotlin {
    // Android is consumed by :androidApp in this build.
    androidTarget {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_11)
        }
    }

    // JVM target exists so the shared common tests can run locally with
    // `./gradlew :sharedLogic:jvmTest` without an emulator.
    jvm()

    listOf(
        iosArm64(),
        iosSimulatorArm64(),
    ).forEach { iosTarget ->
        iosTarget.binaries.framework {
            baseName = "SharedLogic"
            isStatic = true
        }
    }

    // OpenHarmony targets (provided by the eazytec Kotlin toolchain). They produce
    // a C-ABI shared library that the ArkTS app reaches through a NAPI bridge.
    ohosArm64 {
        binaries {
            sharedLib { baseName = "sakipay" }
            staticLib { baseName = "sakipay" }
        }
    }
    ohosX64 {
        binaries {
            sharedLib { baseName = "sakipay" }
            staticLib { baseName = "sakipay" }
        }
    }

    @Suppress("UNUSED_VARIABLE")
    sourceSets {
        val commonMain by getting

        val commonTest by getting {
            dependencies {
                // Resolve the test library through the Kotlin plugin so its
                // version always matches the toolchain (the vendor Maven repo
                // may not publish suffixed kotlin-test artifacts).
                implementation(kotlin("test"))
            }
        }

        // The default hierarchy template is disabled (see gradle.properties), so
        // the intermediate source sets are wired by hand.
        val androidMain by getting

        val iosMain by creating {
            dependsOn(commonMain)
        }
        val iosArm64Main by getting { dependsOn(iosMain) }
        val iosSimulatorArm64Main by getting { dependsOn(iosMain) }

        // Shared between ohosArm64 and ohosX64 — holds the @CName exports.
        val ohosMain by creating {
            dependsOn(commonMain)
        }
        val ohosArm64Main by getting { dependsOn(ohosMain) }
        val ohosX64Main by getting { dependsOn(ohosMain) }
    }
}

android {
    namespace = "com.xiatstudio.sakipay.shared"
    compileSdk = libs.versions.android.compileSdk.get().toInt()

    defaultConfig {
        minSdk = libs.versions.android.minSdk.get().toInt()
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

// --- OpenHarmony artefact publishing -----------------------------------------
// Copies the built <libsakipay.so> + <libsakipay_api.h> into the HarmonyOS app
// (harmonyApp/, whose DevEco module is named `main`) so its NAPI bridge can link
// them.
//
//   ./gradlew :sharedLogic:publishDebugBinariesToHarmonyApp
//   ./gradlew :sharedLogic:publishReleaseBinariesToHarmonyApp
//
// x86_64 (ohosX64) variants target the HarmonyOS emulator:
//
//   ./gradlew :sharedLogic:publishDebugBinariesToHarmonyAppX64
val harmonyModuleDir = file("$rootDir/harmonyApp/main")

arrayOf("debug", "release").forEach { type ->
    val capitalized = type.replaceFirstChar { it.uppercase() }

    tasks.register<Copy>("publish${capitalized}BinariesToHarmonyApp") {
        group = "harmony"
        description = "Publish ohosArm64 libsakipay.so to the HarmonyOS app"
        dependsOn("link${capitalized}SharedOhosArm64")
        into(harmonyModuleDir)
        from("build/bin/ohosArm64/${type}Shared/libsakipay_api.h") {
            into("src/main/cpp/include/")
        }
        from("build/bin/ohosArm64/${type}Shared/libsakipay.so") {
            into("libs/arm64-v8a/")
        }
        doFirst {
            val dir = file("build/bin/ohosArm64/${type}Shared")
            if (!dir.exists()) {
                throw GradleException("Artefact directory not found: ${dir.absolutePath}")
            }
        }
    }

    tasks.register<Copy>("publish${capitalized}BinariesToHarmonyAppX64") {
        group = "harmony"
        description = "Publish ohosX64 libsakipay.so to the HarmonyOS app (emulator)"
        dependsOn("link${capitalized}SharedOhosX64")
        into(harmonyModuleDir)
        from("build/bin/ohosX64/${type}Shared/libsakipay_api.h") {
            into("src/main/cpp/include/")
        }
        from("build/bin/ohosX64/${type}Shared/libsakipay.so") {
            into("libs/x86_64/")
        }
        doFirst {
            val dir = file("build/bin/ohosX64/${type}Shared")
            if (!dir.exists()) {
                throw GradleException("Artefact directory not found: ${dir.absolutePath}")
            }
        }
    }
}

// --- IDE import workaround ---------------------------------------------------
// The IDE's ohosMain dependency resolution reads
// build/kotlin/commonizedNativeDistributionLocation.txt during the import phase,
// before any task runs. Create it eagerly so `prepareKotlinIdeaImport` does not
// fail with a FileNotFoundException.
val commonizedDir = file("build/kotlin")
commonizedDir.mkdirs()
File(commonizedDir, "commonizedNativeDistributionLocation.txt").writeText(commonizedDir.absolutePath)

// The commonizer only knows upstream Konan targets, not ohos_x64/ohos_arm64, so
// its tasks may be registered late. Disable them once the project is evaluated.
afterEvaluate {
    listOf("commonizeNativeDistribution", "commonizeCInterop").forEach { taskName ->
        tasks.findByName(taskName)?.let { it.enabled = false }
    }
}
