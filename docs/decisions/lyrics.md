# Lyrics

MusicGram searches LRCLIB when the user opens lyrics for an uncached track or starts a manual search. Search sends the song title and artist, or the user's entered keywords, to LRCLIB; it does not send audio or Telegram messages.

The user selects a result. The selected lyrics are stored in the app's private support directory against the track identity and can be displayed offline. Synchronized LRC timestamps follow the playback position; records without timestamps display plain lyrics.
