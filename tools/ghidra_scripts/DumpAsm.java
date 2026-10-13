// Ghidra headless script: decompile + disassemble a fixed list of functions,
// and print raw instructions for a given address range (to map registers to
// arguments at a specific call site). Disposable, edit between runs.
//
//@category TS6Droid

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.address.AddressSet;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.util.task.ConsoleTaskMonitor;
import ghidra.app.cmd.function.CreateFunctionCmd;

public class DumpAsm extends GhidraScript {

    @Override
    public void run() throws Exception {
        long[] decompileTargets = {
            0x01de6d00L,
        };

        // {startOffset, endOffsetExclusive} ranges to disassemble raw.
        long[][] asmRanges = {
            {0x01de6d00L, 0x01de6d80L},   // FUN_01de6d00 entry (ABI at entry)
            {0x01de5460L, 0x01de54c0L},   // call site in FUN_01de5430 (approx, adjust if needed)
        };

        FunctionManager fm = currentProgram.getFunctionManager();
        ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();
        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);

        println("\n=== DECOMPILES ===");
        for (long off : decompileTargets) {
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

        println("\n=== RAW DISASSEMBLY RANGES ===");
        for (long[] range : asmRanges) {
            Address start = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(range[0]);
            Address end = currentProgram.getAddressFactory().getDefaultAddressSpace().getAddress(range[1]);
            println("\n-- range " + start + " .. " + end + " --");
            InstructionIterator it = currentProgram.getListing().getInstructions(
                new AddressSet(start, end), true);
            while (it.hasNext()) {
                Instruction insn = it.next();
                println(insn.getAddress() + ": " + insn.toString());
            }
        }
        println("\nDONE");
    }
}
