using System;

namespace ide;

public interface ITerminalBackend : IDisposable
{
    event Action<string>? Output;
    event Action<string>? Error;

    bool IsRunning { get; }

    void Start();
    void Stop();
    void WriteLine(string text);
}
