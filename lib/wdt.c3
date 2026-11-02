// The ROM leaves the watchdogs armed, expecting ESP-IDF's bootloader to take
// over. Without one, they reset the chip a few seconds after boot.
module esp32::wdt;
import esp32c5::lp_wdt, esp32c5::timg, esp32::mmio;

const uint KEY = 0x50D83AA1;

fn void disable_all()
{
	// RTC watchdog.
	mmio::write(lp_wdt::WPROTECT_REG, KEY);
	mmio::write(lp_wdt::CONFIG0_REG, 0);
	mmio::write(lp_wdt::WPROTECT_REG, 0);

	// Super watchdog: let the hardware feed itself.
	mmio::write(lp_wdt::SWD_WPROTECT_REG, KEY);
	mmio::set_bits(lp_wdt::SWD_CONFIG_REG, lp_wdt::SWD_AUTO_FEED_EN);
	mmio::write(lp_wdt::SWD_WPROTECT_REG, 0);

	// The two timer-group watchdogs.
	for (uint i = 0; i < 2; i++)
	{
		uint off = i * timg::STRIDE;
		mmio::write(timg::WDTWPROTECT_REG + off, KEY);
		mmio::write(timg::WDTCONFIG0_REG + off, 0);
		mmio::write(timg::WDTWPROTECT_REG + off, 0);
	}
}
