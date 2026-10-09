import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// The Android app is a Kotlin Multiplatform module with a single Android target,
// matching the OpenHarmony reference project's app module. Using the KMP plugin
// (rather than a separate Kotlin-Android plugin) keeps the whole build on the one
// OpenHarmony Kotlin toolchain version.
plugins {
    alias(libs.plugins.kotlinMultiplatform)
    alias(libs.plugins.androidApplication)
}

kotlin {
    androidTarget {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_11)
        }
    }
}

android {
    namespace = "com.xiatstudio.sakipay"
    compileSdk = libs.versions.android.compileSdk.get().toInt()

    defaultConfig {
        applicationId = "com.xiatstudio.sakipay"
        minSdk = libs.versions.android.minSdk.get().toInt()
        targetSdk = libs.versions.android.targetSdk.get().toInt()
        versionCode = 1
        versionName = "1.0"
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
}

dependencies {
    // All behaviour comes from the shared module; the UI is Android-only.
    implementation(project(":sharedLogic"))
}
