// Plain GPIO output for pins 0..31: route the pad to the GPIO block and drive
// it through the set/clear registers.
module esp32::pin;
import esp32c5::gpio, esp32c5::io_mux, esp32::mmio;

const uint FUNC_GPIO = 1;       // IO_MUX function number that selects GPIO
const uint SIG_GPIO_OUT = 256;  // output signal "GPIO_OUT_REG drives the pad"

fn void output(uint pin)
{
	uint mux = io_mux::GPIO0_REG + pin * 4;
	uint v = mmio::read(mux) & ~(io_mux::MCU_SEL_V << io_mux::MCU_SEL_S);
	mmio::write(mux, v | (FUNC_GPIO << io_mux::MCU_SEL_S));
	mmio::write(gpio::FUNC0_OUT_SEL_CFG_REG + pin * 4, SIG_GPIO_OUT);
	mmio::write(gpio::ENABLE_W1TS_REG, 1 << pin);
}

fn void high(uint pin) @inline
{
	mmio::write(gpio::OUT_W1TS_REG, 1 << pin);
}

fn void low(uint pin) @inline
{
	mmio::write(gpio::OUT_W1TC_REG, 1 << pin);
}

fn void set(uint pin, bool level) @inline
{
	if (level)
	{
		high(pin);
	}
	else
	{
		low(pin);
	}
}
