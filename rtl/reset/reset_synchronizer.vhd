library ieee;
use ieee.std_logic_1164.all;

entity reset_synchronizer is
  generic (
    G_STAGES : positive := 2
    );
  port (
    CLOCK         : in  std_logic;
    ASYNC_RESET   : in  std_logic;
    SYNCED_RESET  : out std_logic
    );
end entity reset_synchronizer;

architecture rtl of reset_synchronizer is
  signal reset_sync_chain : std_logic_vector(G_STAGES - 1 downto 0) :=
    (others => '1');
  signal reset_output_reg : std_logic := '1';

  attribute preserve : boolean;
  attribute preserve of reset_sync_chain : signal is true;
begin
  assert G_STAGES >= 2
    report "reset_synchronizer requires at least two resolution stages"
    severity failure;

  process (CLOCK, ASYNC_RESET)
  begin
    if ASYNC_RESET = '1' then
      reset_sync_chain <= (others => '1');
      reset_output_reg <= '1';
    elsif rising_edge(CLOCK) then
      reset_sync_chain(0) <= '0';

      for i in 1 to G_STAGES - 1 loop
        reset_sync_chain(i) <= reset_sync_chain(i - 1);
      end loop;

      reset_output_reg <= reset_sync_chain(G_STAGES - 1);
    end if;
  end process;

  SYNCED_RESET <= reset_output_reg;
end architecture rtl;
