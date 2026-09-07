package dev.tsdroid.bridge

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONObject
import org.webrtc.AudioTrack
import org.webrtc.DefaultVideoDecoderFactory
import org.webrtc.DefaultVideoEncoderFactory
import org.webrtc.EglBase
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.VideoTrack
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/**
 * The EGL context shared by the decoder and every renderer. It lives as long
 * as the process: `SurfaceViewRenderer`s come and go with the UI, while the
 * decoder wants a stable context.
 */
object StreamEgl {
    val base: EglBase by lazy { EglBase.create() }
    val context: EglBase.Context get() = base.eglBaseContext
}

/** What the viewer is doing with the stream it was asked to show. */
enum class StreamViewPhase { IDLE, REQUESTING, CONNECTING, PLAYING, FAILED }

/**
 * A snapshot of the viewer. [track] is set only in [StreamViewPhase.PLAYING];
 * [message] carries the sharer's refusal text or a failure reason.
 */
data class StreamViewerState(
    val ownerId: Int = 0,
    val streamId: String = "",
    val title: String = "",
    val phase: StreamViewPhase = StreamViewPhase.IDLE,
    val message: String? = null,
    val track: VideoTrack? = null,
)

/**
 * The viewer half of TeamSpeak 6 screen sharing, in `STREAM_P2P` mode.
 *
 * `tslib` only carries signaling: this class owns the WebRTC session. It asks
 * a sharer to join ([join]), answers the SDP offer that comes back on
 * [TsClient.streamJoinResponses], trickles ICE both ways over
 * [TsClient.streamSignaling], and publishes the received video track.
 *
 * One stream at a time — joining another one leaves the current session first.
 * SDP and ICE payloads are never logged, at any level.
 */
