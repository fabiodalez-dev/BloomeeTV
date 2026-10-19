package ls.bloomee.musicplayer

import org.junit.Assert.*
import org.junit.Test

class TvCastTrackTest {
    @Test fun mapsMusicValuesAndPublicArtwork() {
        val track = TvCastTrack.create("Title", "Artist", "Album", "https://images.test/cover.jpg")
        assertEquals("Title", track.title)
        assertEquals("Artist", track.artist)
        assertEquals("Album", track.album)
        assertNotNull(track.image)
    }
    @Test fun blocksPrivateFilesAndArtworkCredentials() {
        for (url in listOf("file:///data/cover.jpg", "https://user:pass@test/cover",
            "https://test/cover?ApiKey=private", "https://test/cover?token=private", "invalid")) {
            assertNull(TvCastTrack.create(null, null, null, url).image)
        }
        assertNotNull(TvCastTrack.create(null, null, null, "http://test/cover/opaque-capability").image)
    }
}
