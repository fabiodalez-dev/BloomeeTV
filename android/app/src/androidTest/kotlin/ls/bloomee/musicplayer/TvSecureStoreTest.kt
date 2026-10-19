package ls.bloomee.musicplayer

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class TvSecureStoreTest {
    @Test fun loginOriginRequiresExactHttpsHost() {
        assertTrue(YtLoginActivity.isMusicOrigin("https://music.youtube.com/"))
        assertFalse(YtLoginActivity.isMusicOrigin("https://music.youtube.com.attacker.test/"))
        assertFalse(YtLoginActivity.isMusicOrigin("http://music.youtube.com/"))
    }
    @Test fun credentialsSurviveRestartEncryptedAndBoundToProfile() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences("tv_secure_v1", Context.MODE_PRIVATE)
        val first = "instrumentation_profile_a"
        val second = "instrumentation_profile_b"
        try {
            val vault = TvSecureStore(context)
            val clear = "{\"token\":\"INSTRUMENTATION_SECRET\"}"
            vault.write(first, clear)
            assertEquals(clear, TvSecureStore(context).read(first))
            val encrypted = preferences.getString(first, null)!!
            assertFalse(encrypted.contains("INSTRUMENTATION_SECRET"))
            preferences.edit().putString(second, encrypted).commit()
            var rejected = false
            try { vault.read(second) } catch (_: Exception) { rejected = true }
            assertTrue("A copied encrypted bundle must not decrypt in another profile", rejected)
            vault.write(first, "{}")
            assertEquals("{}", vault.read(first))
        } finally { preferences.edit().remove(first).remove(second).commit() }
    }
}