class StreamViewer(
    context: Context,
    private val tsClient: TsClient,
    private val scope: CoroutineScope,
) {
    companion object {
        private const val TAG = "StreamViewer"

        /** A join request can simply go unanswered — the sharer decides. */
        private const val JOIN_TIMEOUT_MS = 30_000L

        /**
         * Trickled candidates are paced: a burst is the plausible way to trip
         * the server's flood protection (protocol §9b.5).
         */
        private const val CANDIDATE_INTERVAL_MS = 120L

        /** Hardcoded in the desktop client (§6); they reflect but do not relay. */
        private val ICE_SERVERS = listOf(
            PeerConnection.IceServer.builder("stun:turn.teamspeak.com:3478").createIceServer(),
            PeerConnection.IceServer.builder("stun:turn2.teamspeak.com:3478").createIceServer(),
        )
    }

    private val appContext = context.applicationContext

    private val _state = MutableStateFlow(StreamViewerState())
    val state: StateFlow<StreamViewerState> = _state.asStateFlow()

    private val mutex = Mutex()
    private var factory: PeerConnectionFactory? = null
    private var connection: PeerConnection? = null
    private var joinTimeout: Job? = null
    private var candidatePump: Job? = null
    private var outgoingCandidates: Channel<IceCandidate>? = null

    /** Remote candidates that arrived before the offer was applied. */
    private val pendingRemote = mutableListOf<IceCandidate>()
    private var remoteDescriptionSet = false

    private var target: Pair<Int, String>? = null

    init {
        scope.launch {
            tsClient.streamJoinResponses.collect { response ->
                if (target == Pair(response.ownerId, response.streamId)) {
                    onJoinResponse(response)
                }
            }
        }
        scope.launch {
            tsClient.streamSignaling.collect { signaling ->
                if (target == Pair(signaling.ownerId, signaling.streamId)) {
                    onSignaling(signaling.json)
                }
            }
        }
        scope.launch {
            // A stream that stopped, or whose owner left, is gone for good.
            tsClient.streams.collect { streams ->
                val current = target ?: return@collect
                if (streams.none { it.ownerId == current.first && it.id == current.second }) {
                    fail("stream_ended")
                }
            }
        }
    }

    /** Ask [ownerId] to let us view [streamId]; watch [state] for the answer. */
    fun join(ownerId: Int, streamId: String, title: String) {
        scope.launch {
            mutex.withLock {
                teardownLocked(notifySharer = true)
                target = ownerId to streamId
                _state.value = StreamViewerState(
                    ownerId = ownerId,
                    streamId = streamId,
                    title = title,
                    phase = StreamViewPhase.REQUESTING,
                )
                tsClient.joinStream(ownerId, streamId)
                joinTimeout = scope.launch {
                    delay(JOIN_TIMEOUT_MS)
                    if (_state.value.phase == StreamViewPhase.REQUESTING) fail("join_timeout")
                }
            }
        }
    }

    /** Stop viewing and tell the sharer. Safe to call when idle. */
    fun leave() {
        scope.launch {
            mutex.withLock {
                teardownLocked(notifySharer = true)
                _state.value = StreamViewerState()
            }
        }
    }

    /** Release WebRTC resources; the instance is unusable afterwards. */
    fun release() {
        scope.launch {
            mutex.withLock {
                teardownLocked(notifySharer = true)
                _state.value = StreamViewerState()
                factory?.dispose()
                factory = null
            }
        }
    }

    private suspend fun onJoinResponse(response: TsStreamJoinResponse) = mutex.withLock {
        joinTimeout?.cancel()
        joinTimeout = null
        if (!response.accepted) {
            Log.i(TAG, "Join refused for stream of client ${response.ownerId}")
            failLocked("refused", response.message?.takeIf { it.isNotBlank() })
            return@withLock
        }
        val offer = response.offer
        if (offer.isNullOrEmpty()) {
            failLocked("no_offer", null)
            return@withLock
        }
        _state.value = _state.value.copy(phase = StreamViewPhase.CONNECTING, message = null)
        runCatching { answerOffer(offer) }.onFailure {
            Log.w(TAG, "WebRTC negotiation failed", it)
            failLocked("negotiation_failed", null)
        }
    }

    private suspend fun answerOffer(offer: String) {
        val (ownerId, streamId) = target ?: return
        val factory = ensureFactory()
        val config = PeerConnection.RTCConfiguration(ICE_SERVERS).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            bundlePolicy = PeerConnection.BundlePolicy.MAXBUNDLE
            rtcpMuxPolicy = PeerConnection.RtcpMuxPolicy.REQUIRE
        }
        val candidates = Channel<IceCandidate>(Channel.UNLIMITED)
        outgoingCandidates = candidates
        val pc = factory.createPeerConnection(config, PeerObserver(candidates))
            ?: throw IllegalStateException("createPeerConnection returned null")
        connection = pc

        // Pace trickled candidates: a burst is what trips flood protection.
        candidatePump = scope.launch {
            for (candidate in candidates) {
                tsClient.sendStreamSignaling(ownerId, streamId, candidateJson(candidate))
                delay(CANDIDATE_INTERVAL_MS)
            }
        }

        pc.setRemoteDescriptionAwait(SessionDescription(SessionDescription.Type.OFFER, offer))
        remoteDescriptionSet = true
        pendingRemote.forEach { pc.addIceCandidate(it) }
        pendingRemote.clear()

        val answer = pc.createAnswerAwait()
        pc.setLocalDescriptionAwait(answer)
        tsClient.sendStreamSignaling(ownerId, streamId, answerJson(answer.description))
    }

    private suspend fun onSignaling(json: String) {
        // The server relays this parameter without inspecting it (§9b.2), so a
        // malformed or unknown message reaches us: ignore instead of failing.
        val parsed = runCatching { JSONObject(json) }.getOrNull() ?: return
        when (parsed.optString("cmd")) {
            "iceCandidate" -> {
                val args = parsed.optJSONObject("args") ?: return
                val sdp = args.optString("sdp").takeIf { it.isNotEmpty() } ?: return
                val candidate = IceCandidate(
                    args.optString("mid", ""),
                    args.optInt("mLine", 0),
                    sdp,
                )
                mutex.withLock {
                    val pc = connection
                    if (pc != null && remoteDescriptionSet) pc.addIceCandidate(candidate)
                    else pendingRemote += candidate
                }
            }
            // "answer" is ours to send, "reconnect" was never observed in the
            // wild; anything else is a future command we do not speak yet.
            else -> Unit
        }
    }

    private fun answerJson(sdp: String): String = JSONObject()
        .put("cmd", "answer")
        .put("args", JSONObject().put("answer", sdp))
        .toString()

    private fun candidateJson(candidate: IceCandidate): String = JSONObject()
        .put("cmd", "iceCandidate")
        .put(
            "args",
            JSONObject()
                .put("mLine", candidate.sdpMLineIndex)
                .put("mid", candidate.sdpMid ?: "")
                .put("sdp", candidate.sdp),
        )
        .toString()

    private fun ensureFactory(): PeerConnectionFactory = factory ?: run {
        PeerConnectionFactory.initialize(
            PeerConnectionFactory.InitializationOptions.builder(appContext)
                .createInitializationOptions()
        )
        PeerConnectionFactory.builder()
            .setVideoDecoderFactory(DefaultVideoDecoderFactory(StreamEgl.context))
            .setVideoEncoderFactory(DefaultVideoEncoderFactory(StreamEgl.context, true, true))
            .createPeerConnectionFactory()
            .also { factory = it }
    }

    private fun fail(reason: String) {
        scope.launch { mutex.withLock { failLocked(reason, null) } }
    }

    private fun failLocked(reason: String, message: String?) {
        if (target == null) return
        val previous = _state.value
        teardownLocked(notifySharer = false)
        _state.value = previous.copy(
            phase = StreamViewPhase.FAILED,
            message = message ?: reason,
            track = null,
        )
    }

    private fun teardownLocked(notifySharer: Boolean) {
        val current = target
        joinTimeout?.cancel()
        joinTimeout = null
        candidatePump?.cancel()
        candidatePump = null
        outgoingCandidates?.close()
        outgoingCandidates = null
        pendingRemote.clear()
        remoteDescriptionSet = false
        connection?.let { pc ->
            runCatching { pc.dispose() }.onFailure { Log.w(TAG, "PeerConnection dispose failed", it) }
        }
        connection = null
        if (notifySharer && current != null) {
            tsClient.leaveStream(current.first, current.second)
        }
        target = null
    }

    private inner class PeerObserver(
        private val candidates: Channel<IceCandidate>,
    ) : PeerConnection.Observer {
        override fun onIceCandidate(candidate: IceCandidate) {
            candidates.trySend(candidate)
        }

        override fun onTrack(transceiver: org.webrtc.RtpTransceiver) {
            when (val track = transceiver.receiver?.track()) {
                is VideoTrack -> {
                    track.setEnabled(true)
                    _state.value = _state.value.copy(
                        phase = StreamViewPhase.PLAYING,
                        message = null,
                        track = track,
                    )
                }
                is AudioTrack -> track.setEnabled(true)
                else -> Unit
            }
        }

        override fun onIceConnectionChange(newState: PeerConnection.IceConnectionState) {
            Log.d(TAG, "ICE state: $newState")
            when (newState) {
                PeerConnection.IceConnectionState.FAILED -> fail("ice_failed")
                PeerConnection.IceConnectionState.CLOSED -> fail("connection_closed")
                else -> Unit
            }
        }

        override fun onSignalingChange(state: PeerConnection.SignalingState) = Unit
        override fun onIceConnectionReceivingChange(receiving: Boolean) = Unit
        override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) = Unit
        override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) = Unit
        override fun onAddStream(stream: MediaStream) = Unit
        override fun onRemoveStream(stream: MediaStream) = Unit
        override fun onDataChannel(channel: org.webrtc.DataChannel) = Unit
        override fun onRenegotiationNeeded() = Unit
        override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) = Unit
    }
}

