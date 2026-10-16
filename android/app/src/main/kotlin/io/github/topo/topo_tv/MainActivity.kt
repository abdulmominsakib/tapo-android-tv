package io.github.topo.topo_tv

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "topo/player")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                // Where the player saves last-frame snapshots (app cache).
                "snapshotDir" -> result.success(File(cacheDir, "snapshots").apply { mkdirs() }.absolutePath)
                else -> result.notImplemented()
            }
        }
        flutterEngine.platformViewsController.registry
            .registerViewFactory("topo/live-video", LiveVideoViewFactory(channel))
    }
}
