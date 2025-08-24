using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Ide.Core.Indexing;
using Xunit;

namespace Ide.Tests;

public class IndexerTests
{
    private static string CreateTempTree()
    {
        var root = Path.Combine(Path.GetTempPath(), "ide-index-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        Directory.CreateDirectory(Path.Combine(root, "src"));
        Directory.CreateDirectory(Path.Combine(root, "bin"));
        File.WriteAllText(Path.Combine(root, "src", "a.cs"), "class A { void M() { var alpha = 1; } }\n// beta line\n", new UTF8Encoding(false));
        File.WriteAllText(Path.Combine(root, "src", "b.txt"), "gamma delta ALPHA\n", new UTF8Encoding(false));
        File.WriteAllBytes(Path.Combine(root, "bin", "app.dll"), new byte[] { 0x4D, 0x5A, 0x00, 0x01 });
        return root;
    }

    [Fact]
    public async Task Indexer_BuildAndQuery_FindsTokens()
    {
        var root = CreateTempTree();
        using var idx = new LexicalIndexer();
        await idx.BuildAsync(root, includeGlobs: new[] { "**/*" }, excludeGlobs: new[] { "bin/**" });

        var res1 = await idx.QueryAsync("alpha", limit: 10);
        Assert.True(res1.Count >= 2);
        Assert.All(res1, r => Assert.DoesNotContain("bin/", r.File.Replace('\\', '/')));

        var res2 = await idx.QueryAsync("beta");
        Assert.Single(res2);
        Assert.Contains("beta", res2[0].Preview);
    }

    [Fact]
    public async Task Indexer_Limit_Enforced()
    {
        var root = CreateTempTree();
        // Create multiple files with same token to exceed limit
        for (int i = 0; i < 20; i++)
        {
            File.WriteAllText(Path.Combine(root, $"file{i}.txt"), "token here\n", new UTF8Encoding(false));
        }
        using var idx = new LexicalIndexer();
        await idx.BuildAsync(root);
        var res = await idx.QueryAsync("token", limit: 5);
        Assert.Equal(5, res.Count);
    }

    [Fact]
    public async Task Indexer_Respects_Globs()
    {
        var root = CreateTempTree();
        using var idx = new LexicalIndexer();
        await idx.BuildAsync(root, includeGlobs: new[] { "src/**/*.cs" });
        var resAlpha = await idx.QueryAsync("alpha", 100);
        // Only a.cs lines should appear; not b.txt
        Assert.All(resAlpha, r => Assert.EndsWith("a.cs", Path.GetFileName(r.File)));
    }
}
