using System.Text;
using FloatingLyric.Core;

namespace FloatingLyric.Core.Tests;

public sealed class StubHttpClient : IHttpClient
{
    public Queue<HttpResponse> Responses { get; } = new();
    public Exception? ExceptionToThrow { get; set; }
    public List<HttpRequestMessage> Recorded { get; } = [];

    public Task<HttpResponse> SendAsync(HttpRequestMessage request, CancellationToken ct = default)
    {
        Recorded.Add(request);
        if (ExceptionToThrow is { } e) throw e;
        return Task.FromResult(Responses.Count > 0
            ? Responses.Dequeue()
            : new HttpResponse(200, [], new Dictionary<string, string>()));
    }

    public StubHttpClient Enqueue(params HttpResponse[] responses)
    {
        foreach (var r in responses) Responses.Enqueue(r);
        return this;
    }
}

public static class Responses
{
    public static HttpResponse Json(string body, int status = 200) => new(
        status, Encoding.UTF8.GetBytes(body),
        new Dictionary<string, string> { ["Content-Type"] = "application/json" });

    public static HttpResponse Status(int status, params (string, string)[] headers) => new(
        status, [], headers.ToDictionary(h => h.Item1, h => h.Item2));
}

public sealed class MemoryLyricsCache : ILyricsCache
{
    public Dictionary<string, (LyricsResult Result, DateTime At)> Stored { get; } = new();

    public LyricsResult? Read(string trackId, DateTime now)
    {
        if (!Stored.TryGetValue(trackId, out var entry)) return null;
        if (entry.Result is LyricsResult.NotFound &&
            now - entry.At > LyricsProvider.NegativeTtl) return null;
        return entry.Result;
    }

    public void Write(LyricsResult result, string trackId, DateTime now) =>
        Stored[trackId] = (result, now);

    public void Remove(string trackId) => Stored.Remove(trackId);
}
