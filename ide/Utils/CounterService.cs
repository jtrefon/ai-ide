namespace ide.Utils;

public class CounterService
{
    private int _count = 0;

    public int Count => _count;

    public int Increment()
    {
        return ++_count;
    }

    public int Decrement()
    {
        return --_count;
    }

    public void Reset()
    {
        _count = 0;
    }

    public string GetCountText()
    {
        if (_count == 1)
            return $"Clicked {_count} time";
        else
            return $"Clicked {_count} times";
    }
}