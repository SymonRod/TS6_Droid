package dev.tsdroid.ui.component

import android.app.Activity
import android.content.pm.ActivityInfo
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ScreenShare
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.FullscreenExit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import dev.tsdroid.R
import dev.tsdroid.bridge.StreamEgl
import dev.tsdroid.bridge.StreamViewPhase
import dev.tsdroid.bridge.StreamViewerState
import dev.tslib.Stream
import dev.tslib.User
import kotlinx.coroutines.delay
import org.webrtc.RendererCommon
import org.webrtc.SurfaceViewRenderer
import org.webrtc.VideoFrame
import org.webrtc.VideoSink

/** The streams on offer; picking one asks its owner for permission. */
@Composable
fun StreamListDialog(
    streams: List<Stream>,
    users: List<User>,
    onSelect: (Stream) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.screen_shares)) },
        text = {
            LazyColumn {
                items(streams, key = { "${it.ownerId}:${it.id}" }) { stream ->
                    val owner = users.find { it.id == stream.ownerId }?.nickname
                        ?: context.getString(R.string.user_fallback, stream.ownerId)
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelect(stream) }
                            .padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            Icons.AutoMirrored.Filled.ScreenShare,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.primary,
                        )
                        Spacer(Modifier.width(12.dp))
                        Column(Modifier.weight(1f)) {
                            Text(
                                stream.name ?: owner,
                                style = MaterialTheme.typography.bodyMedium,
                            )
                            Text(
                                stringResource(R.string.screen_share_of, owner),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        stream.viewerCount?.let { count ->
                            Text(
                                stringResource(R.string.screen_share_viewers, count),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.close)) }
        },
    )
}

/**
 * Full-screen player for the stream the WebRTC viewer is negotiating or
 * showing. Handles every phase, since a join can be refused or go unanswered.
 */
@Composable
fun StreamViewerOverlay(
    state: StreamViewerState,
    onClose: () -> Unit,
) {
    // The overlay covers the server screen, so the system back has to reach it
    // first — otherwise it navigates the screen hidden underneath.
    BackHandler { onClose() }
    var stats by remember { mutableStateOf<String?>(null) }
    // Fit letterboxes the whole frame; fill crops it to the screen edges.
    var fillScreen by remember { mutableStateOf(false) }
    KeepAwakeAndOriented()

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = Color.Black,
    ) {
        Box(Modifier.fillMaxSize()) {
            when (state.phase) {
                StreamViewPhase.PLAYING -> VideoSurface(
                    state = state,
                    fillScreen = fillScreen,
                    onStats = { stats = it },
                    modifier = Modifier.fillMaxSize(),
                )
                StreamViewPhase.FAILED -> CenteredStatus(failureText(state.message), onClose)
                StreamViewPhase.REQUESTING ->
                    CenteredStatus(stringResource(R.string.screen_share_requesting), onClose, spinner = true)
                else ->
                    CenteredStatus(stringResource(R.string.screen_share_connecting), onClose, spinner = true)
            }

            Row(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .fillMaxWidth()
                    .statusBarsPadding()
                    .background(Color(0x66000000))
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    state.title,
                    modifier = Modifier.weight(1f),
                    color = Color.White,
                    style = MaterialTheme.typography.titleSmall,
                )
                stats?.let { line ->
                    Text(
                        line,
                        modifier = Modifier.padding(end = 8.dp),
                        color = Color.White,
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
                if (state.phase == StreamViewPhase.PLAYING) {
                    IconButton(onClick = { fillScreen = !fillScreen }) {
                        Icon(
                            if (fillScreen) Icons.Default.FullscreenExit else Icons.Default.Fullscreen,
                            contentDescription = stringResource(
                                if (fillScreen) R.string.screen_share_fit else R.string.screen_share_fill,
                            ),
                            tint = Color.White,
                        )
                    }
                }
                IconButton(onClick = onClose) {
                    Icon(
                        Icons.Default.Close,
                        contentDescription = stringResource(R.string.close),
                        tint = Color.White,
                    )
                }
            }
        }
    }
}

/**
 * While the player is up: no screen timeout, no system bars, and both
 * orientations. The player does not pick one — a desktop stream is easier to
 * read in landscape, but holding the phone upright has to keep working, and a
 * phone sharing its own screen is portrait to begin with. `FULL_SENSOR` also
 * ignores the system rotation lock, which would otherwise pin a full-screen
 * player to whichever way the phone happens to be locked.
 * Everything is put back on dispose, so leaving the player restores the app's
 * own chrome.
 */
@Composable
private fun KeepAwakeAndOriented() {
    val view = LocalView.current
    val activity = LocalContext.current as? Activity

    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
    // Captured once: re-reading it after we have set an orientation would
    // restore our own value instead of the screen's.
    val previousOrientation = remember(activity) {
        activity?.requestedOrientation ?: ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }
    DisposableEffect(activity) {
        activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
        onDispose { activity?.requestedOrientation = previousOrientation }
    }
    DisposableEffect(view) {
        val window = activity?.window
        val insets = window?.let { WindowInsetsControllerCompat(it, view) }
        insets?.apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
        onDispose { insets?.show(WindowInsetsCompat.Type.systemBars()) }
    }
}

/** Zoom bounds; past 5× a desktop stream is a handful of pixels. */
private const val MIN_ZOOM = 1f
private const val MAX_ZOOM = 5f

