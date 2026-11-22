// This is the PROJECT-LEVEL build.gradle.kts
// Location: android/build.gradle.kts

plugins {
    // START: Fixes for your error
    // Use 'plugins' (plural), not 'plugin'
    //id("com.android.application") version "8.11.1" apply false
    //id("com.android.library") version "8.11.1" apply false
    //id("org.jetbrains.kotlin.android") version "1.8.22" apply false
    
    // Google Services for Firebase
    id("com.google.gms.google-services") version "4.4.1" apply false
    // END: Fixes
    //dependency for the Performance Monitoring Gradle plugin
    id("com.google.firebase.firebase-perf") version "2.0.2" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)

    // Force all plugins (like background_sms) to compile against SDK 35
    // so they have android:attr/lStar and other newer attributes
    afterEvaluate {
        if (project.hasProperty("android")) {
            val android = project.extensions.getByName("android")
            if (android is com.android.build.gradle.BaseExtension) {
                if (android.compileSdkVersion == null || (android.compileSdkVersion?.replace("android-", "")?.toIntOrNull() ?: 0) < 35) {
                    android.compileSdkVersion(35)
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}