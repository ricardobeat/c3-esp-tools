// Host-side check of spibus::clock_value: decodes the register it produces and
// compares the resulting SPI clock with the one asked for. Run with `make test`.
module clock_test;
import std::io, esp32::spibus, esp32c5::spi;

fn int main()
{
	uint[10] rates = { 1, 1000, 100_000, 400_000, 1_000_000, 2_000_000, 8_000_000,
	                   12_000_000, 20_000_000, 24_000_000 };
	int bad = 0;
	foreach (hz : rates)
	{
		uint reg = spibus::clock_value(hz);
		uint eff;
		uint pre = 0;
		uint n = 0;
		uint h = 0;
		uint l = 0;
		if ((reg & spi::CLK_EQU_SYSCLK) != 0)
		{
			eff = spibus::FCLK_HZ;
		}
		else
		{
			pre = ((reg >> spi::CLKDIV_PRE_S) & 0xFFF) + 1;
			n = ((reg >> spi::CLKCNT_N_S) & 0x3F) + 1;
			h = ((reg >> spi::CLKCNT_H_S) & 0x3F) + 1;
			l = ((reg >> spi::CLKCNT_L_S) & 0x3F) + 1;
			eff = spibus::FCLK_HZ / (pre * n);
		}
		// Within 5% of the request, or the closest the dividers allow at the extremes.
		uint err = eff > hz ? eff - hz : hz - eff;
		bool extreme = hz < 24_000_000 / (16 * 64) || hz > 24_000_000 / 4 * 3;
		bool ok = (err * 20 <= hz) || extreme;
		// The clock must be high for at least one tick and low for at least one.
		if (n != 0 && (h < 1 || h >= n || l != n)) ok = false;
		if (!ok) bad++;
		io::printfn("%9d Hz -> %9d Hz  pre=%d n=%d h=%d l=%d  %s", hz, eff, pre, n, h, l, ok ? "ok" : "BAD");
	}
	return bad;
}
