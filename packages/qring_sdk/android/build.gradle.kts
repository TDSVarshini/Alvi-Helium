group = "ca.alvi.qring.qring_sdk"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

// The vendor AAR is served from a file-based Maven repo inside this plugin:
// AGP refuses direct local .aar dependencies in library modules.
val qringRepo = file("libs-maven")

allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri(qringRepo) }
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "ca.alvi.qring.qring_sdk"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 26
        consumerProguardFiles("consumer-rules.pro")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("com.oudmon:qring-sdk:1.0.0.60@aar")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.annotation:annotation:1.8.2")
}
