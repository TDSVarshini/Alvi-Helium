allprojects {
    repositories {
        google()
        mavenCentral()
        // Vendor ring SDK (AAR) shipped inside the qring_sdk plugin.
        maven { url = uri("${rootDir}/../packages/qring_sdk/android/libs-maven") }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
