using System.Net;

namespace FloatingLyric.Core;

/// <summary>
/// Serves exactly one /callback request, then shuts down.
///
/// Windows has no equivalent of ASWebAuthenticationSession, so login opens the
/// user's browser and comes back to a loopback address — the flow the Mac app
/// keeps as its fallback.
/// </summary>
public static class CallbackListener
{
    public static async Task<Uri> WaitForCallbackAsync(int port, CancellationToken ct = default)
    {
        var listener = new HttpListener();
        listener.Prefixes.Add($"http://127.0.0.1:{port}/");

        try { listener.Start(); }
        catch (HttpListenerException) { throw new AppErrorException(new AppError.PortUnavailable()); }
        catch (ObjectDisposedException) { throw new AppErrorException(new AppError.PortUnavailable()); }

        try
        {
            using var registration = ct.Register(listener.Abort);
            var context = await listener.GetContextAsync();
            var url = context.Request.Url!;

            var ok = url.AbsolutePath == "/callback" &&
                     url.Query.Contains("code=", StringComparison.Ordinal);
            var body = ok
                ? "<h2>FloatingLyric is connected.</h2><p>You can close this tab.</p>"
                : "<h2>Login failed.</h2><p>Return to FloatingLyric and try again.</p>";

            var bytes = System.Text.Encoding.UTF8.GetBytes(
                $"<!doctype html><meta charset=utf-8><title>FloatingLyric</title>{body}");
            context.Response.ContentType = "text/html; charset=utf-8";
            context.Response.ContentLength64 = bytes.Length;
            await context.Response.OutputStream.WriteAsync(bytes, ct);
            context.Response.Close();

            return url;
        }
        catch (HttpListenerException)
        {
            throw new AppErrorException(new AppError.AuthCancelled());
        }
        finally
        {
            listener.Close();
        }
    }
}
