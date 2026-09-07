package dev.tslib;

/**
 * A screen sharing stream advertised on the server (immutable snapshot).
 *
 * <p>A stream is announced before its details are known, so every metadata
 * field is nullable: {@code null} means the server has not sent it yet, not
 * that the value is zero. {@link Client#requestStreamInfo(int)} asks for the
 * missing pieces.
 */
public class Stream {
    /** Client ID of the sharer. */
    public final int ownerId;
    /** Stream UUID, unique per owner. */
    public final String id;
    public final String name;
    public final Integer type;
    public final Integer access;
    public final Integer mode;
    public final Integer bitrate;
    public final Integer viewerLimit;
    public final Integer viewerCount;
    public final Boolean audio;

    public Stream(int ownerId, String id, String name, Integer type,
                  Integer access, Integer mode, Integer bitrate,
                  Integer viewerLimit, Integer viewerCount, Boolean audio) {
        this.ownerId = ownerId;
        this.id = id;
        this.name = name;
        this.type = type;
        this.access = access;
        this.mode = mode;
        this.bitrate = bitrate;
        this.viewerLimit = viewerLimit;
        this.viewerCount = viewerCount;
        this.audio = audio;
    }

    @Override
    public String toString() {
        return "Stream(owner=" + ownerId + ", id='" + id + "', name='" + name + "')";
    }
}
