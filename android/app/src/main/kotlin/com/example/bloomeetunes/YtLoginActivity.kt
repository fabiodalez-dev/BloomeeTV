package ls.bloomee.musicplayer

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient

/**
 * Accesso a YouTube Music con l'account Google (come Echo Music): pagina di
 * login Google in una WebView; quando si arriva su music.youtube.com leggo i
 * cookie di sessione, VISITOR_DATA e DATASYNC_ID e li restituisco all'app.
 */
class YtLoginActivity : Activity() {
    private lateinit var web: WebView
    private var cookie: String? = null
    private var visitorData: String? = null
    private var dataSyncId: String? = null
    private var done = false

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        web = WebView(this)
        setContentView(web)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.addJavascriptInterface(object {
            @JavascriptInterface
            fun onVisitorData(v: String?) { visitorData = v; maybeFinish() }
            @JavascriptInterface
            fun onDataSyncId(v: String?) { dataSyncId = v; maybeFinish() }
        }, "Android")
        web.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                if (url.startsWith("https://music.youtube.com")) {
                    val c = CookieManager.getInstance().getCookie(url)
                    if (c != null && (c.contains("SAPISID") || c.contains("__Secure-3PAPISID"))) {
                        cookie = c
                        view.loadUrl("javascript:Android.onVisitorData(window.yt && window.yt.config_ ? window.yt.config_.VISITOR_DATA : null)")
                        view.loadUrl("javascript:Android.onDataSyncId(window.yt && window.yt.config_ ? window.yt.config_.DATASYNC_ID : null)")
                    }
                }
            }
        }
        if (intent.getBooleanExtra("logout", false)) {
            CookieManager.getInstance().removeAllCookies(null)
            CookieManager.getInstance().flush()
            setResult(RESULT_OK)
            finish()
            return
        }
        CookieManager.getInstance().removeAllCookies(null)
        CookieManager.getInstance().flush()
        web.loadUrl("https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com")
    }

    private fun maybeFinish() {
        if (done || cookie == null || visitorData == null || dataSyncId == null) return
        done = true
        runOnUiThread {
            CookieManager.getInstance().flush()
            setResult(RESULT_OK, Intent().apply {
                putExtra("cookie", cookie)
                putExtra("visitorData", visitorData)
                putExtra("dataSyncId", dataSyncId)
            })
            finish()
        }
    }

    @Deprecated("Indietro nella WebView, poi chiudi")
    override fun onBackPressed() {
        if (web.canGoBack()) web.goBack() else super.onBackPressed()
    }
}
