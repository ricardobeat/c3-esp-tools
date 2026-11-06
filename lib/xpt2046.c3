// XPT2046 resistive touch controller on the SPI bus. CS is a GPIO and the
// pen-interrupt pin reads low while the panel is pressed.
module esp32::xpt2046;
import esp32::pin, esp32::spibus;

const uint CMD_Y = 0x90;
const uint CMD_X = 0xD0;

struct Touch
{
	uint cs, irq;
	uint hz;                // the controller tops out around 2 MHz
}

fn void Touch.init(&self)
{
	pin::output(self.cs);
	pin::high(self.cs);
	pin::input(self.irq, true);
}

fn bool Touch.pressed(&self)
{
	return !pin::read(self.irq);
}

// One 12-bit conversion: the control byte goes out while the result comes back
// in the next 16 bits, right-aligned by a 3-bit shift.
fn uint Touch.sample(&self, uint cmd)
{
	char[3] tx = { (char)cmd, 0, 0 };
	char[3] rx;
	spibus::configure(self.hz, 0);
	pin::low(self.cs);
	spibus::transfer(tx[..], rx[..]);
	pin::high(self.cs);
	return ((((uint)rx[1] << 8) | (uint)rx[2]) >> 3) & 0xFFF;
}

// Average of four conversions, to smooth the noise.
fn uint Touch.read(&self, uint cmd)
{
	uint sum = 0;
	for (uint i = 0; i < 4; i++) sum += self.sample(cmd);
	return sum / 4;
}
