import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.PrintWriter;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.util.List;

public final class Sum {
    private static final List<GarbageCollectorMXBean> COLLECTORS =
        ManagementFactory.getGarbageCollectorMXBeans();

    private static int sumToN(long n) {
        int sum = 0;
        for (long i = n; i > 0; --i) sum += (int) i;
        return sum & 255;
    }

    private static long gcCount() {
        long total = 0;
        for (GarbageCollectorMXBean bean : COLLECTORS) {
            long count = bean.getCollectionCount();
            if (count > 0) total += count;
        }
        return total;
    }

    private static long gcMillis() {
        long total = 0;
        for (GarbageCollectorMXBean bean : COLLECTORS) {
            long time = bean.getCollectionTime();
            if (time > 0) total += time;
        }
        return total;
    }

    private static int server(long n) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in));
        PrintWriter output = new PrintWriter(System.out, true);
        String line;
        while ((line = input.readLine()) != null) {
            final int count;
            try {
                count = Integer.parseInt(line);
            } catch (NumberFormatException error) {
                System.err.println("invalid repetitions");
                return 65;
            }
            if (count < 1 || count > 1_000_000) {
                System.err.println("invalid repetitions");
                return 65;
            }
            long gcBefore = gcCount();
            long millisBefore = gcMillis();
            long checksum = 0;
            for (int i = 0; i < count; ++i) checksum += sumToN(n);
            long gcDelta = Math.max(0, gcCount() - gcBefore);
            long millisDelta = Math.max(0, gcMillis() - millisBefore);
            output.printf("OK\t%d\t%d\t%d\t%d%n", count, checksum & 255,
                          gcDelta, millisDelta);
            if (output.checkError()) return 74;
        }
        return 0;
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 2) System.exit(64);
        final long n;
        try {
            n = Long.parseLong(args[1]);
        } catch (NumberFormatException error) {
            System.exit(65);
            return;
        }
        if (n < 1) System.exit(65);
        if ("single".equals(args[0])) System.exit(sumToN(n));
        if ("server".equals(args[0])) System.exit(server(n));
        System.exit(64);
    }
}