private suspend fun PeerConnection.setRemoteDescriptionAwait(description: SessionDescription) =
    suspendCoroutine { continuation ->
        setRemoteDescription(object : SimpleSdpObserver() {
            override fun onSetSuccess() = continuation.resume(Unit)
            override fun onSetFailure(error: String?) =
                continuation.resumeWith(Result.failure(IllegalStateException("setRemoteDescription: $error")))
        }, description)
    }

private suspend fun PeerConnection.setLocalDescriptionAwait(description: SessionDescription) =
    suspendCoroutine { continuation ->
        setLocalDescription(object : SimpleSdpObserver() {
            override fun onSetSuccess() = continuation.resume(Unit)
            override fun onSetFailure(error: String?) =
                continuation.resumeWith(Result.failure(IllegalStateException("setLocalDescription: $error")))
        }, description)
    }

private suspend fun PeerConnection.createAnswerAwait(): SessionDescription =
    suspendCoroutine { continuation ->
        createAnswer(object : SimpleSdpObserver() {
            override fun onCreateSuccess(description: SessionDescription) =
                continuation.resume(description)
            override fun onCreateFailure(error: String?) =
                continuation.resumeWith(Result.failure(IllegalStateException("createAnswer: $error")))
        }, MediaConstraints())
    }

private abstract class SimpleSdpObserver : SdpObserver {
    override fun onCreateSuccess(description: SessionDescription) = Unit
    override fun onSetSuccess() = Unit
    override fun onCreateFailure(error: String?) = Unit
    override fun onSetFailure(error: String?) = Unit
}
