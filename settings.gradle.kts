rootProject.name = "Sakipay"

// The OpenHarmony Kotlin toolchain (ohosArm64 / ohosX64 targets) lives in the
// eazytec HarmonyOS Maven repository, NOT on Maven Central. It must be listed
// FIRST in pluginManagement, otherwise Gradle resolves the plain upstream Kotlin
// plugin from Central and the `ohosArm64 { }` DSL fails with
// "Unresolved reference: ohosArm64".
//
// The Android Gradle Plugin and AndroidX come from Google's repository.
pluginManagement {
    repositories {
        maven("https://maven.eazytec-cloud.com/nexus/repository/maven-public/")
        maven("https://maven.eazytec-cloud.com/nexus/repository/maven-hw/")
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        maven("https://maven.eazytec-cloud.com/nexus/repository/maven-public/")
        maven("https://maven.eazytec-cloud.com/nexus/repository/maven-hw/")
        google()
        mavenCentral()
    }
}

// The Gradle build covers the shared module and the Android app. The iOS app
// (`iosApp/`) and the HarmonyOS app (`harmonyApp/`) are native projects in this
// same folder that consume the shared module — iOS links the `SharedLogic`
// framework, HarmonyOS links `libsakipay.so`.
// `sharedUI` (the wizard's Compose module) is intentionally excluded: UI is
// native per platform. Its sources are left on disk untouched.
include(":sharedLogic")
include(":androidApp")
