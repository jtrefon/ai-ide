using System.IO;
using Ide.Core.Files;
using Ide.Core.Indexing;
using Ide.Core.Searching;
using Ide.Core.Utils;

namespace Ide.Tests;

public class BinaryExtensionsTests
{
    [Fact]
    public async Task CentralList_AffectsAllServices()
    {
        const string ext = ".foo";
        var dir = Path.Combine(Path.GetTempPath(), "ide-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        var path = Path.Combine(dir, "a" + ext);
        await File.WriteAllTextAsync(path, "hi");
        var idx = new LexicalIndexer();
        Assert.False(await FileService.IsBinaryAsync(path, 10, default));
        Assert.False(await idx.ShouldSkipFileAsync(path, default));
        Assert.False(await CodeSearchService.ShouldSkipFileAsync(path, default));
        BinaryExtensions.Set.Add(ext);
        try
        {
            Assert.True(await FileService.IsBinaryAsync(path, 10, default));
            Assert.True(await idx.ShouldSkipFileAsync(path, default));
            Assert.True(await CodeSearchService.ShouldSkipFileAsync(path, default));
        }
        finally { BinaryExtensions.Set.Remove(ext); }
    }
}

