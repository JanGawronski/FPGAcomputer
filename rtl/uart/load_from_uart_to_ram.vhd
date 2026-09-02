library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity load_from_uart_to_ram is
  generic (
    G_RAM_ADDR_WIDTH : positive;
    G_RAM_DATA_WIDTH : positive;
    G_CLK_HZ         : positive;
    G_BAUD           : positive
    );
  port (
    CLOCK        : in  std_logic;
    RESET        : in  std_logic;
    ENABLE       : in  std_logic;

    FPGA_UART_RX : in  std_logic;

    RAM_START    : in  std_logic_vector(G_RAM_ADDR_WIDTH - 1 downto 0);
    RAM_END      : in  std_logic_vector(G_RAM_ADDR_WIDTH - 1 downto 0);

    RAM_READY    : in  std_logic;
    RAM_VALID    : out std_logic;
    RAM_WRITE    : out std_logic;
    RAM_ADDR     : out std_logic_vector(G_RAM_ADDR_WIDTH - 1 downto 0);
    RAM_WDATA    : out std_logic_vector(G_RAM_DATA_WIDTH - 1 downto 0);
    RAM_BYTE_EN  : out std_logic_vector((G_RAM_DATA_WIDTH / 8) - 1 downto 0);

    DONE         : out std_logic
    );
end entity load_from_uart_to_ram;

architecture rtl of load_from_uart_to_ram is
  constant C_CLKS_PER_BIT : natural := G_CLK_HZ / G_BAUD;
  constant C_HALF_BIT     : natural := C_CLKS_PER_BIT / 2;
  constant C_WORD_BYTES   : natural := G_RAM_DATA_WIDTH / 8;

  type t_state is (idle, start_bit, data_bits, stop_bit, collect_byte, save_word, advance_after_write, done_hold);
  signal state : t_state := idle;

  signal rx_meta, rx_sync : std_logic := '1';
  signal clk_count        : natural range 0 to C_CLKS_PER_BIT - 1 := 0;
  signal bit_index        : natural range 0 to 7 := 0;
  signal data_byte        : std_logic_vector(7 downto 0) := (others => '0');

  signal word_buf       : std_logic_vector(G_RAM_DATA_WIDTH - 1 downto 0) := (others => '0');
  signal byte_index     : natural range 0 to C_WORD_BYTES - 1 := 0;
  signal ram_addr_reg   : unsigned(G_RAM_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal ram_valid_reg  : std_logic := '0';
  signal done_reg       : std_logic := '0';
begin
  assert G_RAM_DATA_WIDTH >= 8
    report "G_RAM_DATA_WIDTH must be at least 8"
    severity failure;
  assert (G_RAM_DATA_WIDTH mod 8) = 0
    report "G_RAM_DATA_WIDTH must be a multiple of 8"
    severity failure;

  RAM_VALID   <= ram_valid_reg;
  RAM_WRITE   <= '1';
  RAM_ADDR    <= std_logic_vector(ram_addr_reg);
  RAM_WDATA   <= word_buf;
  RAM_BYTE_EN <= (others => '1');
  DONE        <= done_reg;

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
      ram_valid_reg <= '0';
      if RESET = '1' then
        state        <= idle;
        clk_count    <= 0;
        bit_index    <= 0;
        byte_index   <= 0;
        word_buf     <= (others => '0');
        ram_addr_reg <= unsigned(RAM_START);
        ram_valid_reg <= '0';
        done_reg     <= '0';
      elsif ENABLE = '0' then
        state        <= idle;
        clk_count    <= 0;
        bit_index    <= 0;
        byte_index   <= 0;
        word_buf     <= (others => '0');
        ram_addr_reg <= unsigned(RAM_START);
        done_reg     <= '0';
      else
        case state is
          when idle =>
            done_reg <= '0';
            if unsigned(RAM_START) > unsigned(RAM_END) then
              done_reg <= '1';
              state    <= done_hold;
            elsif rx_sync = '0' then
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
              if rx_sync = '1' then
                state <= collect_byte;
              else
                state <= idle;
              end if;
            else
              clk_count <= clk_count + 1;
            end if;

          when collect_byte =>
            word_buf((byte_index * 8) + 7 downto byte_index * 8) <= data_byte;
            if byte_index = C_WORD_BYTES - 1 then
              state <= save_word;
            else
              byte_index <= byte_index + 1;
              state      <= idle;
            end if;

          when save_word =>
            if RAM_READY = '1' then
              ram_valid_reg <= '1';
              state         <= advance_after_write;
            end if;

          when advance_after_write =>
            byte_index <= 0;
            if ram_addr_reg = unsigned(RAM_END) then
              done_reg <= '1';
              state    <= done_hold;
            else
              ram_addr_reg <= ram_addr_reg + 1;
              word_buf     <= (others => '0');
              state        <= idle;
            end if;

          when done_hold =>
            done_reg <= '1';
            state    <= done_hold;
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
