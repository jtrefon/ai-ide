using Ide.Core.Utils;

namespace Ide.Tests;

public class CounterServiceTests
{
    [Fact]
    public void Increment_Then_GetCountText_ReturnsPluralizedText()
    {
        var svc = new CounterService();
        Assert.Equal(0, svc.Count);

        Assert.Equal(1, svc.Increment());
        Assert.Equal("Clicked 1 time", svc.GetCountText());

        Assert.Equal(2, svc.Increment());
        Assert.Equal("Clicked 2 times", svc.GetCountText());
    }
}
