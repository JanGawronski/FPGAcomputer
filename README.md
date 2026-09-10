# Computer system in FPGA
Computer system developed for Atum A3 Nano.

## How to run
Requirements:
 - Altera Quartus Prime Pro
 - Atum A3 Nano
 
### IP generation
After fresh checkout and after every change of `.ip` files IP should generated.
```bash
quartus_ipgenerate --generate_project_ip_files --synthesis=vhdl quartus/computer
```

### Compilation
```bash
quartus_sh --flow compile quartus/computer
 ```

### Programming the board
```bash
quartus_pgm -m jtag -o "p;quartus/output_files/computer.sof"
```
