using System.Collections.Concurrent;
using System.Text;
using Ide.Core.Searching;
using Microsoft.Extensions.FileSystemGlobbing;
using Microsoft.Extensions.FileSystemGlobbing.Abstractions;

namespace Ide.Tests;

public class CodeSearchServiceTests
{
    private static string CreateTempDir()
    {
        var dir = Path.Combine(Path.GetTempPath(), "CodeSearchServiceTests_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    [Fact]
    public async Task LiteralSearch_FindsMatch_WithGlob()
    {
        var root = CreateTempDir();
        try
        {
            var csPath = Path.Combine(root, "a.cs");
            await File.WriteAllTextAsync(csPath, "// Hello Search\nclass A { string s = \"search needle\"; }");

            var txtPath = Path.Combine(root, "b.txt");
            await File.WriteAllTextAsync(txtPath, "this should be ignored by include glob");

            ICodeSearchService svc = new CodeSearchService();
            var results = await svc.SearchAsync(root, "search", SearchKind.Literal, includeGlobs: new[] { "**/*.cs" }, limit: 10);

            Assert.NotEmpty(results);
            Assert.Contains(results, m => m.File.EndsWith("a.cs", StringComparison.Ordinal));
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch { /* ignore */ }
        }
    }

    [Fact]
    public async Task RegexSearch_IsCaseInsensitive()
    {
        var root = CreateTempDir();
        try
        {
            var file = Path.Combine(root, "c.cs");
            await File.WriteAllTextAsync(file, "// token FOO123 and foo456\n");

            ICodeSearchService svc = new CodeSearchService();
            var results = await svc.SearchAsync(root, "foo\\d+", SearchKind.Regex, includeGlobs: new[] { "**/*.cs" }, limit: 10);

            Assert.True(results.Count >= 2);
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch { }
        }
    }

    [Fact]
    public async Task Respects_Limit()
    {
        var root = CreateTempDir();
        try
        {
            var file = Path.Combine(root, "many.cs");
            var sb = new StringBuilder();
            for (int i = 0; i < 100; i++) sb.AppendLine($"line {i} needle");
            await File.WriteAllTextAsync(file, sb.ToString());

            ICodeSearchService svc = new CodeSearchService();
            var results = await svc.SearchAsync(root, "needle", SearchKind.Literal, includeGlobs: new[] { "**/*.cs" }, limit: 3);

            Assert.True(results.Count <= 3);
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch { }
        }
    }

    [Fact]
    public async Task Skips_Binary_ByNullSniff()
    {
        var root = CreateTempDir();
        try
        {
            var bin = Path.Combine(root, "raw.bin");
            await File.WriteAllBytesAsync(bin, new byte[] { 0, 1, 2, 0, 3, 4 });

            ICodeSearchService svc = new CodeSearchService();
            var results = await svc.SearchAsync(root, "\u0001", SearchKind.Literal, includeGlobs: new[] { "**/*" }, limit: 10);

            Assert.Empty(results);
        }
        finally
        {
            try { Directory.Delete(root, recursive: true); } catch { }
        }
    }

    [Fact]
    public async Task Helpers_BuildMatcher_Skip_SearchFile()
    {
        var root = CreateTempDir();
        try
        {
            var file = Path.Combine(root, "a.cs");
            await File.WriteAllTextAsync(file, "needle line\n");
            var matcher = CodeSearchService.BuildMatcher(new[] { "**/*.cs" }, null);
            var res = matcher.Execute(new DirectoryInfoWrapper(new DirectoryInfo(root)));
            Assert.Single(res.Files);
            Assert.False(await CodeSearchService.ShouldSkipFileAsync(file, default));
            var bag = new ConcurrentBag<SearchMatch>();
            await CodeSearchService.SearchFileAsync(file, root, "needle", SearchKind.Literal, 5, bag, default);
            Assert.Single(bag);
        }
        finally
        {
            try { Directory.Delete(root, true); } catch { }
        }
    }
}
