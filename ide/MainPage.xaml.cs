using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Text;
using System.IO;
using Ide.Core.Files;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Maui.Storage;

namespace ide;

public partial class MainPage : ContentPage
{
    // Explorer/Editor state
    private readonly ObservableCollection<FileTreeNode> _nodes = new();
    private string? _currentRoot;
    private string? _currentFile;

    // Persistent terminal state
    private readonly ITerminalBackend _terminal;
    private bool _updatingTerminal; // guard to avoid recursive TextChanged
    private int _termLockLen; // text length beyond which user can edit
    private readonly StringBuilder _termInput = new(); // current input line buffer

    private readonly IBrowseService _browseService;
    private readonly IFileService _fileService;

    public MainPage(IBrowseService browseService, IFileService fileService, ITerminalBackend terminal)
    {
        InitializeComponent();
        FileTree.ItemsSource = _nodes;
        _browseService = browseService;
        _fileService = fileService;
        _terminal = terminal;
        _terminal.Output += AppendTerminal;
        _terminal.Error += AppendTerminal;
        SetStatus("Ready");
    }

    public static MainPage Create() => App.Current.Services.GetRequiredService<MainPage>();

    private void SetStatus(string text)
    {
        StatusLabel.Text = text;
    }

    protected override void OnAppearing()
    {
        base.OnAppearing();
        EnsureTerminalStarted();
    }

    protected override void OnDisappearing()
    {
        base.OnDisappearing();
        StopTerminal();
    }

    private async Task BrowseRootAsync(string root)
    {
        try
        {
            _currentRoot = root;
            var browse = await _browseService.BrowseAsync(root, maxDepth: 20, maxEntries: 5000);
            var tree = FileTreeBuilder.Build(root, browse);
            _nodes.Clear();
            _nodes.Add(tree);
        }
        catch (Exception ex)
        {
            AppendTerminal($"[explorer error] {ex.Message}\n");
        }
    }

    private async void OnFileSelected(object? sender, SelectionChangedEventArgs e)
    {
        try
        {
            var node = e.CurrentSelection?.FirstOrDefault() as FileTreeNode;
            if (node == null || node.IsDirectory) return;
            _currentFile = node.Path;
            var rr = await _fileService.ReadFilesAsync(new[] { node.Path }, maxBytes: 1024 * 1024);
            var r = rr.FirstOrDefault();
            if (r is not null && r.Ok)
            {
                EditorView.Text = r.Content ?? string.Empty;
            }
            else
            {
                AppendTerminal($"[open error] {r?.Error ?? "unknown"}\n");
            }
        }
        catch (Exception ex)
        {
            AppendTerminal($"[open error] {ex.Message}\n");
        }
    }

    // File menu handlers
    private async void OnOpenFileMenuClicked(object? sender, EventArgs e)
    {
        try
        {
            var result = await FilePicker.Default.PickAsync(new PickOptions
            {
                PickerTitle = "Open File"
            });
            if (result == null) return;
            var path = result.FullPath;
            _currentFile = path;
            await BrowseRootAsync(Path.GetDirectoryName(path)!);
            var rr = await _fileService.ReadFilesAsync(new[] { path }, maxBytes: 1024 * 1024);
            var r = rr.FirstOrDefault();
            if (r is not null && r.Ok)
            {
                EditorView.Text = r.Content ?? string.Empty;
            }
            else
            {
                AppendTerminal($"[open error] {r?.Error ?? "unknown"}\n");
            }
        }
        catch (Exception ex)
        {
            AppendTerminal($"[open error] {ex.Message}\n");
        }
    }

    private async void OnOpenProjectMenuClicked(object? sender, EventArgs e)
    {
        try
        {
            var result = await FolderPicker.Default.PickAsync();
            if (result == null) return;
            var root = result.Folder?.Path;
            if (string.IsNullOrEmpty(root)) return;
            await BrowseRootAsync(root);
        }
        catch (Exception ex)
        {
            AppendTerminal($"[explorer error] {ex.Message}\n");
        }
    }

    private async void OnSaveFileMenuClicked(object? sender, EventArgs e)
    {
        try
        {
            if (string.IsNullOrEmpty(_currentFile)) return;
            var wr = await _fileService.WriteFilesAsync(new[] { new FileWrite(_currentFile!, EditorView.Text ?? string.Empty) });
            var r = wr.FirstOrDefault();
            if (r is not null && r.Ok)
            {
                AppendTerminal($"[saved] {_currentFile}\n");
            }
            else
            {
                AppendTerminal($"[save error] {r?.Error ?? "unknown"}\n");
            }
        }
        catch (Exception ex)
        {
            AppendTerminal($"[save error] {ex.Message}\n");
        }
    }

