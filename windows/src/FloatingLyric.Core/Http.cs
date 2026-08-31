using System.Net;

namespace FloatingLyric.Core;

public sealed record HttpResponse(int Status, byte[] Body, IReadOnlyDictionary<string, string> Headers)
{
    public string Text => System.Text.Encoding.UTF8.GetString(Body);
}

/// <summary>The seam every network test hangs off.</summary>
public interface IHttpClient
{
    Task<HttpResponse> SendAsync(HttpRequestMessage request, CancellationToken ct = default);
}

public sealed class RealHttpClient(HttpClient? client = null) : IHttpClient
{
    private readonly HttpClient _client = client ?? new HttpClient
    {
        Timeout = TimeSpan.FromSeconds(20),
    };

    public async Task<HttpResponse> SendAsync(HttpRequestMessage request, CancellationToken ct = default)
    {
        try
        {
            using var response = await _client.SendAsync(request, ct);
            var body = await response.Content.ReadAsByteArrayAsync(ct);
            var headers = response.Headers
                .Concat(response.Content.Headers)
                .ToDictionary(h => h.Key, h => string.Join(", ", h.Value),
                              StringComparer.OrdinalIgnoreCase);
            return new HttpResponse((int)response.StatusCode, body, headers);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException)
        {
            throw new AppErrorException(new AppError.Network(e.Message));
        }
    }
}
