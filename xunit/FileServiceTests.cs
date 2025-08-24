using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Ide.Core.Files;
using Xunit;

namespace Ide.Tests;

public class FileServiceTests
{
    private static string CreateTempDir()
    {
        var dir = Path.Combine(Path.GetTempPath(), "ide-tests-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        return dir;
    }

    [Fact]
    public async Task FileService_ReadWriteOverwrite_Works()
    {
        var root = CreateTempDir();
        var path = Path.Combine(root, "a.txt");
        var svc = new FileService();

        var w1 = await svc.WriteFilesAsync(new[] { new FileWrite(path, "hello") });
        Assert.True(w1.Single().Ok);

        var r1 = await svc.ReadFilesAsync(new[] { path });
        Assert.True(r1.Single().Ok);
        Assert.Equal("hello", r1.Single().Content);

        var w2 = await svc.WriteFilesAsync(new[] { new FileWrite(path, "world") });
        Assert.True(w2.Single().Ok);

        var r2 = await svc.ReadFilesAsync(new[] { path });
        Assert.True(r2.Single().Ok);
        Assert.Equal("world", r2.Single().Content);
    }

    [Fact]
    public async Task FileService_ApplyUnifiedDiff_Works()
    {
        var root = CreateTempDir();
        var path = Path.Combine(root, "a.txt");
        await File.WriteAllTextAsync(path, "alpha\nbeta\ngamma\n", new UTF8Encoding(false));

        var diff = @"+++ b/a.txt
@@ -1,3 +1,4 @@
 alpha
-beta
+beta2
 gamma
+delta
";

        var svc = new FileService();
        var pr = await svc.ApplyUnifiedDiffAsync(root, diff, atomic: true);
        Assert.True(pr.Ok, pr.Error);
        Assert.Equal(1, pr.FilesChanged);

        var text = await File.ReadAllTextAsync(path, new UTF8Encoding(false));
        Assert.Equal("alpha\nbeta2\ngamma\ndelta\n", text);
    }

    [Fact]
    public async Task FileService_BinaryReject_ReadAndWrite()
    {
        var root = CreateTempDir();
        var binPath = Path.Combine(root, "image.png");
        await File.WriteAllBytesAsync(binPath, new byte[] { 1, 2, 3, 4 });

        var svc = new FileService();
        var r = await svc.ReadFilesAsync(new[] { binPath });
        Assert.False(r.Single().Ok);
        Assert.Contains("Binary", r.Single().Error ?? string.Empty);

        var w = await svc.WriteFilesAsync(new[] { new FileWrite(Path.Combine(root, "nul.txt"), "abc\0def") });
        Assert.False(w.Single().Ok);
        Assert.Contains("NUL", w.Single().Error ?? string.Empty);
    }

    [Fact]
    public async Task Helpers_IsBinary_ReadFile_WriteAtomic_ParseDiff()
    {
        var root = CreateTempDir();
        var txt = Path.Combine(root, "a.txt");
        await File.WriteAllTextAsync(txt, "hello", new UTF8Encoding(false));
        Assert.False(await FileService.IsBinaryAsync(txt, 5, default));
        var rr = await FileService.ReadFileAsync(txt, 1000, default);
        Assert.True(rr.Ok);

        var bPath = Path.Combine(root, "b.txt");
        var w = await FileService.WriteFileAsync(new FileWrite(bPath, "hi"), true, default);
        Assert.True(w.Ok);
        Assert.Equal("hi", await File.ReadAllTextAsync(bPath, new UTF8Encoding(false)));
        var cPath = Path.Combine(root, "c.txt");
        await FileService.WriteFileAtomicAsync(cPath, "z", default);
        Assert.Equal("z", await File.ReadAllTextAsync(cPath, new UTF8Encoding(false)));

        var diff = "+++ b/d.txt\n@@ -0,0 +1 @@\n+line\n";
        var patches = FileService.ParseDiffLines(root, diff).ToList();
        Assert.Single(patches);
        Assert.Equal(1, patches[0].Hunks.Count);
    }
}
