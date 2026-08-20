/*
  Copies `no_bytes` bytes of consecutive data in memory starting from `dest` address into `source` address.
*/
void memory_copy(char *source, char *dest, int no_bytes)
{
  for (int i = 0; i < no_bytes; i++)
  {
    *(dest + i) = *(source + i);
  }
}