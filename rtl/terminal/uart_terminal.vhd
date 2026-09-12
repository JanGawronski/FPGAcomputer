library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_terminal is
    generic (
        G_CLK_HZ         : positive;
        G_BAUD           : positive
    );
    port (
        CLOCK        : in  std_logic;
        RESET        : in  std_logic;
        ENABLE       : in  std_logic;

        FPGA_UART_TX : out std_logic;

        CHAR         : in  std_logic_vector(7 downto 0)
    );
end entity uart_terminal;

architecture rtl of uart_terminal is
    constant C_CLKS_PER_BIT : natural := G_CLK_HZ / G_BAUD;

    type t_state is (
        idle,
        tx_start,
        tx_data,
        tx_stop
    );
    signal state : t_state := idle;

    signal tx_byte      : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_bit_index : natural range 0 to 7 := 0;
    signal clk_count    : natural range 0 to C_CLKS_PER_BIT - 1 := 0;
begin
    process (CLOCK, RESET)
    begin
        if RESET = '1' then
          state         <= idle;
          tx_byte       <= (others => '0');
          tx_bit_index  <= 0;
          clk_count     <= 0;
      elsif rising_edge(CLOCK) then
        if ENABLE = '0' then
          state         <= idle;
          tx_byte       <= (others => '0');
          tx_bit_index  <= 0;
          clk_count     <= 0;
        else          
          case state is
            when idle =>
              if CHAR /= x"00" then
                tx_byte      <= CHAR;
                tx_bit_index <= 0;
                clk_count    <= 0;              
                state        <= tx_start;
              end if;

            when tx_start =>
              FPGA_UART_TX <= '0';
              if clk_count = C_CLKS_PER_BIT - 1 then
                clk_count <= 0;
                state     <= tx_data;
              else
                clk_count <= clk_count + 1;
              end if;

            when tx_data =>
              FPGA_UART_TX <= tx_byte(tx_bit_index);
              if clk_count = C_CLKS_PER_BIT - 1 then
                clk_count <= 0;
                if tx_bit_index = 7 then
                  state <= tx_stop;
                else
                  tx_bit_index <= tx_bit_index + 1;
                end if;
              else
                clk_count <= clk_count + 1;
              end if;

            when tx_stop =>
              FPGA_UART_TX <= '1';
              if clk_count = C_CLKS_PER_BIT - 1 then
                clk_count <= 0;
                state     <= idle;
              else
                clk_count <= clk_count + 1;
              end if;
              
          end case;
        end if;
      end if;
    end process;
end architecture rtl;
