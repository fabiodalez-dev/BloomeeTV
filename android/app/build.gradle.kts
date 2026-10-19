plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")


android {
    testBuildType = "debug"
    namespace = "ls.bloomee.musicplayer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        applicationId = "it.fabiodalez.bloomeetv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        manifestPlaceholders["baseVersionCode"] = flutter.versionCode
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = true
        }
    }
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            println("   ✅ key.properties found - configuring release signing")
            val keystoreProperties = Properties()
            keystoreProperties.load(FileInputStream(keystorePropertiesFile))

            val keystorePath = keystoreProperties["bloomee.jks"] as String?
            val keyAliasValue = keystoreProperties["keyAlias"] as String?

            println("   Keystore file path: $keystorePath")
            println("   Key alias: $keyAliasValue")

            if (keystorePath != null) {
                val keystoreFile = file(keystorePath)
                println("   Keystore file exists: ${keystoreFile.exists()}")
                println("   Keystore file path: ${keystoreFile.absolutePath}")
            }

            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = rootProject.file("bloomee.jks")
                storePassword = keystoreProperties["storePassword"] as String?
                println("   ✅ Release signing config created successfully")
            }
        } else {
            println("   ❌ key.properties not found - using debug signing")
        }
    }

    buildTypes {
        debug {
            // Optional local device testing over an existing signed install.
            if (providers.gradleProperty("signDebugWithRelease").orNull == "true" && keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
        release {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
                println("   📦 Release build: Using release signing config")
            }
            else{
                signingConfig = signingConfigs.getByName("debug")
                println("   📦 Release build: Using debug signing config (no keystore)")
            }
        }
    }

    // To reduce the size of the APK, since from AGP 8.0.0 the default value of useLegacyPackaging is false.
     packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}

// Cast Connect receives controls and publishes the existing media session.
dependencies {
    testImplementation("junit:junit:4.13.2")
    // Keep instrumentation aligned with Flutter integration_test's debug runtime.
    debugImplementation("androidx.test.ext:junit:1.2.1")
    debugImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    implementation("com.google.android.gms:play-services-cast-tv:21.1.1")
    implementation("com.google.android.gms:play-services-cast:22.3.1")
}
