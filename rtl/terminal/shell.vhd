library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity shell is
  port(
    CLOCK       : in  std_logic;
    RESET       : in  std_logic;
    ENABLE      : in  std_logic;

    INPUT_CHAR  : in  std_logic_vector(7 downto 0);
    OUTPUT_CHAR : out std_logic_vector(7 downto 0);
    
    DONE  : out std_logic
    );
end entity shell;

architecture rtl of shell is
  constant LINE_WIDTH : natural := 20;

  type t_line is array (0 to LINE_WIDTH - 1) of std_logic_vector(7 downto 0);
  signal command_line : t_line := (others => (others => '0'));

  signal cursor : natural range 0 to LINE_WIDTH - 1 := 0;
  
begin
  process (CLOCK, RESET)
  begin
    if RESET = '1' then
      cursor <= 0;
      command_line <= (others => (others => '0'));
      OUTPUT_CHAR  <= (others => '0');
      DONE   <= '0';
    elsif rising_edge(CLOCK) then
      if ENABLE = '1' then
        if INPUT_CHAR /= x"0" then
          if INPUT_CHAR = x"0D" then
            DONE <= '0';
          end if;
          OUTPUT_CHAR <= INPUT_CHAR;
          command_line(cursor) <= INPUT_CHAR;
          cursor <= cursor + 1;
        else
          OUTPUT_CHAR  <= (others => '0');            
        end if;
      end if;
    end if;
  end process;                         

end architecture rtl;
