using Ide.Core.State;

namespace Ide.Tests;

public class StateStoreTests
{
    [Fact]
    public void Set_And_TryGet_Returns_Value()
    {
        var store = new StateStore();
        store.Set("mode", "Ask");
        Assert.True(store.TryGet<string>("mode", out var mode));
        Assert.Equal("Ask", mode);
    }

    [Fact]
    public void Snapshot_And_Restore_Works()
    {
        var store = new StateStore();
        store.Set("count", 1);
        var snap = store.Snapshot();
        store.Set("count", 2);
        store.Restore(snap);
        Assert.True(store.TryGet<int>("count", out var value));
        Assert.Equal(1, value);
    }
}
