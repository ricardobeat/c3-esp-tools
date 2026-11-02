// Display test for the NM-CYD-C5 (2.8" ST7789, 240x320): colour bars, a grey
// ramp and a block "C3", drawn from C3 with no graphics library.
//
// The display, touch controller and SD card share one SPI bus; the touch and
// SD chip-selects are driven high so they stay off it.
module lcd_demo;
import esp32::console, esp32::pin, esp32::rom, esp32::st7789, esp32::wdt;

const uint TOUCH_CS = 1;
const uint SD_CS = 10;

fn void main() @export("c3_main")
{
	wdt::disable_all();
	console::write("\nlcd test: ST7789 on the NM-CYD-C5\n");

	pin::output(TOUCH_CS); pin::high(TOUCH_CS);
	pin::output(SD_CS); pin::high(SD_CS);

	st7789::Display d = { .sclk = 6, .mosi = 7, .cs = 23, .dc = 24, .bl = 25,
	                      .width = 240, .height = 320, .invert = true };
	d.init();
	console::write("init done\n");

	d.fill_rect(0, 0, 240, 320, st7789::rgb(0, 0, 0));

	// Colour bars: red, green, blue, white.
	uint[4] bars = { st7789::rgb(255, 0, 0), st7789::rgb(0, 255, 0),
	                 st7789::rgb(0, 0, 255), st7789::rgb(255, 255, 255) };
	foreach (i, c : bars) d.fill_rect((uint)i * 60, 0, 60, 120, c);
	console::write("bars done\n");

	// Grey ramp, black to white in 16 steps.
	for (uint s = 0; s < 16; s++)
	{
		uint v = s * 17;
		d.fill_rect(s * 15, 120, 15, 40, st7789::rgb(v, v, v));
	}
	console::write("ramp done\n");

	// Block letters "C" and "3".
	uint w = st7789::rgb(255, 255, 255);
	d.fill_rect(40, 180, 20, 100, w);
	d.fill_rect(40, 180, 70, 20, w);
	d.fill_rect(40, 260, 70, 20, w);
	d.fill_rect(130, 180, 70, 20, w);
	d.fill_rect(150, 220, 50, 20, w);
	d.fill_rect(130, 260, 70, 20, w);
	d.fill_rect(180, 180, 20, 100, w);

	// Yellow frame.
	uint y = st7789::rgb(255, 220, 0);
	d.fill_rect(0, 0, 240, 2, y);
	d.fill_rect(0, 318, 240, 2, y);
	d.fill_rect(0, 0, 2, 320, y);
	d.fill_rect(238, 0, 2, 320, y);
	console::write("all done\n");

	for (uint n = 1;; n++)
	{
		rom::delay_ms(1000);
		console::write("alive ");
		console::write_dec(n);
		console::write("\n");
	}
}
