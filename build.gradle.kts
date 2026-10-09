plugins {
    // Loaded once here and applied in the subprojects so each (custom) plugin is
    // not resolved multiple times in different classloaders.
    alias(libs.plugins.kotlinMultiplatform) apply false
    alias(libs.plugins.androidApplication) apply false
    alias(libs.plugins.androidLibrary) apply false
}
