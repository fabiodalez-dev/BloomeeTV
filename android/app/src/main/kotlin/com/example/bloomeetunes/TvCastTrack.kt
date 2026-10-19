package ls.bloomee.musicplayer

import java.net.URI

/** Cast-facing values, without local files or credential-bearing artwork URLs. */
data class TvCastTrack(val title: String, val artist: String, val album: String, val image: String?) {
    companion object {
        fun create(title: String?, artist: String?, album: String?, image: String?): TvCastTrack =
            TvCastTrack(title.orEmpty(), artist.orEmpty(), album.orEmpty(), safeImage(image))

        private fun safeImage(value: String?): String? = try {
            val uri = URI(value ?: "")
            if (uri.scheme !in listOf("http", "https") || uri.host.isNullOrBlank() ||
                uri.userInfo != null || Regex("(?i)(?:^|&)(?:api[_-]?key|token|password|cookie)=")
                    .containsMatchIn(uri.rawQuery.orEmpty())) null else value
        } catch (_: Exception) { null }
    }
}
