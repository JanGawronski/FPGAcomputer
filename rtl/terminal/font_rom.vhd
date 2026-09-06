library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity terminal_font_rom is
  port (
    CLOCK : in  std_logic;
    ADDR  : in  unsigned(13 downto 0);
    DATA  : out std_logic
    );
end entity terminal_font_rom;

architecture rtl of terminal_font_rom is
  type t_rom is array (0 to 16_383) of std_logic_vector(0 downto 0);
  signal mem : t_rom;

  attribute ram_init_file : string;
  attribute ram_init_file of mem : signal is "../rtl/terminal/chartable.mif";

  attribute ramstyle : string;
  attribute ramstyle of mem : signal is "M20K";
begin
  process (CLOCK)
  begin
    if rising_edge(CLOCK) then
      DATA <= mem(to_integer(ADDR))(0);
    end if;
  end process;
end architecture rtl;
