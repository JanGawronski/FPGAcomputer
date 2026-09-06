library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity terminal_text_ram is
  generic (
    G_DEPTH      : positive := 16_080;
    G_ADDR_WIDTH : positive := 14
    );
  port (
    WR_CLK  : in std_logic;
    WR_EN   : in std_logic;
    WR_ADDR : in unsigned(G_ADDR_WIDTH - 1 downto 0);
    WR_DATA : in std_logic_vector(7 downto 0);

    RD_CLK  : in  std_logic;
    RD_ADDR : in  unsigned(G_ADDR_WIDTH - 1 downto 0);
    RD_DATA : out std_logic_vector(7 downto 0)
    );
end entity terminal_text_ram;

architecture rtl of terminal_text_ram is
  type t_ram is array (0 to G_DEPTH - 1) of std_logic_vector(7 downto 0);
  signal mem : t_ram;

  attribute ramstyle : string;
  attribute ramstyle of mem : signal is "M20K";
begin
  assert G_DEPTH <= 2 ** G_ADDR_WIDTH
    report "G_ADDR_WIDTH is too small for G_DEPTH"
    severity failure;

  process (WR_CLK)
  begin
    if rising_edge(WR_CLK) then
      if WR_EN = '1' then
        mem(to_integer(WR_ADDR)) <= WR_DATA;
      end if;
    end if;
  end process;

  process (RD_CLK)
  begin
    if rising_edge(RD_CLK) then
      RD_DATA <= mem(to_integer(RD_ADDR));
    end if;
  end process;
end architecture rtl;
