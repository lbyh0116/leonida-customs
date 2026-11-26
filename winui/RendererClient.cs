using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace VehicleStudio;

internal sealed class RendererClient : IDisposable
{
    private readonly TcpListener listener = new(IPAddress.Loopback, 0);
    private readonly CancellationTokenSource lifetime = new();
    private readonly SemaphoreSlim writeLock = new(1);
    private readonly ConcurrentDictionary<int, TaskCompletionSource<JsonElement>> requests = new();
    private Process? worker;
    private TcpClient? connection;
    private StreamWriter? writer;
    private int nextId;

    public int ProcessId => worker?.Id ?? 0;
    public event Action<JsonElement>? Notification;
    public event Action<string>? Disconnected;

    public async Task<JsonElement> StartAsync(string root)
    {
        var rtx = Path.Combine(root, "tools", "godot-rtx", "godot.windows.editor.x86_64.exe");
        var hasRtx = File.Exists(rtx);
        var engine = hasRtx
            ? rtx
            : Path.Combine(root, "tools", "godot", "Godot_v4.7.2-stable_win64.exe");
        if (!File.Exists(engine))
            throw new InvalidOperationException("找不到 Godot。请先运行项目的 setup.ps1。");

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(lifetime.Token);
        timeout.CancelAfter(TimeSpan.FromSeconds(20));
        var secret = Convert.ToHexString(RandomNumberGenerator.GetBytes(24));
        listener.Start(1);
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var log = Path.Combine(root, "work", hasRtx ? "winui-renderer-rtx.log" : "winui-renderer.log");
        var options = new ProcessStartInfo(engine)
        {
            WorkingDirectory = root,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        foreach (var arg in new[] { "--path", root, "--log-file", log, "--single-window", "--audio-driver", "Dummy", "--rendering-driver", "vulkan" })
            options.ArgumentList.Add(arg);
        options.ArgumentList.Add("res://preview-worker.tscn");
        options.ArgumentList.Add("--");
        options.ArgumentList.Add($"--studio-port={port}");
        options.ArgumentList.Add($"--studio-token={secret}");
        worker = Process.Start(options) ?? throw new InvalidOperationException("无法启动预览进程。");
        connection = await listener.AcceptTcpClientAsync(timeout.Token);
        listener.Stop();
        connection.NoDelay = true;
        var stream = connection.GetStream();
        writer = new StreamWriter(stream, new UTF8Encoding(false), leaveOpen: true) { AutoFlush = true };
        var reader = new StreamReader(stream, Encoding.UTF8, leaveOpen: true);
        try
        {
            var line = await reader.ReadLineAsync(timeout.Token);
            var hello = Parse(line ?? throw new IOException("预览进程没有返回启动信息。"));
            if (hello.GetProperty("event").GetString() != "hello" || hello.GetProperty("token").GetString() != secret)
                throw new InvalidOperationException("预览进程验证失败。");
            _ = ReadAsync(reader);
            return hello;
        }
        catch
        {
            reader.Dispose();
            throw;
        }
    }

    public async Task<JsonElement> RequestAsync(string command, object data)
    {
        var id = Interlocked.Increment(ref nextId);
        var response = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        requests[id] = response;
        try
        {
            await SendAsync(id, command, data);
            var reply = await response.Task.WaitAsync(lifetime.Token);
            if (!reply.GetProperty("ok").GetBoolean())
                throw new InvalidOperationException(reply.GetProperty("error").GetString());
            return reply;
        }
        finally
        {
            requests.TryRemove(id, out _);
        }
    }

    public Task PostAsync(string command, object data) => SendAsync(0, command, data);

    private async Task SendAsync(int id, string command, object data)
    {
        if (writer is null)
            throw new IOException("预览进程还未连接。");
        await writeLock.WaitAsync(lifetime.Token);
        try
        {
            var json = JsonSerializer.Serialize(new { id, command, data });
            await writer.WriteLineAsync(json.AsMemory(), lifetime.Token);
        }
        finally
        {
            writeLock.Release();
        }
    }

    private async Task ReadAsync(StreamReader reader)
    {
        using (reader)
        {
            Exception? failure = null;
            try
            {
                while (await reader.ReadLineAsync(lifetime.Token) is { } line)
                {
                    var message = Parse(line);
                    if (message.TryGetProperty("id", out var id))
                    {
                        if (requests.TryGetValue(id.GetInt32(), out var response))
                            response.TrySetResult(message);
                    }
                    else
                    {
                        Notification?.Invoke(message);
                    }
                }
            }
            catch (Exception ex) when (ex is IOException or OperationCanceledException or FormatException or JsonException or ObjectDisposedException)
            {
                failure = ex;
            }

            if (lifetime.IsCancellationRequested)
                return;
            foreach (var request in requests.Values)
                request.TrySetException(new IOException("预览进程已断开。", failure));
            Disconnected?.Invoke("预览进程已断开。可关闭并重新启动预览器。");
        }
    }

    private static JsonElement Parse(string line)
    {
        using var document = JsonDocument.Parse(line);
        return document.RootElement.Clone();
    }

    public async ValueTask CloseAsync()
    {
        try
        {
            if (writer is not null && worker is { HasExited: false })
            {
                using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                await PostAsync("shutdown", new { }).WaitAsync(timeout.Token);
                await worker.WaitForExitAsync(timeout.Token);
            }
        }
        catch (Exception ex) when (ex is IOException or OperationCanceledException or InvalidOperationException or ObjectDisposedException)
        {
        }
        finally
        {
            Dispose();
        }
    }

    public void Dispose()
    {
        lifetime.Cancel();
        listener.Stop();
        connection?.Dispose();
        if (worker is { HasExited: false })
        {
            try { worker.Kill(entireProcessTree: true); }
            catch (InvalidOperationException) { }
        }
        worker?.Dispose();
        worker = null;
    }
}