    private async void OnSaveProjectMenuClicked(object? sender, EventArgs e)
    {
        // For now, save the active file. Later, iterate open editors/tabs.
        await Task.Run(() => OnSaveFileMenuClicked(sender!, e));
    }

    private void EnsureTerminalStarted()
    {
        try
        {
            if (!_terminal.IsRunning)
            {
                _terminal.Start();
            }
        }
        catch (Exception ex)
        {
            AppendTerminal($"[terminal error] {ex.Message}\n");
        }
    }

    private void StopTerminal()
    {
        try
        {
            if (_terminal.IsRunning)
            {
                _terminal.Stop();
            }
        }
        catch (Exception ex)
        {
            AppendTerminal($"[terminal error] {ex.Message}\n");
        }
    }

    // Shell output/error are handled via ITerminalBackend events

    private void AppendTerminal(string text)
    {
        Microsoft.Maui.ApplicationModel.MainThread.BeginInvokeOnMainThread(() =>
        {
            _updatingTerminal = true;
            var cur = TerminalView.Text ?? string.Empty;
            // Insert output at the lock position so that process output appears before any user-typed input.
            var head = _termLockLen <= cur.Length ? cur.Substring(0, _termLockLen) : cur;
            var tail = _termLockLen <= cur.Length ? cur.Substring(_termLockLen) : string.Empty;
            TerminalView.Text = head + text + tail;
            // Advance lock by inserted text length; keep cursor at end to continue typing.
            _termLockLen = head.Length + text.Length;
            TerminalView.CursorPosition = TerminalView.Text.Length;
            _updatingTerminal = false;
        });
    }

    // TerminalView TextChanged: accept only appends after _termLockLen; send lines on Enter
    private void OnTerminalTextChanged(object? sender, TextChangedEventArgs e)
    {
        if (_updatingTerminal) return;
        var oldText = e.OldTextValue ?? string.Empty;
        var newText = e.NewTextValue ?? string.Empty;
        if (newText.Length < _termLockLen)
        {
            // Disallow editing before the lock
            _updatingTerminal = true;
            TerminalView.Text = oldText;
            TerminalView.CursorPosition = _termLockLen;
            _updatingTerminal = false;
            return;
        }
        // Compute tail after lock and handle complete lines
        var tail = newText.Substring(_termLockLen);
        if (tail.Length == 0)
        {
            // Nothing after lock; clear buffer
            _termInput.Clear();
            return;
        }

        // Normalize CRLF to LF in processing, but do not mutate editor text here
        var normalized = tail.Replace("\r\n", "\n").Replace('\r', '\n');
        int lastNL = normalized.LastIndexOf('\n');
        if (lastNL >= 0)
        {
            // There are complete lines to send (everything up to lastNL)
            var toProcess = normalized.Substring(0, lastNL);
            var lines = toProcess.Split('\n');
            foreach (var line in lines)
            {
                try
                {
                    if (!_terminal.IsRunning)
                    {
                        AppendTerminal("[terminal] not started\n");
                        continue;
                    }
                    _terminal.WriteLine(line);
                }
                catch (Exception ex)
                {
                    AppendTerminal($"[terminal error] {ex.Message}\n");
                }
            }
            // Remove the submitted portion from the editor to avoid double-echo (shell will echo it)
            var submittedLenInTail = tail.Substring(0, Math.Min(lastNL + 1, tail.Length)).Length;
            var head = (TerminalView.Text ?? string.Empty).Substring(0, _termLockLen);
            var remainder = tail.Substring(Math.Min(lastNL + 1, tail.Length));
            _updatingTerminal = true;
            TerminalView.Text = head + remainder;
            TerminalView.CursorPosition = (TerminalView.Text?.Length ?? 0);
            _updatingTerminal = false;
            // Lock remains unchanged since we removed text after the lock
            _termInput.Clear();
            _termInput.Append(remainder);
        }
        else
        {
            // No complete line yet: update buffer to match editor tail (handle arbitrary edits)
            _termInput.Clear();
            _termInput.Append(tail);
        }
    }
}

