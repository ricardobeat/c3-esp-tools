// Called by crt0's trap vector on any exception. Reports it and stops.
module esp32::trap;
import esp32::console;

fn void report(uint cause, uint epc, uint tval) @export("c3_trap")
{
	console::write("\n*** trap: mcause=");
	console::write_hex(cause);
	console::write(" mepc=");
	console::write_hex(epc);
	console::write(" mtval=");
	console::write_hex(tval);
	console::write("\n");
}
