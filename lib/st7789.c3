// ST7789 TFT over bit-banged SPI (mode 0, MSB first). Slow, but it needs no
// SPI peripheral, clock gating or DMA, so it works the moment the pins do.
module esp32::st7789;
import esp32::pin, esp32::rom;

struct Display
{
	uint sclk, mosi, cs, dc, bl;   // GPIO numbers
	uint width, height;
	bool invert;
}

fn uint rgb(uint r, uint g, uint b) @inline
{
	return ((r & 0xF8) << 8) | ((g & 0xFC) << 3) | (b >> 3);
}

fn void Display.write_byte(&self, uint b)
{
	for (int i = 7; i >= 0; i--)
	{
		pin::set(self.mosi, ((b >> i) & 1) != 0);
		pin::high(self.sclk);
		pin::low(self.sclk);
	}
}

fn void Display.cmd(&self, uint c)
{
	pin::low(self.dc);
	pin::low(self.cs);
	self.write_byte(c);
	pin::high(self.cs);
}

fn void Display.data(&self, uint d)
{
	pin::high(self.dc);
	pin::low(self.cs);
	self.write_byte(d);
	pin::high(self.cs);
}

fn void Display.init(&self)
{
	uint[5] pins = { self.sclk, self.mosi, self.cs, self.dc, self.bl };
	foreach (p : pins) pin::output(p);
	pin::high(self.cs);
	pin::low(self.sclk);

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
	pin::high(self.dc);
	pin::low(self.cs);
	for (uint n = w * h; n > 0; n--)
	{
		self.write_byte(color >> 8);
		self.write_byte(color & 0xFF);
	}
	pin::high(self.cs);
}
