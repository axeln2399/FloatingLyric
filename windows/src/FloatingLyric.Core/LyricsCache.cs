using System.Text.Json;
using System.Text.Json.Serialization;

namespace FloatingLyric.Core;

public interface ILyricsCache
{
    LyricsResult? Read(string trackId, DateTime now);
    void Write(LyricsResult result, string trackId, DateTime now);
    /// <summary>Forgets one track so the next lookup goes back to the network.
    /// Without this, a wrong or missing result stands for 24 hours.</summary>
    void Remove(string trackId);
}

public sealed class LyricsCache : ILyricsCache
{
    private readonly string _directory;

    public LyricsCache(string? directory = null)
    {
        _directory = directory ?? Path.Combine(Settings.AppDataDirectory, "lyrics");
        Directory.CreateDirectory(_directory);
    }

    private string PathFor(string trackId) =>
        Path.Combine(_directory, trackId.Replace('/', '_').Replace('\\', '_') + ".json");

    public LyricsResult? Read(string trackId, DateTime now)
    {
        try
        {
            var path = PathFor(trackId);
            if (!File.Exists(path)) return null;
            var entry = JsonSerializer.Deserialize<Entry>(File.ReadAllBytes(path));
            if (entry is null) return null;

            return entry.Kind switch
            {
                EntryKind.Synced => entry.Lines is null ? null : new LyricsResult.Synced(entry.Lines),
                EntryKind.Plain => entry.Text is null ? null : new LyricsResult.Plain(entry.Text),
                // Lyrics never change, so a hit is kept forever. A miss is not:
                // songs get added to LRCLIB.
                EntryKind.NotFound => now - entry.FetchedAt <= LyricsProvider.NegativeTtl
                    ? LyricsResult.None : null,
                _ => null,
            };
        }
        catch (Exception e) when (e is IOException or JsonException)
        {
            return null;
        }
    }

    public void Write(LyricsResult result, string trackId, DateTime now)
    {
        var entry = result switch
        {
            LyricsResult.Synced s => new Entry(EntryKind.Synced, s.Lines.ToList(), null, now),
            LyricsResult.Plain p => new Entry(EntryKind.Plain, null, p.Text, now),
            _ => new Entry(EntryKind.NotFound, null, null, now),
        };
        try { File.WriteAllBytes(PathFor(trackId), JsonSerializer.SerializeToUtf8Bytes(entry)); }
        catch (IOException) { }
    }

    public void Remove(string trackId)
    {
        try { File.Delete(PathFor(trackId)); } catch (IOException) { }
    }

    [JsonConverter(typeof(JsonStringEnumConverter))]
    private enum EntryKind { Synced, Plain, NotFound }

    private sealed record Entry(
        EntryKind Kind, List<LyricLine>? Lines, string? Text, DateTime FetchedAt);
}
