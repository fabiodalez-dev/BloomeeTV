package ls.bloomee.musicplayer

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class TvSecureStore(context: Context) {
    private val prefs = context.getSharedPreferences("tv_secure_v1", Context.MODE_PRIVATE)
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("bloomeetv-vault-v1", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("bloomeetv-vault-v1", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }
    fun read(profile: String): String? {
        val value = prefs.getString(profile, null) ?: return null
        val fields = value.split(":")
        require(fields.size == 2)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(fields[0], Base64.NO_WRAP)))
        cipher.updateAAD(profile.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(Base64.decode(fields[1], Base64.NO_WRAP)), Charsets.UTF_8)
    }
    fun write(profile: String, value: String) {
        require(profile.matches(Regex("[a-zA-Z0-9_-]{1,64}")))
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(profile.toByteArray(Charsets.UTF_8))
        val encrypted = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
        check(prefs.edit().putString(profile, encrypted).commit()) { "Cannot persist credentials" }
    }
}
