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

  signal reading : std_logic := '1';

  constant NOT_FOUND_LENGTH : natural := 11;
  
  signal write_counter : natural range 0 to NOT_FOUND_LENGTH + LINE_WIDTH - 1 := 0;
  
  type byte_array_t is array (0 to NOT_FOUND_LENGTH - 1) of std_logic_vector(7 downto 0);
  constant NOT_FOUND : byte_array_t := (x"4E", x"6F", x"74", x"20", x"66", x"6F", x"75", x"6E", x"64", x"3A", x"20");
  -- NOT_FOUND = "Not found: "
  
begin
  process (CLOCK, RESET)
  begin
    if RESET = '1' then
      cursor <= 0;
      command_line <= (others => (others => '0'));
      OUTPUT_CHAR  <= (others => '0');
      reading <= '1';
      write_counter <= 0;
      DONE   <= '0';
    elsif rising_edge(CLOCK) then
      if ENABLE = '1' then
        if reading = '1' then
          if INPUT_CHAR /= x"00" then
            OUTPUT_CHAR <= INPUT_CHAR;
            if INPUT_CHAR = x"0D" then -- INPUT_CHAR = Enter
              if command_line(0 to 3) = (x"65", x"78", x"69", x"74") then -- exit
                DONE <= '1';
                cursor <= 0;
                command_line <= (others => (others => '0'));
              else
                DONE <= '0';
                if cursor > 0 then
                  reading <= '0';
                  write_counter <= 0;
                else
                  OUTPUT_CHAR <= x"0D";
                end if;
              end if;
            else
              DONE <= '0';
              command_line(cursor) <= INPUT_CHAR;
              cursor <= cursor + 1;            
            end if;  
          else
            OUTPUT_CHAR  <= (others => '0');
            
          end if;
        else
          if write_counter < NOT_FOUND_LENGTH then
            OUTPUT_CHAR <= NOT_FOUND(write_counter);
            write_counter <= write_counter + 1;
          elsif write_counter < NOT_FOUND_LENGTH + cursor then
            OUTPUT_CHAR <= command_line(write_counter - NOT_FOUND_LENGTH);
            write_counter <= write_counter + 1;
          else
            OUTPUT_CHAR <= x"0D"; -- Enter
            write_counter <= 0;
            reading <= '1';
            cursor <= 0;      
            command_line <= (others => (others => '0'));
          end if;
        end if;
      end if;
      
    end if;
  end process;                         

end architecture rtl;
