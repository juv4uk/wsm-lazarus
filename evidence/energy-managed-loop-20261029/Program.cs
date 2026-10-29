using System.Globalization;

static class Program
{
    private static uint SumToN(ulong n)
    {
        uint sum = 0;
        unchecked
        {
            for (ulong i = n; i > 0; --i) sum += (uint)i;
        }
        return sum & 255;
    }

    private static bool ParsePositive(string text, out ulong value) =>
        ulong.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out value) && value > 0;

    private static int Server(ulong n)
    {
        string? line;
        while ((line = Console.ReadLine()) is not null)
        {
            if (!uint.TryParse(line, NumberStyles.None, CultureInfo.InvariantCulture, out uint count) ||
                count < 1 || count > 1_000_000)
            {
                Console.Error.WriteLine("invalid repetitions");
                return 65;
            }
            int gc0 = GC.CollectionCount(0) + GC.CollectionCount(1) + GC.CollectionCount(2);
            TimeSpan pause0 = GC.GetTotalPauseDuration();
            ulong checksum = 0;
            for (uint i = 0; i < count; ++i) checksum += SumToN(n);
            int gc1 = GC.CollectionCount(0) + GC.CollectionCount(1) + GC.CollectionCount(2);
            long pauseMs = (long)(GC.GetTotalPauseDuration() - pause0).TotalMilliseconds;
            Console.WriteLine($"OK\t{count}\t{checksum & 255}\t{gc1 - gc0}\t{Math.Max(0, pauseMs)}");
            Console.Out.Flush();
        }
        return 0;
    }

    public static int Main(string[] args)
    {
        if (args.Length != 2) return 64;
        if (!ParsePositive(args[1], out ulong n)) return 65;
        return args[0] switch
        {
            "single" => (int)SumToN(n),
            "server" => Server(n),
            _ => 64,
        };
    }
}
