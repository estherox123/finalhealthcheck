plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.healthcheck.finalhealthcheck"
    compileSdk = 35          // Android 14 (API 35)
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.healthcheck.finalhealthcheck"
        minSdk = 26          // Health Connect 최소 요구
        targetSdk = 35       // Android 14 타깃
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        resources {
            excludes += setOf("META-INF/AL2.0", "META-INF/LGPL2.1")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // AndroidX 기본
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    // 권한 요청용 (permission_handler와 연동)
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.fragment:fragment-ktx:1.8.5")

    // Health Connect AndroidX dependency
    implementation("androidx.health.connect:connect-client:1.1.0-alpha11")

    // (필요시) 멀티덱스
    implementation("androidx.multidex:multidex:2.0.1")
}
