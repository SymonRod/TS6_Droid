plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "dev.tsdroid"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.flammedemon.ts6droid"
        minSdk = 29
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            storeFile = file("${rootDir}/release.keystore")
            storePassword = "ts6droid"
            keyAlias = "ts6droid"
            keyPassword = "ts6droid"
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/java", "src/main/kotlin")
        }
    }
}

// Build the Rust JNI library automatically before Android packages native libraries.
val rustProjectDir = rootDir.resolve("../tslib")
val androidSdkDir = providers.environmentVariable("ANDROID_HOME")
    .orElse(providers.environmentVariable("ANDROID_SDK_ROOT"))
    .map(::file)
    .orElse(file("${System.getProperty("user.home")}/Android/Sdk"))
val configuredNdkDir = providers.environmentVariable("ANDROID_NDK_HOME")
    .orElse(providers.environmentVariable("ANDROID_NDK"))
    .map(::file)
val installedNdkDir = providers.provider {
    androidSdkDir.get().resolve("ndk").listFiles()
        ?.filter { it.isDirectory }
        ?.maxByOrNull { it.name }
}
val cargoExecutable = providers.provider {
    val cargoHome = System.getenv("CARGO_HOME")?.let(::file)
        ?: file("${System.getProperty("user.home")}/.cargo")
    cargoHome.resolve("bin/cargo").takeIf { it.isFile }?.absolutePath ?: "cargo"
}

val buildRustLibs by tasks.registering(Exec::class) {
    val ndkDir = configuredNdkDir.orElse(installedNdkDir)
    val outputDir = projectDir.resolve("src/main/jniLibs")

    workingDir = rustProjectDir
    inputs.dir(rustProjectDir.resolve("crates"))
    inputs.file(rustProjectDir.resolve("Cargo.toml"))
    outputs.dir(outputDir)

    doFirst {
        require(rustProjectDir.isDirectory) {
            "Missing tslib repository at ${rustProjectDir.absolutePath}"
        }
        require(ndkDir.isPresent && ndkDir.get().isDirectory) {
            "Android NDK not found. Install it with SDK Manager or set ANDROID_NDK_HOME."
        }
        environment("ANDROID_NDK_HOME", ndkDir.get().absolutePath)
        environment("ANDROID_NDK", ndkDir.get().absolutePath)
    }

    environment("CMAKE_POLICY_VERSION_MINIMUM", "3.5")
    commandLine(
        cargoExecutable.get(), "ndk",
        "-t", "arm64-v8a",
        "-t", "x86_64",
        "-o", outputDir.absolutePath,
        "build", "--release", "-p", "tslib-jni",
        "--features", "vendored-openssl",
        "-j10"
    )

    doLast {
        // The release profile keeps symbols so that native crashes can be
        // symbolized (see tslib/Cargo.toml). Stash an unstripped copy for
        // ndk-stack, and strip the libraries that get packaged into the APK.
        val symbolsDir = rustProjectDir.resolve("symbols")
        val stripTool = ndkDir.get().resolve("toolchains/llvm/prebuilt")
            .walkTopDown().firstOrNull { it.name == "llvm-strip" && it.canExecute() }
        outputDir.walkTopDown().filter { it.extension == "so" }.forEach { so ->
            val abiDir = symbolsDir.resolve(so.parentFile.name).apply { mkdirs() }
            so.copyTo(abiDir.resolve(so.name), overwrite = true)
            if (stripTool != null) {
                providers.exec {
                    commandLine(stripTool.absolutePath, "--strip-unneeded", so.absolutePath)
                }.result.get()
            } else {
                logger.warn("llvm-strip not found in NDK; packaging unstripped ${so.name}")
            }
        }
    }
}

tasks.configureEach {
    if (name == "mergeDebugJniLibFolders" || name == "mergeReleaseJniLibFolders") {
        dependsOn(buildRustLibs)
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.datastore.preferences)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.coil.compose)
    debugImplementation(libs.androidx.ui.tooling)
}
