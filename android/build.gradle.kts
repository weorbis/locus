import com.android.build.api.dsl.LibraryExtension
import org.gradle.api.JavaVersion
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

group = "dev.locus"
// Single source of truth: read the version straight out of pubspec.yaml so
// the Gradle module never drifts from the published package version.
version = file("../pubspec.yaml").readText()
    .let { Regex("""^version:\s*(.+)$""", RegexOption.MULTILINE).find(it) }
    ?.groupValues?.get(1)?.trim()
    ?: error("Could not parse `version:` from pubspec.yaml")

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Android and Kotlin plugin versions belong to the consuming Flutter app.
// Local classpath pins create incompatible duplicate plugin types when the
// host uses a different supported toolchain.
apply(plugin = "com.android.library")
apply(plugin = "org.jetbrains.kotlin.android")
extensions.configure<LibraryExtension>("android") {
    namespace = "dev.locus"
    compileSdk = 37

    defaultConfig {
        minSdk = 26
        // targetSdk belongs to the consuming application. Setting it on this
        // library caused LibraryDefaultConfig.setTargetSdk(Integer) linkage
        // failures with newer host Android Gradle Plugin versions.
        // This dependency-free instrumentation executes the production parser
        // against Android's real org.json implementation. TODO: migrate it to
        // AndroidJUnitRunner if a broader Android test suite is introduced.
        testInstrumentationRunner = "dev.locus.core.ConfigSnapshotInstrumentation"
    }

    sourceSets {
        getByName("main") {
            java.directories.add("src/main/kotlin")
        }
        getByName("test") {
            java.directories.add("src/test/kotlin")
        }
        getByName("androidTest") {
            java.directories.add("src/androidTest/kotlin")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        disable.add("InvalidPackage")
    }

    testOptions {
        unitTests.isIncludeAndroidResources = true
        unitTests.isReturnDefaultValues = true
    }
}

tasks.withType<KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    add("implementation", "com.google.android.gms:play-services-location:21.4.0")
    add("implementation", "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")

    // JVM unit tests under src/test/kotlin. State helpers
    // (`CompressionFallbackState`, future drainExhaustedContexts) are
    // Context-free by design so plain JUnit + kotlinx-coroutines-test is
    // enough — no Robolectric / emulator required.
    add("testImplementation", "junit:junit:4.13.2")
    add("testImplementation", "org.jetbrains.kotlinx:kotlinx-coroutines-test:1.11.0")
}
