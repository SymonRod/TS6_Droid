package dev.tsdroid.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BookmarkStoreTest {

    @Test
    fun `round-trip preserves special chars`() {
        val original = listOf(
            ServerBookmark(
                name = "My, \"quoted\": server",
                address = "voice.example.com:9987",
                nickname = "nick, with: \"chars\"",
                password = "p@ss,\"word:123",
                channel = "Lobby, \"VIP\": room",
                serverName = "srv:name, \"x\"",
                iconId = 42L,
            ),
            ServerBookmark(name = "plain", address = "127.0.0.1", nickname = "n"),
        )

        val parsed = BookmarkStore.parseBookmarks(BookmarkStore.serializeBookmarks(original))

        assertEquals(original, parsed)
    }

    @Test
    fun `legacy null strings read as null`() {
        val legacy = """[{"name":"a","address":"b","nickname":"c","password":"null","channel":"null","serverName":"null","iconId":"7"}]"""

        val parsed = BookmarkStore.parseBookmarks(legacy)

        assertEquals(1, parsed.size)
        assertNull(parsed[0].password)
        assertNull(parsed[0].channel)
        assertNull(parsed[0].serverName)
        assertEquals(7L, parsed[0].iconId)
    }

    @Test
    fun `corrupt json returns empty list`() {
        assertEquals(emptyList<ServerBookmark>(), BookmarkStore.parseBookmarks("[{broken"))
        assertEquals(emptyList<ServerBookmark>(), BookmarkStore.parseBookmarks("not json at all"))
        assertEquals(emptyList<ServerBookmark>(), BookmarkStore.parseBookmarks("""{"name":"x"}"""))
        assertEquals(emptyList<ServerBookmark>(), BookmarkStore.parseBookmarks(""))
    }

    @Test
    fun `match key is address-based`() {
        val a = ServerBookmark(name = "one", address = "voice.example.com", nickname = "n1")
        val b = ServerBookmark(name = "two", address = "voice.example.com", nickname = "n2")
        val c = ServerBookmark(name = "three", address = "other.example.com", nickname = "n3")

        assertEquals(a.matchKey, b.matchKey)
        assertEquals("voice.example.com", a.matchKey)
        assert(a.matchKey != c.matchKey)
    }
}
