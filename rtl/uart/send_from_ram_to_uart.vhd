library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity send_from_ram_to_uart is
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

        FPGA_UART_TX : out std_logic;

        RAM_START    : in  std_logic_vector(G_RAM_ADDR_WIDTH - 1 downto 0);
        RAM_END      : in  std_logic_vector(G_RAM_ADDR_WIDTH - 1 downto 0);

        RAM_READY    : in  std_logic;
        RAM_RVALID   : in  std_logic;
        RAM_RDATA    : in  std_logic_vector(G_RAM_DATA_WIDTH - 1 downto 0);

        RAM_VALID    : out std_logic;
        RAM_WRITE    : out std_logic;
        RAM_ADDR     : out std_logic_vector(G_RAM_ADDR_WIDTH - 1 downto 0);
        RAM_WDATA    : out std_logic_vector(G_RAM_DATA_WIDTH - 1 downto 0);
        RAM_BYTE_EN  : out std_logic_vector((G_RAM_DATA_WIDTH / 8) - 1 downto 0);

        DONE         : out std_logic
    );
end entity send_from_ram_to_uart;

architecture rtl of send_from_ram_to_uart is
    constant C_CLKS_PER_BIT : natural := G_CLK_HZ / G_BAUD;
    constant C_WORD_BYTES   : natural := G_RAM_DATA_WIDTH / 8;

    type t_state is (
        idle,
        request_word,
        wait_word,
        load_byte,
        tx_start,
        tx_data,
        tx_stop,
        next_item,
        done_hold
    );
    signal state : t_state := idle;

    signal ram_addr_reg  : unsigned(G_RAM_ADDR_WIDTH - 1 downto 0) := (others => '0');
    signal ram_valid_reg : std_logic := '0';
    signal word_buf      : std_logic_vector(G_RAM_DATA_WIDTH - 1 downto 0) := (others => '0');

    signal byte_index   : natural range 0 to C_WORD_BYTES - 1 := 0;
    signal tx_byte      : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_bit_index : natural range 0 to 7 := 0;
    signal clk_count    : natural range 0 to C_CLKS_PER_BIT - 1 := 0;

    signal tx_reg   : std_logic := '1';
    signal done_reg : std_logic := '0';
begin
    assert G_RAM_DATA_WIDTH >= 8
        report "G_RAM_DATA_WIDTH must be at least 8"
        severity failure;
    assert (G_RAM_DATA_WIDTH mod 8) = 0
        report "G_RAM_DATA_WIDTH must be a multiple of 8"
        severity failure;

    FPGA_UART_TX <= tx_reg;

    RAM_VALID   <= ram_valid_reg;
    RAM_WRITE   <= '0';
    RAM_ADDR    <= std_logic_vector(ram_addr_reg);
    RAM_WDATA   <= (others => '0');
    RAM_BYTE_EN <= (others => '0');
    DONE        <= done_reg;

    process (CLOCK)
    begin
        if rising_edge(CLOCK) then
            ram_valid_reg <= '0';

            if RESET = '1' then
                state         <= idle;
                ram_addr_reg  <= unsigned(RAM_START);
                ram_valid_reg <= '0';
                word_buf      <= (others => '0');
                byte_index    <= 0;
                tx_byte       <= (others => '0');
                tx_bit_index  <= 0;
                clk_count     <= 0;
                tx_reg        <= '1';
                done_reg      <= '0';
            elsif ENABLE = '0' then
                state         <= idle;
                ram_addr_reg  <= unsigned(RAM_START);
                word_buf      <= (others => '0');
                byte_index    <= 0;
                tx_byte       <= (others => '0');
                tx_bit_index  <= 0;
                clk_count     <= 0;
                tx_reg        <= '1';
                done_reg      <= '0';
            else
                case state is
                    when idle =>
                        tx_reg   <= '1';
                        done_reg <= '0';

                        if unsigned(RAM_START) > unsigned(RAM_END) then
                            done_reg <= '1';
                            state    <= done_hold;
                        else
                            state <= request_word;
                        end if;

                    when request_word =>
                        if RAM_READY = '1' then
                            ram_valid_reg <= '1';
                            state         <= wait_word;
                        end if;

                    when wait_word =>
                        if RAM_RVALID = '1' then
                            word_buf   <= RAM_RDATA;
                            byte_index <= 0;
                            state      <= load_byte;
                        end if;

                    when load_byte =>
                        tx_byte      <= word_buf((byte_index * 8) + 7 downto byte_index * 8);
                        tx_bit_index <= 0;
                        clk_count    <= 0;
                        state        <= tx_start;

                    when tx_start =>
                        tx_reg <= '0';
                        if clk_count = C_CLKS_PER_BIT - 1 then
                            clk_count <= 0;
                            state     <= tx_data;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                    when tx_data =>
                        tx_reg <= tx_byte(tx_bit_index);
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
                        tx_reg <= '1';
                        if clk_count = C_CLKS_PER_BIT - 1 then
                            clk_count <= 0;
                            state     <= next_item;
                        else
                            clk_count <= clk_count + 1;
                        end if;

                    when next_item =>
                        if byte_index = C_WORD_BYTES - 1 then
                            if ram_addr_reg = unsigned(RAM_END) then
                                done_reg <= '1';
                                state    <= done_hold;
                            else
                                ram_addr_reg <= ram_addr_reg + 1;
                                state        <= request_word;
                            end if;
                        else
                            byte_index <= byte_index + 1;
                            state      <= load_byte;
                        end if;

                    when done_hold =>
                        tx_reg   <= '1';
                        done_reg <= '1';
                        state    <= done_hold;
                end case;
            end if;
        end if;
    end process;
end architecture rtl;
