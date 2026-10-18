package ls.bloomee.musicplayer

import android.annotation.SuppressLint
import android.app.Activity
import android.os.Bundle
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * Pagina web dentro l'app, per i link che sul telefono aprirebbero il browser
 * (su Google TV di solito non c'è): es. l'autorizzazione di Last.FM.
 * Indietro torna alla pagina precedente, poi chiude.
 */
class WebActivity : Activity() {
    private lateinit var web: WebView

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        web = WebView(this)
        setContentView(web)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.webViewClient = WebViewClient()
        web.loadUrl(intent.getStringExtra("url") ?: "about:blank")
    }

    @Deprecated("Indietro nella WebView, poi chiudi")
    override fun onBackPressed() {
        if (web.canGoBack()) web.goBack() else super.onBackPressed()
    }
}
