import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releasePropertiesFile = rootProject.file("../../android/key.properties")
val releaseStoreFile = rootProject.file("../../android/bloomee.jks")
val releaseProperties = Properties()
if (releasePropertiesFile.exists()) {
    releasePropertiesFile.inputStream().use { releaseProperties.load(it) }
}

android {
    namespace = "it.fabiodalez.bloomee_remote"
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
        applicationId = "it.fabiodalez.bloomee_remote"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releasePropertiesFile.exists() && releaseStoreFile.exists()) {
            create("release") {
                keyAlias = releaseProperties["keyAlias"] as String
                keyPassword = releaseProperties["keyPassword"] as String
                storePassword = releaseProperties["storePassword"] as String
                storeFile = releaseStoreFile
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
