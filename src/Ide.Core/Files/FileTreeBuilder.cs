using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;

namespace Ide.Core.Files;

public sealed class FileTreeNode
{
    public string Name { get; }
    public string Path { get; }
    public bool IsDirectory { get; }
    public ObservableCollection<FileTreeNode> Children { get; } = new();

    public FileTreeNode(string name, string path, bool isDirectory)
    {
        Name = name;
        Path = path;
        IsDirectory = isDirectory;
    }
}

public static class FileTreeBuilder
{
    public static FileTreeNode Build(string root, IEnumerable<BrowseEntry> entries)
    {
        if (string.IsNullOrWhiteSpace(root))
            throw new ArgumentException("Root required", nameof(root));
        if (entries == null)
            throw new ArgumentNullException(nameof(entries));

        var fullRoot = Path.GetFullPath(root);
        var rootNode = new FileTreeNode(Path.GetFileName(fullRoot.TrimEnd(Path.DirectorySeparatorChar)), fullRoot, true);
        var map = new Dictionary<string, FileTreeNode>(StringComparer.OrdinalIgnoreCase)
        {
            [fullRoot] = rootNode
        };

        foreach (var entry in entries.OrderBy(e => e.Path, StringComparer.OrdinalIgnoreCase))
        {
            var parentPath = Path.GetDirectoryName(entry.Path) ?? fullRoot;
            if (!map.TryGetValue(parentPath, out var parent))
            {
                var stack = new Stack<string>();
                var p = parentPath;
                while (!map.ContainsKey(p) && p.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
                {
                    stack.Push(p);
                    p = Path.GetDirectoryName(p)!;
                }
                var current = map[p];
                while (stack.Count > 0)
                {
                    var dir = stack.Pop();
                    var node = new FileTreeNode(Path.GetFileName(dir), dir, true);
                    current.Children.Add(node);
                    map[dir] = node;
                    current = node;
                }
                parent = current;
            }
            var child = new FileTreeNode(Path.GetFileName(entry.Path), entry.Path, entry.IsDirectory);
            parent.Children.Add(child);
            if (entry.IsDirectory)
            {
                map[entry.Path] = child;
            }
        }

        return rootNode;
    }
}

