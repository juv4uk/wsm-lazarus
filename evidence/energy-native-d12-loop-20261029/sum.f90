program sum_bench
  use, intrinsic :: iso_fortran_env, only: int64
  implicit none
  character(len=64) :: argument
  integer(int64) :: count, i, sum
  integer :: status

  if (command_argument_count() /= 1) stop 64
  call get_command_argument(1, argument, status=status)
  if (status /= 0) stop 65
  read(argument, *, iostat=status) count
  if (status /= 0) stop 65
  if (count < 0_int64) stop 65

  sum = 0_int64
  do i = count, 1_int64, -1_int64
    sum = modulo(sum + modulo(i, 4294967296_int64), 4294967296_int64)
  end do
  stop int(modulo(sum, 256_int64))
end program sum_bench
