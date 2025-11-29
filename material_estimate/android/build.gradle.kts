import com.android.build.gradle.LibraryExtension
import org.gradle.api.tasks.Delete

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

    // If this subproject is an Android library, configure safely.
    // Some third-party plugins (older ones) don't specify `namespace` in their module build.gradle
    // which causes AGP 7.3+ to fail. Set a default namespace per module to avoid build failures.
    extensions.findByType(LibraryExtension::class.java)?.let { libExt ->
        try { libExt.compileSdk = 34 } catch (_: Throwable) {}
        try {
            // Use a namespace based on the root package and module name "com.example.<module>"
            // This helps avoid the 'Namespace not specified' error for plugins that don't include it.
            libExt.namespace = "com.example.${'$'}{project.name}"
        } catch (_: Throwable) {}
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}