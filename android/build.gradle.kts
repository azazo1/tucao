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

// jni 插件在自己的 build.gradle 里把 ndkVersion 写死成 flutter.ndkVersion (28.2.13676358),
// 只改 app 模块的话 AGP 仍会为它现下那份约 600MB 的 NDK, 所以 ci 上连插件模块一起覆盖.
// 本地不覆盖, 保持 Flutter 默认的 NDK.
// 用反射设置, 避免在根脚本里引入 AGP 的类型依赖.
if (providers.environmentVariable("CI").isPresent) {
    val ciNdkVersion: String = providers.gradleProperty("tucao.ndkVersion").get()
    subprojects {
        afterEvaluate {
            val androidExtension = extensions.findByName("android") ?: return@afterEvaluate
            val setter = androidExtension.javaClass.methods.firstOrNull { method ->
                method.name == "setNdkVersion" && method.parameterCount == 1
            }
            setter?.invoke(androidExtension, ciNdkVersion)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
