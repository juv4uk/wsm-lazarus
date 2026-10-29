package main

import (
	"bufio"
	"fmt"
	"os"
	"runtime"
	"strconv"
)

const expectedExit = 173

func sumToN(n uint64) uint32 {
	var sum uint32
	for i := n; i > 0; i-- {
		sum += uint32(i)
	}
	return sum & 255
}

func repetitions(raw string) (uint64, bool) {
	value, err := strconv.ParseUint(raw, 10, 32)
	return value, err == nil && value > 0 && value <= 1000000
}

func runServer(n uint64) int {
	scanner := bufio.NewScanner(os.Stdin)
	writer := bufio.NewWriter(os.Stdout)
	for scanner.Scan() {
		count, ok := repetitions(scanner.Text())
		if !ok {
			fmt.Fprintln(os.Stderr, "invalid repetitions")
			return 65
		}
		var before, after runtime.MemStats
		runtime.ReadMemStats(&before)
		var checksum uint64
		for i := uint64(0); i < count; i++ {
			checksum += uint64(sumToN(n))
		}
		runtime.ReadMemStats(&after)
		fmt.Fprintf(writer, "OK\t%d\t%d\t%d\t%d\n", count, checksum&255,
			after.NumGC-before.NumGC,
			(after.PauseTotalNs-before.PauseTotalNs)/1000000)
		if err := writer.Flush(); err != nil {
			return 74
		}
	}
	if err := scanner.Err(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 74
	}
	return 0
}

func main() {
	if len(os.Args) != 3 {
		os.Exit(64)
	}
	n, err := strconv.ParseUint(os.Args[2], 10, 64)
	if err != nil || n == 0 {
		os.Exit(65)
	}
	switch os.Args[1] {
	case "single":
		os.Exit(int(sumToN(n)))
	case "server":
		os.Exit(runServer(n))
	default:
		os.Exit(64)
	}
}
