import com.android.build.gradle.LibraryExtension
import org.gradle.api.JavaVersion
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

group = "dev.locus"
version = "2.3.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.7.0")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.1.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply(plugin = "com.android.library")
apply(plugin = "org.jetbrains.kotlin.android")

extensions.configure<LibraryExtension>("android") {
    namespace = "dev.locus"
    compileSdk = 34

    defaultConfig {
        minSdk = 26
        targetSdk = 34
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
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
    add("implementation", "com.google.android.gms:play-services-location:21.3.0")
    add("implementation", "org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    add("implementation", "androidx.security:security-crypto:1.1.0-alpha06")

    // JVM unit tests under src/test/kotlin. State helpers
    // (`CompressionFallbackState`, future drainExhaustedContexts) are
    // Context-free by design so plain JUnit + kotlinx-coroutines-test is
    // enough — no Robolectric / emulator required.
    add("testImplementation", "junit:junit:4.13.2")
    add("testImplementation", "org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")
}
