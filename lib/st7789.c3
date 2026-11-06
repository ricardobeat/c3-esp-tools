// ST7789 TFT on the SPI bus (esp32::spibus). CS and DC are GPIOs; the bus must
// already be initialised.
module esp32::st7789;
import esp32::pin, esp32::rom, esp32::spibus;

struct Display
{
	uint cs, dc, bl;        // GPIO numbers
	uint width, height;
	bool invert;
	uint hz;                // SPI clock for this device
}

fn uint rgb(uint r, uint g, uint b) @inline
{
	return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

fn void Display.cmd(&self, uint c)
{
	spibus::configure(self.hz, 0);
	pin::low(self.dc);
	pin::low(self.cs);
	spibus::write_byte((char)c);
	pin::high(self.cs);
}

fn void Display.data(&self, uint d)
{
	spibus::configure(self.hz, 0);
	pin::high(self.dc);
	pin::low(self.cs);
	spibus::write_byte((char)d);
	pin::high(self.cs);
}

fn void Display.init(&self)
{
	pin::output(self.cs);
	pin::output(self.dc);
	pin::output(self.bl);
	pin::high(self.cs);

	self.cmd(0x01);              // software reset
	rom::delay_ms(150);
	self.cmd(0x11);              // sleep out
	rom::delay_ms(120);
	self.cmd(0x3A);              // 16 bits per pixel
	self.data(0x55);
	self.cmd(0x36);              // memory access: RGB, no rotation
	self.data(0x00);
	self.cmd(self.invert ? 0x21 : 0x20);
	self.cmd(0x13);              // normal display mode
	self.cmd(0x29);              // display on
	rom::delay_ms(20);
	pin::high(self.bl);
}

fn void Display.window(&self, uint x0, uint y0, uint x1, uint y1)
{
	self.cmd(0x2A);
	self.data(x0 >> 8); self.data(x0 & 0xFF);
	self.data(x1 >> 8); self.data(x1 & 0xFF);
	self.cmd(0x2B);
	self.data(y0 >> 8); self.data(y0 & 0xFF);
	self.data(y1 >> 8); self.data(y1 & 0xFF);
	self.cmd(0x2C);              // memory write; pixels follow
}

fn void Display.fill_rect(&self, uint x, uint y, uint w, uint h, uint color)
{
	if (w == 0 || h == 0 || x >= self.width || y >= self.height) return;
	if (x + w > self.width) w = self.width - x;
	if (y + h > self.height) h = self.height - y;
	self.window(x, y, x + w - 1, y + h - 1);

	// One SPI transaction carries up to 32 pixels, so build that once.
	char[64] chunk;
	for (uint i = 0; i < 64; i += 2)
	{
		chunk[i] = (char)(color >> 8);
		chunk[i + 1] = (char)(color & 0xFF);
	}
	spibus::configure(self.hz, 0);
	pin::high(self.dc);
	pin::low(self.cs);
	for (uint left = w * h; left > 0;)
	{
		uint n = left > 32 ? 32 : left;
		spibus::write(chunk[:n * 2]);
		left -= n;
	}
	pin::high(self.cs);
}
