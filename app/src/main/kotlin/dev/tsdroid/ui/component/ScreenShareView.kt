package dev.tsdroid.ui.component

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
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
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import dev.tsdroid.R
import dev.tsdroid.bridge.StreamEgl
import dev.tsdroid.bridge.StreamViewPhase
import dev.tsdroid.bridge.StreamViewerState
import dev.tslib.Stream
import dev.tslib.User
import org.webrtc.RendererCommon
import org.webrtc.SurfaceViewRenderer

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
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = Color.Black,
    ) {
        Box(Modifier.fillMaxSize()) {
            when (state.phase) {
                StreamViewPhase.PLAYING -> VideoSurface(state, Modifier.fillMaxSize())
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

@Composable
private fun VideoSurface(state: StreamViewerState, modifier: Modifier = Modifier) {
    val track = state.track ?: return
    val context = LocalContext.current
    val renderer = remember {
        SurfaceViewRenderer(context).apply {
            init(StreamEgl.context, null)
            setScalingType(RendererCommon.ScalingType.SCALE_ASPECT_FIT)
            setEnableHardwareScaler(true)
        }
    }
    DisposableEffect(renderer, track) {
        track.addSink(renderer)
        onDispose { runCatching { track.removeSink(renderer) } }
    }
    DisposableEffect(renderer) {
        onDispose { renderer.release() }
    }
    AndroidView(factory = { renderer }, modifier = modifier)
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
