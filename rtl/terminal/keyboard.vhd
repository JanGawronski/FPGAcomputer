library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity keyboard is
  generic (
    G_CLK_HZ         : positive;
    G_BAUD           : positive
    );
  port (
    CLOCK        : in  std_logic;
    RESET        : in  std_logic;
    ENABLE       : in  std_logic;

    FPGA_UART_RX : in  std_logic;

    CHAR         : out std_logic_vector(7 downto 0)
    );
end entity keyboard;

architecture rtl of keyboard is
  constant C_CLKS_PER_BIT : natural := G_CLK_HZ / G_BAUD;
  constant C_HALF_BIT     : natural := C_CLKS_PER_BIT / 2;

  type t_state is (idle, start_bit, data_bits, stop_bit);
  signal state : t_state := idle;

  signal rx_meta, rx_sync : std_logic := '1';
  signal clk_count        : natural range 0 to C_CLKS_PER_BIT - 1 := 0;
  signal bit_index        : natural range 0 to 7 := 0;
  signal data_byte        : std_logic_vector(7 downto 0) := (others => '0');
  
begin

 process (CLOCK)
  begin
    if rising_edge(CLOCK) then
      rx_meta <= FPGA_UART_RX;
      rx_sync <= rx_meta;
    end if;
  end process;
  
  process (CLOCK)
  begin
    if rising_edge(CLOCK) then
      if RESET = '1' then
        state        <= idle;
        data_byte    <= (others => '0');
        clk_count    <= 0;
        bit_index    <= 0;
        CHAR         <= (others => '0');
      elsif ENABLE = '0' then
        state        <= idle;
        data_byte    <= (others => '0');
        clk_count    <= 0;
        bit_index    <= 0;
        CHAR         <= (others => '0');
      else
        case state is
          when idle =>
            CHAR <= (others => '0');    
            if rx_sync = '0' then
              clk_count <= 0;
              state     <= start_bit;
            end if;

          when start_bit =>
            if clk_count = C_HALF_BIT then
              if rx_sync = '0' then
                clk_count <= 0;
                bit_index <= 0;
                state     <= data_bits;
              else
                state <= idle;
              end if;
            else
              clk_count <= clk_count + 1;
            end if;

          when data_bits =>
            if clk_count = C_CLKS_PER_BIT - 1 then
              clk_count            <= 0;
              data_byte(bit_index) <= rx_sync;
              if bit_index = 7 then
                state <= stop_bit;
              else
                bit_index <= bit_index + 1;
              end if;
            else
              clk_count <= clk_count + 1;
            end if;

          when stop_bit =>
            if clk_count = C_CLKS_PER_BIT - 1 then
              clk_count <= 0;
              state <= idle;
              if rx_sync = '1' then
                CHAR <= data_byte;
              end if;
            else
              clk_count <= clk_count + 1;
            end if;

        end case;
      end if;
    end if;
  end process;
end architecture rtl;
