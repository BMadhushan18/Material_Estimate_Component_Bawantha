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

    // If this subproject is an Android library, configure safely
    extensions.findByType(LibraryExtension::class.java)?.let { libExt ->
        try { libExt.compileSdk = 34 } catch (_: Throwable) {}
        try { libExt.namespace = "io.carius.lars.ar_flutter_plugin" } catch (_: Throwable) {}
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}