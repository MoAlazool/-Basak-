import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key: android/key.properties + android/app/upload-keystore.jks.
// Both are git-ignored and must be backed up: every update of the published
// app has to be signed with this same key.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    // UTF-8: the keystore path may contain Arabic (Properties defaults to Latin-1).
    if (file.exists()) file.reader(Charsets.UTF_8).use { load(it) }
}

android {
    namespace = "com.basak.basak_mobile"
    // Google Play: new apps and updates must target API 36 (Android 16) from
    // 31 Aug 2026. Pinned so a Flutter upgrade cannot silently change them.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (vote reminders) needs java.time on older Android.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent once published on Google Play: never change it.
        applicationId = "com.basak.basak_mobile"
        minSdk = flutter.minSdkVersion // 24 (Android 7.0)
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreProperties.isNotEmpty()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Without key.properties (e.g. a fresh clone) release builds fall
            // back to the debug key so `flutter run --release` still works;
            // such builds must never be published.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            // R8 code shrinking + unused resource removal (Flutter's defaults,
            // stated explicitly so they are never switched off by accident).
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
