// UART0 console. The ROM has already set it up at 115200 baud on the pins the
// USB-serial bridge uses, so this only moves bytes through the FIFO.
module esp32::console;
import esp32c5::uart, esp32::mmio;

fn bool tx_ready() @inline
{
	return ((mmio::read(uart::STATUS_REG) >> uart::TXFIFO_CNT_S) & 0xFF) < 120;
}

fn bool rx_ready() @inline
{
	return (mmio::read(uart::STATUS_REG) & uart::RXFIFO_CNT_M) != 0;
}

fn void put(char c)
{
	while (!tx_ready()) {}
	mmio::write(uart::FIFO_REG, (uint)c);
}

fn char get()
{
	while (!rx_ready()) {}
	return (char)(mmio::read(uart::FIFO_REG) & 0xFF);
}

// Writes `s`, turning each \n into \r\n for terminals.
fn void write(char[] s)
{
	foreach (c : s)
	{
		if (c == '\n') put('\r');
		put(c);
	}
}

fn void write_dec(uint v)
{
	char[10] digits;
	usz n = 0;
	do
	{
		digits[n++] = (char)('0' + v % 10);
		v /= 10;
	}
	while (v != 0);
	while (n > 0) put(digits[--n]);
}

fn void write_hex(uint v)
{
	write("0x");
	for (int shift = 28; shift >= 0; shift -= 4)
	{
		uint nibble = (v >> shift) & 0xF;
		put((char)(nibble < 10 ? '0' + nibble : 'a' + nibble - 10));
	}
}
