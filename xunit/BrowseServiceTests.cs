using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Ide.Core.Files;
using Xunit;

namespace Ide.Tests;

public class BrowseServiceTests
{
    private static string CreateTempTree()
    {
        var root = Path.Combine(Path.GetTempPath(), "ide-browse-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        Directory.CreateDirectory(Path.Combine(root, "a"));
        Directory.CreateDirectory(Path.Combine(root, "b", "c"));

        File.WriteAllText(Path.Combine(root, "a", "one.txt"), "one", new UTF8Encoding(false));
        File.WriteAllBytes(Path.Combine(root, "a", "two.bin"), new byte[] { 1, 2, 3 });
        File.WriteAllText(Path.Combine(root, "readme.md"), "readme", new UTF8Encoding(false));
        File.WriteAllBytes(Path.Combine(root, "image.png"), new byte[] { 137, 80, 78, 71 });
        File.WriteAllText(Path.Combine(root, "b", "c", "deep.txt"), "deep", new UTF8Encoding(false));
        return root;
    }

    [Fact]
    public async Task Browse_Depth_Works()
    {
        var root = CreateTempTree();
        var svc = new BrowseService();
        var entries = await svc.BrowseAsync(root, maxDepth: 1, maxEntries: 100);
        var rels = entries.Select(e => Path.GetRelativePath(root, e.Path).Replace('\\', '/')).ToArray();

        Assert.Contains("a", rels);
        Assert.Contains("b", rels);
        Assert.Contains("readme.md", rels);
        Assert.Contains("image.png", rels);
        Assert.Contains("a/one.txt", rels);
        Assert.Contains("a/two.bin", rels);
        Assert.DoesNotContain("b/c/deep.txt", rels); // beyond depth
    }

    [Fact]
    public async Task Browse_Includes_Excludes_Work()
    {
        var root = CreateTempTree();
        var svc = new BrowseService();
        var entries = await svc.BrowseAsync(root,
            includeGlobs: new[] { "**/*.txt" },
            excludeGlobs: new[] { "b/**" },
            maxDepth: 10,
            maxEntries: 100);
        var rels = entries.Select(e => Path.GetRelativePath(root, e.Path).Replace('\\', '/')).OrderBy(x => x).ToArray();

        Assert.Contains("a/one.txt", rels);
        Assert.DoesNotContain("b/c/deep.txt", rels);
        Assert.DoesNotContain("readme.md", rels);
        Assert.All(rels, r => Assert.EndsWith(".txt", r));
    }

    [Fact]
    public async Task Browse_MaxEntries_Caps()
    {
        var root = CreateTempTree();
        var svc = new BrowseService();
        var entries = await svc.BrowseAsync(root, maxDepth: 10, maxEntries: 2);
        Assert.Equal(2, entries.Count);
    }

    [Fact]
    public async Task Browse_Size_ForFiles_Set()
    {
        var root = CreateTempTree();
        var svc = new BrowseService();
        var entries = await svc.BrowseAsync(root, maxDepth: 1, maxEntries: 100);
        var readme = entries.FirstOrDefault(e => Path.GetFileName(e.Path) == "readme.md");
        Assert.NotNull(readme);
        Assert.False(readme!.IsDirectory);
        Assert.Equal(6, readme.SizeBytes); // "readme" length
    }
}
