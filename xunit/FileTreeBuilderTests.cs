using System.IO;
using System.Linq;
using Ide.Core.Files;
using Xunit;

namespace Ide.Tests;

public class FileTreeBuilderTests
{
    [Fact]
    public void Build_Creates_Hierarchy()
    {
        var root = Path.Combine(Path.GetTempPath(), "tree-root");
        var entries = new[]
        {
            new BrowseEntry(Path.Combine(root, "a"), true, null),
            new BrowseEntry(Path.Combine(root, "a", "one.txt"), false, 3),
            new BrowseEntry(Path.Combine(root, "b"), true, null),
            new BrowseEntry(Path.Combine(root, "b", "two.txt"), false, 3),
        };
        var tree = FileTreeBuilder.Build(root, entries);

        Assert.Equal("tree-root", tree.Name);
        Assert.True(tree.IsDirectory);
        Assert.Equal(2, tree.Children.Count);
        var a = tree.Children.First(n => n.Name == "a");
        Assert.True(a.IsDirectory);
        Assert.Single(a.Children);
        Assert.Equal("one.txt", a.Children[0].Name);
    }
}

