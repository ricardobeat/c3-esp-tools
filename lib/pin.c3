// GPIO for pins 0..31: plain outputs and inputs, plus routing a pad to or from
// a peripheral signal through the GPIO matrix.
module esp32::pin;
import esp32c5::gpio, esp32c5::io_mux, esp32::mmio;

const uint FUNC_GPIO = 1;       // IO_MUX function number that selects GPIO
const uint SIG_GPIO_OUT = 256;  // output signal "GPIO_OUT_REG drives the pad"

fn void select_gpio(uint pin) @private
{
	uint mux = io_mux::GPIO0_REG + pin * 4;
	uint v = mmio::read(mux) & ~(io_mux::MCU_SEL_V << io_mux::MCU_SEL_S);
	mmio::write(mux, v | (FUNC_GPIO << io_mux::MCU_SEL_S));
}

// Drive the pad from peripheral output `signal` (see soc/gpio_sig_map.h).
fn void route_output(uint pin, uint signal)
{
	select_gpio(pin);
	mmio::write(gpio::FUNC0_OUT_SEL_CFG_REG + pin * 4, signal);
	mmio::write(gpio::ENABLE_W1TS_REG, 1 << pin);
}

// Feed the pad into peripheral input `signal`. Safe on a pad that is also an
// output, which is how the SPI loopback test works.
fn void route_input(uint pin, uint signal)
{
	select_gpio(pin);
	mmio::set_bits(io_mux::GPIO0_REG + pin * 4, io_mux::FUN_IE);
	mmio::write(gpio::FUNC0_IN_SEL_CFG_REG + signal * 4, pin | gpio::SIG0_IN_SEL);
}

fn void output(uint pin)
{
	route_output(pin, SIG_GPIO_OUT);
}

fn void input(uint pin, bool pull_up)
{
	select_gpio(pin);
	uint mux = io_mux::GPIO0_REG + pin * 4;
	mmio::set_bits(mux, io_mux::FUN_IE);
	if (pull_up)
	{
		mmio::set_bits(mux, io_mux::FUN_PU);
	}
	else
	{
		mmio::clear_bits(mux, io_mux::FUN_PU);
	}
	mmio::write(gpio::ENABLE_W1TC_REG, 1 << pin);
}

fn bool read(uint pin) @inline
{
	return ((mmio::read(gpio::IN_REG) >> pin) & 1) != 0;
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
