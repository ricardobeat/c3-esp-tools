// Functions that live in the chip's mask ROM. Their addresses come from
// ESP-IDF's esp32c5.rom.ld, which the linker script includes.
module esp32::rom;

// Prints to the ROM's console (UART0). Supports %d %u %x %c %s.
extern fn int printf(char* fmt, ...) @cname("esp_rom_printf");
extern fn void delay_us(uint us) @cname("ets_delay_us");

fn void delay_ms(uint ms)
{
	for (uint i = 0; i < ms; i++) delay_us(1000);
}
