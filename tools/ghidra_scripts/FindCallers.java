//@category TS6Droid
import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.util.task.ConsoleTaskMonitor;

public class FindCallers extends GhidraScript {
    @Override
    public void run() throws Exception {
        long[] targets = { 0x01de5430L, 0x01de72e0L };
        FunctionManager fm = currentProgram.getFunctionManager();
        ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();
        for (long off : targets) {
            Address addr = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(off);
            Function f = fm.getFunctionAt(addr);
            if (f == null) f = fm.getFunctionContaining(addr);
            if (f == null) { println(addr + ": NO FUNCTION"); continue; }
            println("=== callers of " + f.getName() + " @ " + f.getEntryPoint() + " ===");
            for (Function cf : f.getCallingFunctions(monitor)) {
                println("  called by: " + cf.getName() + " @ " + cf.getEntryPoint());
            }
        }
        println("DONE");
    }
}
