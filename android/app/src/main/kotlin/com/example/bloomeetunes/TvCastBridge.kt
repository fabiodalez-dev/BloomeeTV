package ls.bloomee.musicplayer

import android.app.Application
import android.app.UiModeManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.support.v4.media.MediaBrowserCompat
import android.support.v4.media.MediaMetadataCompat
import android.net.Uri
import android.support.v4.media.session.MediaControllerCompat
import android.support.v4.media.session.PlaybackStateCompat
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.common.images.WebImage
import com.google.android.gms.cast.tv.CastReceiverContext
import com.google.android.gms.cast.tv.CastReceiverOptions
import com.google.android.gms.cast.tv.media.MediaLoadCommandCallback
import com.google.android.gms.cast.tv.media.MediaMetadataModifier
import com.google.android.gms.cast.tv.ReceiverOptionsProvider
import com.google.android.gms.common.GoogleApiAvailability
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.TaskCompletionSource
import io.flutter.plugin.common.MethodChannel

class TvApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        TvCastBridge.initialize(this)
    }
}

class TvReceiverOptionsProvider : ReceiverOptionsProvider {
    override fun getOptions(context: Context): CastReceiverOptions =
        CastReceiverOptions.Builder(context).setStatusText("Bloomee TV").build()
}

/** Shares audio_service's existing session, including metadata, with Cast.
 * No second player/session is created. Fire TV without Play Services stays local.
 */
object TvCastBridge {
    private var application: Application? = null
    private var receiver: CastReceiverContext? = null
    private var browser: MediaBrowserCompat? = null
    private var controller: MediaControllerCompat? = null
    private var channel: MethodChannel? = null
    private var foreground = false
    private var ready = false
    private var pendingIntent: Intent? = null
    private var detail = "Cast non disponibile su questo dispositivo"

    fun initialize(app: Application) {
        application = app
        val ui = app.getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
        if (ui.currentModeType != Configuration.UI_MODE_TYPE_TELEVISION ||
            GoogleApiAvailability.getInstance().isGooglePlayServicesAvailable(app) != ConnectionResult.SUCCESS) return
        try {
            CastReceiverContext.initInstance(app)
            receiver = CastReceiverContext.getInstance()
            receiver?.mediaManager?.setMediaLoadCommandCallback(object : MediaLoadCommandCallback() {
                override fun onLoad(senderId: String?, request: MediaLoadRequestData): Task<MediaLoadRequestData> {
                    val result = TaskCompletionSource<MediaLoadRequestData>()
                    val info = request.mediaInfo
                    val target = info?.entity ?: info?.contentId
                    val ch = channel
                    if (!ready || target.isNullOrBlank() || ch == null) {
                        result.setException(IllegalStateException("Player non pronto o contenuto non supportato"))
                        return result.task
                    }
                    ch.invokeMethod("load", mapOf("id" to target, "positionMs" to request.currentTime), object : MethodChannel.Result {
                        override fun success(value: Any?) {
                            receiver?.mediaManager?.setDataFromLoad(request)
                            receiver?.mediaManager?.broadcastMediaStatus()
                            result.setResult(request)
                        }
                        override fun error(code: String, message: String?, details: Any?) {
                            result.setException(IllegalArgumentException(message ?: "Contenuto non supportato"))
                        }
                        override fun notImplemented() { result.setException(IllegalStateException("Player non disponibile")) }
                    })
                    return result.task
                }
            })
            detail = "Cast inizializzato; in attesa della sessione audio"
        } catch (_: Exception) { receiver = null; detail = "Cast non inizializzato: verifica Google Play Services" }
    }

    fun attach(ch: MethodChannel) {
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> { ready = true; connectSession(); pendingIntent?.let { handleIntent(it) }; pendingIntent = null; result.success(null) }
                "status" -> result.success(detail)
                else -> result.notImplemented()
            }
        }
    }
    fun start(intent: Intent?) {
        foreground = true
        try { receiver?.start(); if (ready) connectSession(); if (intent != null && intent.action == "com.google.android.gms.cast.tv.action.LAUNCH") handleIntent(intent) }
        catch (_: Exception) { detail = "Avvio Cast non riuscito" }
    }
    fun background() { foreground = false; updateLifecycle(controller?.playbackState) }
    fun handleIntent(intent: Intent) {
        if (!ready) { pendingIntent = intent; return }
        try { receiver?.mediaManager?.onNewIntent(intent) } catch (_: Exception) { detail = "Richiesta Cast non valida" }
    }
    private val callback = object : MediaControllerCompat.Callback() {
        override fun onMetadataChanged(metadata: MediaMetadataCompat?) { publishMetadata(metadata) }
        override fun onPlaybackStateChanged(state: PlaybackStateCompat?) { updateLifecycle(state) }
        override fun onSessionDestroyed() {
            receiver?.mediaManager?.setSessionCompatToken(null)
            publishMetadata(null)
            controller?.unregisterCallback(this)
            controller = null
            browser?.disconnect(); browser = null
            updateLifecycle(null)
        }
    }
    private fun connectSession() {
        val app = application ?: return
        if (receiver == null || browser != null) return
        browser = MediaBrowserCompat(app, ComponentName(app, com.ryanheise.audioservice.AudioService::class.java), object : MediaBrowserCompat.ConnectionCallback() {
            override fun onConnected() {
                try {
                    val token = browser!!.sessionToken
                    controller = MediaControllerCompat(app, token).also { it.registerCallback(callback) }
                    receiver?.mediaManager?.setSessionCompatToken(token)
                    publishMetadata(controller?.metadata)
                    detail = "Cast collegato alla sessione audio di Bloomee TV"
                } catch (_: Exception) { detail = "Sessione Cast non collegata" }
            }
            override fun onConnectionFailed() { browser = null; detail = "Connessione alla sessione audio non riuscita" }
            override fun onConnectionSuspended() { browser?.disconnect(); browser = null; controller = null }
        }, null).also { it.connect() }
    }
    private fun publishMetadata(metadata: MediaMetadataCompat?) {
      try {
        val manager = receiver?.mediaManager ?: return
        val info = manager.mediaStatusModifier.mediaInfoModifier ?: return
        val modifier = info.metadataModifier ?: MediaMetadataModifier().also { info.setMetadataModifier(it) }
        modifier.clear()
        if (metadata != null) {
            val track = TvCastTrack.create(
                metadata.getString(MediaMetadataCompat.METADATA_KEY_TITLE),
                metadata.getString(MediaMetadataCompat.METADATA_KEY_ARTIST),
                metadata.getString(MediaMetadataCompat.METADATA_KEY_ALBUM),
                metadata.getString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI))
            modifier.setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK)
                .putString(MediaMetadata.KEY_TITLE, track.title)
                .putString(MediaMetadata.KEY_ARTIST, track.artist)
                .putString(MediaMetadata.KEY_ALBUM_ARTIST, track.artist)
                .putString(MediaMetadata.KEY_ALBUM_TITLE, track.album)
                .setImages(track.image?.let { listOf(WebImage(Uri.parse(it))) } ?: emptyList())
        }
        // Required after modifier updates; the SDK handles regular session state.
        manager.broadcastMediaStatus()
      } catch (_: Exception) { detail = "Aggiornamento metadati Cast non riuscito" }
    }
    private fun updateLifecycle(state: PlaybackStateCompat?) {
        val alive = state?.state == PlaybackStateCompat.STATE_PLAYING || state?.state == PlaybackStateCompat.STATE_PAUSED || state?.state == PlaybackStateCompat.STATE_BUFFERING
        if (!foreground && !alive) try { receiver?.stop() } catch (_: Exception) { }
    }
}
