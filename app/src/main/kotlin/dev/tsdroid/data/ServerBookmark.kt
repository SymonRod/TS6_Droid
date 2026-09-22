package dev.tsdroid.data

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.longOrNull

@Serializable
data class ServerBookmark(
    @SerialName("name") val name: String = "",
    @SerialName("address") val address: String = "",
    @SerialName("nickname") val nickname: String = "",
    @SerialName("password") val password: String? = null,
    @SerialName("channel") val channel: String? = null,
    @SerialName("serverName") val serverName: String? = null,
    @SerialName("iconId")
    @Serializable(with = LenientLongSerializer::class)
    val iconId: Long = 0,
)

/**
 * Reads a Long from either a JSON number or a JSON string.
 *
 * The legacy hand-rolled serializer quoted every value, so on-device data
 * written before M0 stores e.g. `"iconId":"0"` instead of `"iconId":0`.
 */
internal object LenientLongSerializer : KSerializer<Long> {
    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("LenientLong")

    override fun serialize(encoder: Encoder, value: Long) {
        encoder.encodeLong(value)
    }

    override fun deserialize(decoder: Decoder): Long {
        val element = (decoder as? JsonDecoder)?.decodeJsonElement()
            ?: return decoder.decodeLong()
        return (element as? JsonPrimitive)?.longOrNull
            ?: element.toString().toLongOrNull()
            ?: 0L
    }
}

/**
 * Key used to match the same bookmark across local list and imports.
 * Today this is the address; M2 keeps this rule with `server_uid`
 * preferred once the field lands on [ServerBookmark].
 */
internal val ServerBookmark.matchKey: String
    get() = address
