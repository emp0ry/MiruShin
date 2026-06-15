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
    configurations.configureEach {
        resolutionStrategy.dependencySubstitution {
            // JitPack serves this transitive flutter_js artifact behind a
            // Cloudflare challenge in CI, so build the same QuickJS runtime
            // from the vendored source instead.
            substitute(
                module("com.github.fast-development.android-js-runtimes:fastdev-jsruntimes-quickjs")
            )
                .using(project(":fastdev-jsruntimes-quickjs"))
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
