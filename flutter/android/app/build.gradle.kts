plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.flammedemon.ts6_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.flammedemon.ts6_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// Builds the Rust bridge (../tslib, crate tslib-frb) with cargo-ndk into jniLibs.
val rustProjectDir = rootProject.projectDir.resolve("../../../tslib").canonicalFile
val buildRustLibs by tasks.registering(Exec::class) {
    val sdkDir = (System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
        ?: System.getProperty("user.home") + "/Android/Sdk")
    val ndkDir = System.getenv("ANDROID_NDK_HOME")
        ?: file("$sdkDir/ndk").listFiles()?.filter { it.isDirectory }?.maxByOrNull { it.name }?.absolutePath
    workingDir = rustProjectDir
    environment("ANDROID_NDK_HOME", ndkDir ?: "")
    environment("CMAKE_POLICY_VERSION_MINIMUM", "3.5")
    environment("PATH", System.getenv("PATH") + ":" + System.getProperty("user.home") + "/.cargo/bin")
    commandLine(
        "cargo", "ndk", "-t", "arm64-v8a", "-t", "x86_64",
        "-o", projectDir.resolve("src/main/jniLibs").absolutePath,
        "build", "--release", "-p", "tslib-frb", "--features", "vendored-openssl",
    )
}
// libtslib_frb.so links libc++_shared.so (oboe/cpal); ship it from the NDK.
buildRustLibs.configure {
    doLast {
        val sdkDir = (System.getenv("ANDROID_HOME") ?: System.getenv("ANDROID_SDK_ROOT")
            ?: System.getProperty("user.home") + "/Android/Sdk")
        val ndkDir = System.getenv("ANDROID_NDK_HOME")
            ?: file("$sdkDir/ndk").listFiles()!!.filter { it.isDirectory }.maxByOrNull { it.name }!!.absolutePath
        val sysroot = "$ndkDir/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/lib"
        val strip = file("$ndkDir/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip")
        mapOf("arm64-v8a" to "aarch64-linux-android", "x86_64" to "x86_64-linux-android").forEach { (abi, triple) ->
            // Keep an unstripped copy for ndk-stack, then strip the one that ships.
            val so = projectDir.resolve("src/main/jniLibs/$abi/libtslib_frb.so")
            if (so.exists()) {
                val sym = rustProjectDir.resolve("symbols/frb/$abi").also { it.mkdirs() }
                so.copyTo(sym.resolve("libtslib_frb.so"), overwrite = true)
                ProcessBuilder(strip.absolutePath, "--strip-unneeded", so.absolutePath).inheritIO().start().waitFor()
            }
            file("$sysroot/$triple/libc++_shared.so")
                .copyTo(projectDir.resolve("src/main/jniLibs/$abi/libc++_shared.so"), overwrite = true)
        }
    }
}
tasks.matching { it.name == "preBuild" }.configureEach { dependsOn(buildRustLibs) }