@Composable
private fun VideoSurface(
    state: StreamViewerState,
    fillScreen: Boolean,
    onStats: (String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    val track = state.track ?: return
    val context = LocalContext.current
    var frameWidth by remember { mutableIntStateOf(0) }
    var frameHeight by remember { mutableIntStateOf(0) }
    val frames = remember { java.util.concurrent.atomic.AtomicInteger() }

    val renderer = remember {
        SurfaceViewRenderer(context).apply {
            init(
                StreamEgl.context,
                object : RendererCommon.RendererEvents {
                    override fun onFirstFrameRendered() = Unit
                    override fun onFrameResolutionChanged(width: Int, height: Int, rotation: Int) {
                        // Called on the render thread; the swap follows the frame's rotation.
                        val portrait = rotation == 90 || rotation == 270
                        frameWidth = if (portrait) height else width
                        frameHeight = if (portrait) width else height
                    }
                },
            )
            setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FIT)
            setEnableHardwareScaler(true)
        }
    }
    // Count frames on the way to the renderer — that is the only place the
    // real frame rate shows up, decoder side.
    val sink = remember(renderer) {
        VideoSink { frame: VideoFrame ->
            frames.incrementAndGet()
            renderer.onFrame(frame)
        }
    }
    DisposableEffect(sink, track) {
        track.addSink(sink)
        onDispose { runCatching { track.removeSink(sink) } }
    }
    DisposableEffect(renderer) {
        onDispose { renderer.release() }
    }
    LaunchedEffect(sink) {
        while (true) {
            delay(1_000)
            val fps = frames.getAndSet(0)
            onStats(
                if (frameWidth > 0) {
                    context.getString(R.string.screen_share_stats, frameWidth, frameHeight, fps)
                } else {
                    null
                },
            )
        }
    }
    DisposableEffect(Unit) {
        onDispose { onStats(null) }
    }
    var zoom by remember { mutableFloatStateOf(MIN_ZOOM) }
    var pan by remember { mutableStateOf(Offset.Zero) }
    var videoSize by remember { mutableStateOf(IntSize.Zero) }
    // A new aspect ratio or a fit/fill switch invalidates where we were looking.
    LaunchedEffect(fillScreen, frameWidth, frameHeight) {
        zoom = MIN_ZOOM
        pan = Offset.Zero
    }

    /** Keep the panned frame covering the view: no dragging past its edges. */
    fun clamp(offset: Offset, scale: Float): Offset {
        val maxX = videoSize.width * (scale - 1f) / 2f
        val maxY = videoSize.height * (scale - 1f) / 2f
        return Offset(offset.x.coerceIn(-maxX, maxX), offset.y.coerceIn(-maxY, maxY))
    }

    val aspect = if (frameWidth > 0 && frameHeight > 0) {
        frameWidth.toFloat() / frameHeight.toFloat()
    } else {
        0f
    }
    // Until the resolution is known the renderer fills the box; afterwards it
    // is laid out at the frame's own aspect ratio. That matters: the renderer
    // crops whatever it needs to fill its layout, so a full-screen view of a
    // 16:9 stream on a 20:9 phone would lose the top and bottom of the frame.
    val sizing = if (aspect > 0f && !fillScreen) {
        Modifier.aspectRatio(aspect)
    } else {
        Modifier.fillMaxSize()
    }

    Box(
        modifier = modifier
            .pointerInput(Unit) {
                detectTransformGestures { _, gesturePan, gestureZoom, _ ->
                    val scaled = (zoom * gestureZoom).coerceIn(MIN_ZOOM, MAX_ZOOM)
                    // Pan in view pixels, then re-clamp: a pinch back to 1×
                    // has to let go of an offset that is no longer reachable.
                    zoom = scaled
                    pan = clamp(pan + gesturePan, scaled)
                }
            }
            .pointerInput(Unit) {
                detectTapGestures(
                    // Zoomed in, a double tap is "back out"; otherwise it is
                    // the usual fit/fill flip players do.
                    onDoubleTap = {
                        if (zoom > MIN_ZOOM) {
                            zoom = MIN_ZOOM
                            pan = Offset.Zero
                        } else {
                            zoom = MAX_ZOOM / 2f
                        }
                    },
                )
            },
        contentAlignment = Alignment.Center,
    ) {
        AndroidView(
            factory = { renderer },
            // SurfaceView follows the View's own scale and translation; a
            // Compose graphicsLayer would leave the surface behind.
            update = {
                it.scaleX = zoom
                it.scaleY = zoom
                it.translationX = pan.x
                it.translationY = pan.y
            },
            modifier = sizing.onSizeChanged { videoSize = it },
        )
    }
}

@Composable
private fun CenteredStatus(text: String, onClose: () -> Unit, spinner: Boolean = false) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .navigationBarsPadding()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        if (spinner) {
            CircularProgressIndicator(color = Color.White, modifier = Modifier.size(36.dp))
            Spacer(Modifier.height(16.dp))
        }
        Text(text, color = Color.White, style = MaterialTheme.typography.bodyMedium)
        Spacer(Modifier.height(16.dp))
        TextButton(onClick = onClose) { Text(stringResource(R.string.close)) }
    }
}

/**
 * Map the viewer's reason codes to text; anything else is the sharer's own
 * refusal message, which is worth showing verbatim.
 */
@Composable
private fun failureText(message: String?): String = when (message) {
    "refused" -> stringResource(R.string.screen_share_refused)
    "join_timeout" -> stringResource(R.string.screen_share_timeout)
    "stream_ended" -> stringResource(R.string.screen_share_ended)
    null, "no_offer", "negotiation_failed", "ice_failed", "connection_closed" ->
        stringResource(R.string.screen_share_failed)
    else -> message
}
