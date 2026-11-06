// SPI master on the chip's general-purpose SPI2 peripheral: polled, no DMA, no
// interrupts. A transaction moves up to 64 bytes through the peripheral's data
// buffer; longer transfers are split into chunks.
//
// Chip select is not driven here. Hardware CS is turned off, so callers use a
// GPIO, which lets one bus serve several devices at different clocks and modes.
module esp32::spibus;
import esp32c5::spi, esp32c5::pcr, esp32::mmio, esp32::pin;

const uint XTAL_HZ = 48_000_000;
const uint CLKM_DIV = 2;                 // peripheral clock = XTAL / CLKM_DIV
const uint FCLK_HZ = XTAL_HZ / CLKM_DIV; // 24 MHz: the fastest SPI clock offered
const uint MAX_CHUNK = 64;               // the data buffer is 16 words

// GPIO-matrix signal numbers for GP-SPI2 ("FSPI*" in soc/gpio_sig_map.h).
const uint SIG_CLK_OUT = 56;
const uint SIG_MISO_IN = 57;
const uint SIG_MOSI_OUT = 58;

// Enables and resets the peripheral and routes its pads. For a loopback test,
// pass the MOSI pad as `miso` too.
fn void init(uint sclk, uint mosi, uint miso)
{
	mmio::set_bits(pcr::SPI2_CONF_REG, pcr::SPI2_CLK_EN);
	mmio::set_bits(pcr::SPI2_CONF_REG, pcr::SPI2_RST_EN);
	mmio::clear_bits(pcr::SPI2_CONF_REG, pcr::SPI2_RST_EN);

	// Peripheral clock source: XTAL (select 0), divided by CLKM_DIV.
	uint v = mmio::read(pcr::SPI2_CLKM_CONF_REG);
	v &= ~(pcr::SPI2_CLKM_SEL_M | pcr::SPI2_CLKM_DIV_NUM_M);
	v |= ((CLKM_DIV - 1) << pcr::SPI2_CLKM_DIV_NUM_S) | pcr::SPI2_CLKM_EN;
	mmio::write(pcr::SPI2_CLKM_CONF_REG, v);

	// Master, plain user transactions: no command, address or dummy phases.
	mmio::write(spi::SLAVE_REG, 0);
	mmio::write(spi::USER_REG, 0);
	mmio::write(spi::USER1_REG, 0);
	mmio::write(spi::USER2_REG, 0);

	pin::route_output(sclk, SIG_CLK_OUT);
	pin::route_output(mosi, SIG_MOSI_OUT);
	pin::route_input(miso, SIG_MISO_IN);
	configure(1_000_000, 0);
}

// The SPI clock register for `hz`, found the way ESP-IDF's spi_ll does: try
// every n (the clock's period in peripheral ticks) and the prescaler that goes
// with it, keep the closest, and prefer a larger n for a steadier duty cycle.
fn uint clock_value(uint hz)
{
	if (hz == 0) hz = 1;
	if (hz >= FCLK_HZ / 4 * 3) return spi::CLK_EQU_SYSCLK;

	uint best_n = 2;
	uint best_pre = 1;
	uint best_err = 0xFFFFFFFF;
	for (uint n = 2; n <= 64; n++)
	{
		uint pre = (FCLK_HZ / n + hz / 2) / hz;
		if (pre < 1) pre = 1;
		if (pre > 16) pre = 16;
		uint f = FCLK_HZ / (pre * n);
		uint err = f > hz ? f - hz : hz - f;
		if (err <= best_err)
		{
			best_err = err;
			best_n = n;
			best_pre = pre;
		}
	}
	uint h = (128 * best_n + 127) / 256;   // 50% duty
	if (h < 1) h = 1;
	return ((best_pre - 1) << spi::CLKDIV_PRE_S)
	     | ((best_n - 1) << spi::CLKCNT_N_S)
	     | ((h - 1) << spi::CLKCNT_H_S)
	     | ((best_n - 1) << spi::CLKCNT_L_S);
}

fn void apply() @private
{
	mmio::set_bits(spi::CMD_REG, spi::UPDATE);
	while ((mmio::read(spi::CMD_REG) & spi::UPDATE) != 0) {}
}

// Sets the clock and SPI mode (0..3) for the transactions that follow.
fn void configure(uint hz, uint mode)
{
	mmio::write(spi::CLOCK_REG, clock_value(hz));

	uint misc = mmio::read(spi::MISC_REG) | 0x3F;   // hardware CS0..CS5 off
	uint user = mmio::read(spi::USER_REG) & ~spi::CK_OUT_EDGE;
	if ((mode & 2) != 0)
	{
		misc |= spi::CK_IDLE_EDGE;
	}
	else
	{
		misc &= ~spi::CK_IDLE_EDGE;
	}
	if (mode == 1 || mode == 2) user |= spi::CK_OUT_EDGE;
	mmio::write(spi::MISC_REG, misc);
	mmio::write(spi::USER_REG, user);
	apply();
}

// Bytes go into the data buffer least-significant byte first, so byte 0 of a
// word is the first one on the wire.
fn void load(char[] tx) @private
{
	uint len = (uint)tx.len;
	for (uint i = 0; i < len; i += 4)
	{
		uint w = 0;
		for (uint k = 0; k < 4 && i + k < len; k++)
		{
			w |= (uint)tx[i + k] << (8 * k);
		}
		mmio::write(spi::W0_REG + i, w);
	}
}

fn void unload(char[] rx) @private
{
	uint len = (uint)rx.len;
	for (uint i = 0; i < len; i += 4)
	{
		uint w = mmio::read(spi::W0_REG + i);
		for (uint k = 0; k < 4 && i + k < len; k++)
		{
			rx[i + k] = (char)((w >> (8 * k)) & 0xFF);
		}
	}
}

// Runs one transaction of `nbytes` already loaded into the data buffer.
fn void run(uint nbytes, bool read_back) @private
{
	mmio::write(spi::MS_DLEN_REG, nbytes * 8 - 1);
	uint user = mmio::read(spi::USER_REG) & ~(spi::USR_MOSI | spi::USR_MISO | spi::DOUTDIN);
	user |= spi::USR_MOSI;
	if (read_back) user |= spi::USR_MISO | spi::DOUTDIN;
	mmio::write(spi::USER_REG, user);
	mmio::write(spi::DMA_INT_CLR_REG, spi::TRANS_DONE_INT_CLR);
	apply();
	mmio::set_bits(spi::CMD_REG, spi::USR);
	while ((mmio::read(spi::DMA_INT_RAW_REG) & spi::TRANS_DONE_INT_RAW) == 0) {}
}

fn void write(char[] data)
{
	uint len = (uint)data.len;
	uint pos = 0;
	while (pos < len)
	{
		uint n = len - pos;
		if (n > MAX_CHUNK) n = MAX_CHUNK;
		load(data[pos:n]);
		run(n, false);
		pos += n;
	}
}

fn void write_byte(char b)
{
	char[1] one = { b };
	write(one[..]);
}

// Sends `tx` and fills `rx` with what came back at the same time. Both must be
// the same length.
fn void transfer(char[] tx, char[] rx)
{
	uint len = (uint)(tx.len < rx.len ? tx.len : rx.len);
	uint pos = 0;
	while (pos < len)
	{
		uint n = len - pos;
		if (n > MAX_CHUNK) n = MAX_CHUNK;
		load(tx[pos:n]);
		run(n, true);
		unload(rx[pos:n]);
		pos += n;
	}
}
