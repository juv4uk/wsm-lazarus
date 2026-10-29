import Glibc
import Foundation

guard CommandLine.arguments.count == 2,
      let count = UInt64(CommandLine.arguments[1]) else {
    exit(64)
}

var sum: UInt32 = 0
var i = count
while i > 0 {
    sum &+= UInt32(truncatingIfNeeded: i)
    i -= 1
}
exit(Int32(sum & 255))
