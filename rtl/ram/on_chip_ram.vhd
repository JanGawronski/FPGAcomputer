library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity on_chip_ram is
    generic (
        G_ADDR_WIDTH : positive := 24;
        G_DATA_WIDTH : positive := 32;
        G_WORD_COUNT : positive := 65536
    );
    port (
        CLOCK       : in  std_logic;
        RESET       : in  std_logic;

        RAM_VALID   : in  std_logic;
        RAM_WRITE   : in  std_logic;
        RAM_ADDR    : in  std_logic_vector(G_ADDR_WIDTH - 1 downto 0);
        RAM_WDATA   : in  std_logic_vector(G_DATA_WIDTH - 1 downto 0);
        RAM_BYTE_EN : in  std_logic_vector((G_DATA_WIDTH / 8) - 1 downto 0);

        RAM_READY   : out std_logic;
        RAM_RVALID  : out std_logic;
        RAM_RDATA   : out std_logic_vector(G_DATA_WIDTH - 1 downto 0)
    );
end entity on_chip_ram;

architecture rtl of on_chip_ram is
    constant C_BYTE_LANES : positive := G_DATA_WIDTH / 8;
    function f_clog2(n : positive) return positive is
        variable v : natural := n - 1;
        variable r : positive := 1;
    begin
        while v > 1 loop
            v := v / 2;
            r := r + 1;
        end loop;
        return r;
    end function;
    constant C_INDEX_WIDTH : positive := f_clog2(G_WORD_COUNT);

    type t_ram is array (0 to G_WORD_COUNT - 1) of std_logic_vector(G_DATA_WIDTH - 1 downto 0);
    signal ram_mem : t_ram := (others => (others => '0'));

    signal ram_rvalid_reg : std_logic := '0';
    signal ram_rdata_reg  : std_logic_vector(G_DATA_WIDTH - 1 downto 0) := (others => '0');
begin
    assert (G_DATA_WIDTH mod 8) = 0
        report "G_DATA_WIDTH must be a multiple of 8"
        severity failure;

    RAM_READY  <= '1';
    RAM_RVALID <= ram_rvalid_reg;
    RAM_RDATA  <= ram_rdata_reg;

    process (CLOCK)
        variable ram_index : natural range 0 to G_WORD_COUNT - 1;
    begin
        if rising_edge(CLOCK) then
            ram_rvalid_reg <= '0';

            if RESET = '1' then
                ram_rvalid_reg <= '0';
            elsif RAM_VALID = '1' then
                ram_index := to_integer(unsigned(RAM_ADDR(C_INDEX_WIDTH - 1 downto 0)));

                if RAM_WRITE = '1' then
                    for i in 0 to C_BYTE_LANES - 1 loop
                        if RAM_BYTE_EN(i) = '1' then
                            ram_mem(ram_index)((i * 8) + 7 downto i * 8) <= RAM_WDATA((i * 8) + 7 downto i * 8);
                        end if;
                    end loop;
                else
                    ram_rdata_reg  <= ram_mem(ram_index);
                    ram_rvalid_reg <= '1';
                end if;
            end if;
        end if;
    end process;
end architecture rtl;
