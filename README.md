# Computer system in FPGA
Computer system developed for Atum A3 Nano.

## How to run
Requirements:
 - Altera Quartus Prime Pro
 - Atum A3 Nano
 
Compile:
 ```bash
quartus_sh --flow compile quartus/computer
 ```

Program the board:
```bash
quartus_pgm -m jtag -o "p;quartus/output_files/computer.sof"
```
