// Ghidra headless script: resolve what a list of DAT_/global pointer
// locations point to (name + target function, if any), and dump the
// pseudocode of a list of functions. Disposable, edit lists between runs.
//
//@category TS6Droid

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.symbol.Symbol;
import ghidra.program.model.symbol.SymbolTable;
import ghidra.program.model.mem.Memory;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.util.task.ConsoleTaskMonitor;
import ghidra.app.cmd.function.CreateFunctionCmd;

public class InspectData extends GhidraScript {

    @Override
    public void run() throws Exception {
        long[] dataAddrs = {
            0x04052af8L,
            0x04052af0L,
            0x04052b00L,
        };

        long[] funcAddrs = {
            0x01de5430L,
            0x01de72e0L,
        };

        FunctionManager fm = currentProgram.getFunctionManager();
        SymbolTable st = currentProgram.getSymbolTable();
        ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();

        println("\n=== DATA POINTERS ===");
        for (long off : dataAddrs) {
            Address addr = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(off);
            try {
                long ptrVal = getLong(addr);
                Address target = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(ptrVal);
                Symbol[] syms = st.getSymbols(target);
                String symName = syms.length > 0 ? syms[0].getName() : "(no symbol)";
                Function tf = fm.getFunctionAt(target);
                println(addr + " -> " + target + "  sym=" + symName + "  func=" + (tf != null ? tf.getName() : "none"));
            } catch (Exception e) {
                println(addr + " -> ERROR: " + e.getMessage());
            }
        }

        println("\n=== FUNCTION DECOMPILES ===");
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        for (long off : funcAddrs) {
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
        }
        decomp.dispose();
        println("\nDONE");
    }
}
