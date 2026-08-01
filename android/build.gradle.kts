allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// AGP 锁在 8.7.3（见 gradle.properties 注释 / android-toolchain 记忆），
// 但 url_launcher_android 等插件会把 androidx.browser / androidx.core 传递拉到
// 需要 AGP 8.9.1+ 的新版（browser 1.9.0、core 1.17.0），导致 checkAarMetadata 失败。
// 这里强制压回 8.7.3 能接受的版本（core 1.13.1 需 compileSdk 34、browser 1.8.0 需 34，
// 均不要求 AGP 8.9.1）。若日后升 AGP 到 8.9.1+ 可移除此段。
subprojects {
    configurations.all {
        resolutionStrategy {
            force("androidx.browser:browser:1.8.0")
            force("androidx.core:core:1.13.1")
            force("androidx.core:core-ktx:1.13.1")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
