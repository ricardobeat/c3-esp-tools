// NM-CYD-C5 display and touch over the SPI peripheral: colour bars, a grey
// ramp and a block "C3", then touch the screen to paint.
//
// The display, touch controller and SD card share one SPI bus (SCLK 6, MOSI 7,
// MISO 2); each has its own chip-select. The SD chip-select is held high.
module lcd_demo;
import esp32::console, esp32::pin, esp32::rom, esp32::spibus, esp32::st7789,
       esp32::wdt, esp32::xpt2046;

const uint SD_CS = 10;

// Raw touch range for this panel, from LovyanGFX's NM-CYD-C5 setup. X runs
// opposite to the screen's X.
const uint RAW_X_LEFT = 3900;
const uint RAW_X_RIGHT = 300;
const uint RAW_Y_TOP = 200;
const uint RAW_Y_BOTTOM = 3700;

fn uint scale(uint raw, uint from, uint to, uint size)
{
	if (from > to)
	{
		if (raw >= from) return 0;
		if (raw <= to) return size - 1;
		return (from - raw) * size / (from - to);
	}
	if (raw <= from) return 0;
	if (raw >= to) return size - 1;
	return (raw - from) * size / (to - from);
}

fn void main() @export("c3_main")
{
	wdt::disable_all();
	console::write("\nlcd test: ST7789 and XPT2046 on SPI\n");

	pin::output(SD_CS);
	pin::high(SD_CS);
	spibus::init(6, 7, 2);

	st7789::Display d = { .cs = 23, .dc = 24, .bl = 25, .width = 240, .height = 320,
	                      .invert = true, .hz = 24_000_000 };
	d.init();
	console::write("init done\n");

	d.fill_rect(0, 0, 240, 320, st7789::rgb(0, 0, 0));

	// Colour bars: red, green, blue, white.
	uint[4] bars = { st7789::rgb(255, 0, 0), st7789::rgb(0, 255, 0),
	                 st7789::rgb(0, 0, 255), st7789::rgb(255, 255, 255) };
	foreach (i, c : bars) d.fill_rect((uint)i * 60, 0, 60, 120, c);

	// Grey ramp, black to white in 16 steps.
	for (uint s = 0; s < 16; s++)
	{
		uint v = s * 17;
		d.fill_rect(s * 15, 120, 15, 40, st7789::rgb(v, v, v));
	}

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
	console::write("drawing done; touch the screen to paint\n");

	xpt2046::Touch t = { .cs = 1, .irq = 3, .hz = 1_000_000 };
	t.init();
	uint reports = 0;
	while (true)
	{
		if (!t.pressed())
		{
			rom::delay_ms(5);
			continue;
		}
		uint rx = t.read(xpt2046::CMD_X);
		uint ry = t.read(xpt2046::CMD_Y);
		uint sx = scale(rx, RAW_X_LEFT, RAW_X_RIGHT, 240);
		uint sy = scale(ry, RAW_Y_TOP, RAW_Y_BOTTOM, 320);
		d.fill_rect(sx > 3 ? sx - 3 : 0, sy > 3 ? sy - 3 : 0, 6, 6, st7789::rgb(0, 255, 255));
		if (reports++ % 10 == 0)
		{
			console::write("touch raw ");
			console::write_dec(rx);
			console::write(",");
			console::write_dec(ry);
			console::write(" -> ");
			console::write_dec(sx);
			console::write(",");
			console::write_dec(sy);
			console::write("\n");
		}
	}
}
