import com.android.build.gradle.LibraryExtension
import org.gradle.api.JavaVersion

group = "dev.locus"
version = "1.0.0"

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.7.0")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply(plugin = "com.android.library")

extensions.configure<LibraryExtension>("android") {
    namespace = "dev.locus"
    compileSdk = 34

    defaultConfig {
        minSdk = 26
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    lint {
        disable.add("InvalidPackage")
    }
}

dependencies {
    add("implementation", "com.google.android.gms:play-services-location:21.3.0")
}
