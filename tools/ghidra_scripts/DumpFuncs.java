// Ghidra headless script: decompile a fixed list of functions (by address)
// and print their pseudocode + direct callees. General-purpose "dump these
// addresses" tool for stepping through a call chain.
//
//@category TS6Droid

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.util.task.ConsoleTaskMonitor;
import ghidra.app.cmd.function.CreateFunctionCmd;

public class DumpFuncs extends GhidraScript {

    @Override
    public void run() throws Exception {
        // Edit this list between runs.
        long[] targets = {
            0x01ec3d20L,
            0x01d83db0L,
            0x01d80e80L,
            0x01d80e00L,
            0x01c69360L,
        };

        FunctionManager fm = currentProgram.getFunctionManager();
        ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);

        for (long off : targets) {
            Address addr = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(off);
            Function f = fm.getFunctionAt(addr);
            if (f == null) f = fm.getFunctionContaining(addr);
            if (f == null) {
                CreateFunctionCmd cmd = new CreateFunctionCmd(addr);
                cmd.applyTo(currentProgram, monitor);
                f = fm.getFunctionAt(addr);
            }
            if (f == null) {
                println("=== " + addr + ": NO FUNCTION ===");
                continue;
            }
            println("\n=== FUNCTION " + f.getName() + " @ " + f.getEntryPoint() + " ===");
            DecompileResults res = decomp.decompileFunction(f, 120, monitor);
            if (res.decompileCompleted()) {
                println(res.getDecompiledFunction().getC());
            } else {
                println("decompile failed: " + res.getErrorMessage());
            }
            println("-- called functions --");
            for (Function cf : f.getCalledFunctions(monitor)) {
                println("  calls: " + cf.getName() + " @ " + cf.getEntryPoint());
            }
        }
        decomp.dispose();
        println("\nDONE");
    }
}
