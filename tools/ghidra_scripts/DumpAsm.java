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
            0x023FD779L, // write sink (run32/36 sender spine)
            0x023F1E26L,
            0x023F0043L,
            0x023EFEC7L,
            0x023A723FL, // upper variant A (597B write path)
            0x023A7154L,
            0x0239D495L,
            0x0232426BL,
            0x0233788BL,
            0x02337A5DL,
            0x01DC6F6AL, // upper frames above 0x2337A5D
            0x01DD65A5L,
        };

        // {startOffset, endOffsetExclusive} ranges to disassemble raw.
        long[][] asmRanges = {
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
