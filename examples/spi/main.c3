// SPI self-test with no wiring: MOSI is also routed back into MISO through the
// GPIO matrix, so everything sent must come back unchanged. Runs several clock
// rates and transfer lengths (100 bytes crosses the 64-byte chunk boundary) and
// reports over the UART.
//
// Pins are the NM-CYD-C5's SPI bus. The display, touch and SD chip-selects are
// held high so those devices ignore the traffic.
module spi_test;
import esp32::console, esp32::pin, esp32::rom, esp32::spibus, esp32::wdt;

const uint SCLK = 6;
const uint MOSI = 7;
const uint[3] DEVICE_CS = { 23, 1, 10 };   // display, touch, SD

fn bool check(uint hz, uint len, uint seed)
{
	char[100] tx;
	char[100] rx;
	for (uint i = 0; i < len; i++)
	{
		tx[i] = (char)((i * 37 + seed * 11 + 5) & 0xFF);
		rx[i] = 0;
	}
	spibus::configure(hz, 0);
	spibus::transfer(tx[:len], rx[:len]);
	for (uint i = 0; i < len; i++)
	{
		if (rx[i] != tx[i]) return false;
	}
	return true;
}

fn void main() @export("c3_main")
{
	wdt::disable_all();
	console::write("\nspi loopback test (GP-SPI2, MOSI -> MISO through the GPIO matrix)\n");

	foreach (cs : DEVICE_CS)
	{
		pin::output(cs);
		pin::high(cs);
	}
	spibus::init(SCLK, MOSI, MOSI);

	uint[5] rates = { 100_000, 1_000_000, 8_000_000, 12_000_000, 24_000_000 };
	uint[6] lengths = { 1, 3, 4, 17, 64, 100 };
	uint failures = 0;

	foreach (hz : rates)
	{
		uint ok = 0;
		foreach (i, len : lengths)
		{
			if (check(hz, len, (uint)i))
			{
				ok++;
			}
			else
			{
				failures++;
				console::write("  FAIL at ");
				console::write_dec(hz);
				console::write(" Hz, ");
				console::write_dec(len);
				console::write(" bytes\n");
			}
		}
		console::write_dec(hz);
		console::write(" Hz: ");
		console::write_dec(ok);
		console::write("/");
		console::write_dec(lengths.len);
		console::write(" ok\n");
	}

	console::write(failures == 0 ? "PASS\n" : "FAIL\n");
	for (uint n = 1;; n++)
	{
		rom::delay_ms(2000);
		console::write("idle ");
		console::write_dec(n);
		console::write("\n");
	}
}
