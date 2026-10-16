package io.github.topo.topo_tv

import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.TextureView
import android.view.View
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/**
 * Native live video view: ExoPlayer rendering into an Android TextureView,
 * embedded in Flutter with hybrid composition.
 *
 * A native view is used instead of a Flutter texture because on some
 * devices the texture's buffers are never handed back to the decoder and
 * the picture freezes after a few frames. The view is never focusable, so
 * the D-pad focus always stays in Flutter.
 */
class LiveVideoViewFactory(private val channel: MethodChannel) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val url = (args as? Map<*, *>)?.get("url") as? String
            ?: throw IllegalArgumentException("url is required")
        return LiveVideoView(context, url) { event ->
            channel.invokeMethod("event", event + ("id" to viewId))
        }
    }
}

private class LiveVideoView(
    context: Context,
    url: String,
    private val emit: (Map<String, Any?>) -> Unit,
) : PlatformView {
    private val handler = Handler(Looper.getMainLooper())
    private val textureView = TextureView(context).apply {
        isFocusable = false
        isFocusableInTouchMode = false
        importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
    }
    private val player: ExoPlayer
    private var released = false
    private var speedUp = false

    /**
     * The relay is a live stream exposed as an unbounded progressive file,
     * so ExoPlayer cannot seek to the live edge. Instead, play slightly
     * faster while more than ~1.5 s is buffered to drain accumulated delay.
     */
    private val latencyWatch: Runnable = object : Runnable {
        override fun run() {
            if (released) return
            val ahead = player.bufferedPosition - player.currentPosition
            if (!speedUp && ahead > 1500) {
                speedUp = true
                player.playbackParameters = PlaybackParameters(1.25f)
            } else if (speedUp && ahead < 600) {
                speedUp = false
                player.playbackParameters = PlaybackParameters(1f)
            }
            handler.postDelayed(this, 500)
        }
    }

    init {
        // A camera preview should start as soon as one GOP is available and
        // never accumulate seconds of delay, so keep the buffers small.
        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(500, 4000, 250, 500)
            .setPrioritizeTimeOverSizeThresholds(true)
            .build()
        val extractors = DefaultExtractorsFactory()
            .setTsExtractorFlags(
                DefaultTsPayloadReaderFactory.FLAG_ALLOW_NON_IDR_KEYFRAMES or
                    DefaultTsPayloadReaderFactory.FLAG_DETECT_ACCESS_UNITS
            )
        val dataSource = DefaultHttpDataSource.Factory()
            .setConnectTimeoutMs(10_000)
            .setReadTimeoutMs(30_000)
        val source = ProgressiveMediaSource.Factory(dataSource, extractors)
            .createMediaSource(MediaItem.fromUri(Uri.parse(url)))

        player = ExoPlayer.Builder(context, renderersFactory(context))
            .setLoadControl(loadControl)
            .build()
        player.volume = 0f
        player.setVideoTextureView(textureView)
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                when (state) {
                    Player.STATE_BUFFERING -> emit(mapOf("state" to "buffering"))
                    Player.STATE_READY -> emit(mapOf("state" to "playing"))
                    Player.STATE_ENDED -> emit(mapOf("state" to "error", "message" to "Stream ended"))
                    else -> {}
                }
            }

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width <= 0 || videoSize.height <= 0) return
                emit(
                    mapOf(
                        "state" to "size",
                        "width" to videoSize.width,
                        "height" to videoSize.height,
                    )
                )
            }

            override fun onRenderedFirstFrame() {
                emit(mapOf("state" to "firstFrame"))
            }

            override fun onPlayerError(error: PlaybackException) {
                emit(mapOf("state" to "error", "message" to (error.cause?.message ?: error.message)))
            }
        })
        player.setMediaSource(source)
        player.playWhenReady = true
        player.prepare()
        handler.postDelayed(latencyWatch, 1000)
    }

    override fun getView(): View = textureView

    companion object {
        /**
         * Emulators expose a "goldfish" hardware decoder that stalls after a
         * dozen frames on live H.264, so there prefer the software decoder.
         * Real TVs keep their hardware decoders.
         */
        private val isEmulator: Boolean =
            Build.HARDWARE.contains("goldfish") || Build.HARDWARE.contains("ranchu") ||
                Build.PRODUCT.startsWith("sdk_") || Build.FINGERPRINT.contains("generic")

        fun renderersFactory(context: Context): DefaultRenderersFactory {
            val factory = DefaultRenderersFactory(context).setEnableDecoderFallback(true)
            if (!isEmulator) return factory
            return factory.setMediaCodecSelector { mimeType, secure, tunneling ->
                MediaCodecSelector.DEFAULT.getDecoderInfos(mimeType, secure, tunneling)
                    .sortedBy { it.hardwareAccelerated }
            }
        }
    }

    override fun dispose() {
        if (released) return
        released = true
        handler.removeCallbacks(latencyWatch)
        player.release()
    }
}
