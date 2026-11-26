using System.Buffers;
using System.Buffers.Binary;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Runtime.InteropServices;
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
    public const int MaxFramePixels = 7680 * 4320;
    public event Action<JsonElement>? Notification;
    public event Action<PreviewFrame>? FrameReceived;
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
        var prefix = new byte[4];
        var hello = await ReadHeaderAsync(stream, prefix, timeout.Token);
        if (hello.GetProperty("event").GetString() != "hello" || hello.GetProperty("token").GetString() != secret)
            throw new InvalidOperationException("预览进程验证失败。");
        _ = Task.Run(() => ReadAsync(stream, prefix));
        return hello;
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

    private async Task ReadAsync(NetworkStream stream, byte[] prefix)
    {
        Exception? failure = null;
        try
        {
            while (!lifetime.IsCancellationRequested)
            {
                var message = await ReadHeaderAsync(stream, prefix, lifetime.Token);
                if (message.TryGetProperty("id", out var id))
                {
                    if (requests.TryGetValue(id.GetInt32(), out var response))
                        response.TrySetResult(message);
                }
                else if (message.GetProperty("event").GetString() == "frame")
                {
                    await ReadFrameAsync(stream, message);
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

    private static async Task<JsonElement> ReadHeaderAsync(NetworkStream stream, byte[] prefix, CancellationToken token)
    {
        await stream.ReadExactlyAsync(prefix, token);
        var length = BinaryPrimitives.ReadInt32LittleEndian(prefix);
        if (length is < 2 or > (4 << 20))
            throw new IOException("预览进程发送了无效的消息长度。");
        var header = new byte[length];
        await stream.ReadExactlyAsync(header, token);
        using var document = JsonDocument.Parse(header);
        return document.RootElement.Clone();
    }

    private async Task ReadFrameAsync(NetworkStream stream, JsonElement message)
    {
        var width = message.GetProperty("width").GetInt32();
        var height = message.GetProperty("height").GetInt32();
        if (width is < 8 or > 16384 || height is < 8 or > 16384 || (long)width * height > MaxFramePixels)
            throw new IOException("预览进程发送了无效的画面尺寸。");
        var frame = new PreviewFrame(width, height);
        try
        {
            await stream.ReadExactlyAsync(frame.Pixels, lifetime.Token);
            ConvertToBgra(frame.Pixels.Span);
            if (FrameReceived is { } handler)
            {
                handler(frame);
                return;
            }
        }
        catch
        {
            frame.Dispose();
            throw;
        }
        frame.Dispose();
    }

    private static void ConvertToBgra(Span<byte> pixels)
    {
        foreach (ref uint pixel in MemoryMarshal.Cast<byte, uint>(pixels))
            pixel = (pixel & 0x0000FF00u) | ((pixel & 0x00FF0000u) >> 16) | ((pixel & 0xFFu) << 16) | 0xFF000000u;
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

internal sealed class PreviewFrame(int width, int height) : IDisposable
{
    private readonly byte[] buffer = ArrayPool<byte>.Shared.Rent(width * height * 4);
    public int Width { get; } = width;
    public int Height { get; } = height;
    public Memory<byte> Pixels => buffer.AsMemory(0, Width * Height * 4);

    public void Dispose() => ArrayPool<byte>.Shared.Return(buffer);
}
