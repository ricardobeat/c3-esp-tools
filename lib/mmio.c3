// Volatile 32-bit register access. Addresses come from the generated
// esp32c5::* modules (gen/), built by init.sh from ESP-IDF's register headers.
module esp32::mmio;

fn uint read(uint addr) @inline
{
	return $$volatile_load((uint*)(uptr)addr);
}

fn void write(uint addr, uint value) @inline
{
	$$volatile_store((uint*)(uptr)addr, value);
}

fn void set_bits(uint addr, uint mask) @inline
{
	write(addr, read(addr) | mask);
}

fn void clear_bits(uint addr, uint mask) @inline
{
	write(addr, read(addr) & ~mask);
}
