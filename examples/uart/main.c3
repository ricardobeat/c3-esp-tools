// UART demo: banner, a once-a-second tick, and an echo of whatever you type.
// Also shows a ROM function (rom::printf) and thread-local storage.
module uart_demo;
import esp32::console, esp32::rom, esp32::wdt;

tlocal uint g_ticks = 100;   // initialized: lives in .tdata, copied by crt0
tlocal uint g_zero;          // zero: lives in .tbss

fn void main() @export("c3_main")
{
	wdt::disable_all();

	console::write("\nc3-esp-tools: hello from C3 on the ESP32-C5\n");
	console::write("type something and it is echoed back\n");
	rom::printf("ROM printf says %d, 0x%x, %s\n", 42, 0xC3C3, "ok");

	console::write("tlocal: g_ticks=");
	console::write_dec(g_ticks);
	console::write(" g_zero=");
	console::write_dec(g_zero);
	console::write(" at ");
	console::write_hex((uint)(uptr)&g_ticks);
	console::write("\n");

	while (true)
	{
		for (uint i = 0; i < 100; i++)
		{
			while (console::rx_ready())
			{
				char c = console::get();
				if (c == '\r') c = '\n';
				console::put(c == '\n' ? '\r' : c);
				if (c == '\n') console::put('\n');
			}
			rom::delay_ms(10);
		}
		g_ticks++;
		console::write("tick ");
		console::write_dec(g_ticks);
		console::write("\n");
	}
}
