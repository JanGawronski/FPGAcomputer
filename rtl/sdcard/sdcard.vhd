library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdcard is
  generic (
    CLK_HZ  : positive := 100_000_000;
    SPI_HZ  : positive := 400_000
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;

    start_rd  : in  std_logic;
    start_wr  : in  std_logic;
    lba       : in  unsigned(31 downto 0);

    busy      : out std_logic;
    done      : out std_logic;
    error     : out std_logic;

    -- SPI pins to the card socket
    sd_clk    : out std_logic;
    sd_cmd    : out std_logic;  -- MOSI
    sd_dat0   : in  std_logic;  -- MISO
    sd_dat3   : out std_logic;  -- CS_n

    -- External 512-byte buffer RAM
    ram_addr  : out unsigned(8 downto 0);
    ram_din   : out std_logic_vector(7 downto 0);
    ram_dout  : in  std_logic_vector(7 downto 0);
    ram_we    : out std_logic
  );
end entity;

architecture rtl of sdcard is

  function max_nat(a, b : natural) return natural is
  begin
    if a > b then
      return a;
    else
      return b;
    end if;
  end function;

  constant SPI_DIV_HALF : natural := max_nat(1, CLK_HZ / (2 * SPI_HZ));

  function lba_to_arg(l : unsigned(31 downto 0); highcap : std_logic)
    return std_logic_vector
  is
    variable a : unsigned(31 downto 0);
  begin
    if highcap = '1' then
      a := l;                 -- SDHC/SDXC: block addressing
    else
      a := shift_left(l, 9);  -- SDSC: byte addressing
    end if;
    return std_logic_vector(a);
  end function;

  type state_t is (
    S_IDLE,
    S_PWRUP,

    S_CMD0_SEND,  S_CMD0_R1,

    S_CMD8_SEND,  S_CMD8_R1,
    S_CMD8_R7_3,  S_CMD8_R7_2,  S_CMD8_R7_1,  S_CMD8_R7_0,

    S_CMD55_SEND, S_CMD55_R1,
    S_ACMD41_SEND, S_ACMD41_R1,

    S_CMD58_SEND, S_CMD58_R1,
    S_CMD58_OCR_3, S_CMD58_OCR_2, S_CMD58_OCR_1, S_CMD58_OCR_0,

    S_CMD16_SEND, S_CMD16_R1,

    S_READY,

    S_CMD17_SEND, S_CMD17_R1, S_CMD17_TOKEN, S_CMD17_DATA, S_CMD17_CRC1, S_CMD17_CRC2,

    S_CMD24_SEND, S_CMD24_R1, S_CMD24_TOKEN,
    S_CMD24_REQ, S_CMD24_SEND_BYTE, S_CMD24_WAIT_BYTE,
    S_CMD24_CRC1, S_CMD24_CRC2,
    S_CMD24_WAIT_RESP, S_CMD24_WAIT_BUSY,

    S_DONE,
    S_ERROR
  );

  signal st            : state_t := S_IDLE;

  signal cmd_idx       : integer range 0 to 5 := 0;
  signal dummy_cnt     : integer range 0 to 15 := 0;
  signal init_try      : integer range 0 to 4095 := 0;

  signal is_write      : std_logic := '0';
  signal sd_v2         : std_logic := '1';
  signal high_capacity : std_logic := '0';

  signal tx_byte       : std_logic_vector(7 downto 0) := (others => '1');
  signal rx_byte       : std_logic_vector(7 downto 0) := (others => '1');

  signal byte_start    : std_logic := '0';
  signal byte_busy     : std_logic := '0';
  signal byte_done     : std_logic := '0';

  signal spi_div_cnt   : natural range 0 to SPI_DIV_HALF - 1 := 0;
  signal spi_phase     : std_logic := '0';  -- 0 = drive, 1 = sample
  signal spi_bit_cnt   : integer range 0 to 7 := 7;
  signal tx_shift      : std_logic_vector(7 downto 0) := (others => '1');
  signal rx_shift      : std_logic_vector(7 downto 0) := (others => '1');

  signal byte_idx      : integer range 0 to 511 := 0;

  signal start_prev    : std_logic := '0';

begin

  -----------------------------------------------------------------------------
  -- SPI byte engine: transfers one byte per byte_start pulse.
  -- Mode 0 behavior:
  --   drive MOSI on one half-cycle, sample MISO on the other.
  -----------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        sd_clk     <= '0';
        sd_cmd     <= '1';
        byte_busy  <= '0';
        byte_done  <= '0';
        spi_div_cnt <= 0;
        spi_phase  <= '0';
        spi_bit_cnt <= 7;
        tx_shift   <= (others => '1');
        rx_shift   <= (others => '1');
        rx_byte    <= (others => '1');
      else
        byte_done <= '0';

        if byte_start = '1' and byte_busy = '0' then
          byte_busy   <= '1';
          spi_div_cnt <= 0;
          spi_phase   <= '0';
          spi_bit_cnt <= 7;
          tx_shift    <= tx_byte;
          rx_shift    <= (others => '1');
          sd_clk      <= '0';
          sd_cmd      <= '1';
        elsif byte_busy = '1' then
          if spi_div_cnt = SPI_DIV_HALF - 1 then
            spi_div_cnt <= 0;

            if spi_phase = '0' then
              -- drive MOSI, raise clock
              sd_cmd     <= tx_shift(7);
              tx_shift   <= tx_shift(6 downto 0) & '1';
              sd_clk     <= '1';
              spi_phase  <= '1';
            else
              -- sample MISO, lower clock
              rx_shift   <= rx_shift(6 downto 0) & sd_dat0;
              sd_clk     <= '0';
              spi_phase  <= '0';

              if spi_bit_cnt = 0 then
                byte_busy <= '0';
                byte_done <= '1';
                rx_byte   <= rx_shift(6 downto 0) & sd_dat0;
              else
                spi_bit_cnt <= spi_bit_cnt - 1;
              end if;
            end if;
          else
            spi_div_cnt <= spi_div_cnt + 1;
          end if;
        else
          sd_clk <= '0';
        end if;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Main controller FSM
  -----------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        st            <= S_IDLE;
        busy          <= '0';
        done          <= '0';
        error         <= '0';
        sd_dat3       <= '1';

        byte_start    <= '0';
        tx_byte       <= (others => '1');

        cmd_idx       <= 0;
        dummy_cnt     <= 0;
        init_try      <= 0;
        is_write      <= '0';
        sd_v2         <= '1';
        high_capacity <= '0';
        byte_idx      <= 0;

        ram_addr      <= (others => '0');
        ram_din       <= (others => '0');
        ram_we        <= '0';

        start_prev    <= '0';
      else
        done       <= '0';
        error      <= '0';
        byte_start <= '0';
        ram_we     <= '0';

        -- edge detect for start request
        if (start_rd = '1' or start_wr = '1') and start_prev = '0' then
          if st = S_IDLE then
            busy     <= '1';
            is_write <= start_wr;
            dummy_cnt <= 0;
            init_try  <= 0;
            sd_dat3   <= '1';  -- deselect during power-up clocks
            st        <= S_PWRUP;
          end if;
        end if;
        start_prev <= (start_rd or start_wr);

        case st is

          -----------------------------------------------------------------------
          -- Power-up clocks with CS high
          -----------------------------------------------------------------------
          when S_PWRUP =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
              if dummy_cnt = 9 then
                cmd_idx <= 0;
                st <= S_CMD0_SEND;
              else
                dummy_cnt <= dummy_cnt + 1;
              end if;
            end if;

          -----------------------------------------------------------------------
          -- CMD0: GO_IDLE_STATE
          -----------------------------------------------------------------------
          when S_CMD0_SEND =>
            sd_dat3 <= '0';
            if byte_busy = '0' then
              case cmd_idx is
                when 0 => tx_byte <= x"40";
                when 1 => tx_byte <= x"00";
                when 2 => tx_byte <= x"00";
                when 3 => tx_byte <= x"00";
                when 4 => tx_byte <= x"00";
                when others => tx_byte <= x"95";
              end case;
              byte_start <= '1';
              if cmd_idx = 5 then
                cmd_idx <= 0;
                st <= S_CMD0_R1;
              else
                cmd_idx <= cmd_idx + 1;
              end if;
            end if;

          when S_CMD0_R1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              if rx_byte = x"01" then
                cmd_idx <= 0;
                st <= S_CMD8_SEND;
              else
                st <= S_ERROR;
              end if;
            end if;

          -----------------------------------------------------------------------
          -- CMD8: SEND_IF_COND
          -----------------------------------------------------------------------
          when S_CMD8_SEND =>
            if byte_busy = '0' then
              case cmd_idx is
                when 0 => tx_byte <= x"48";
                when 1 => tx_byte <= x"00";
                when 2 => tx_byte <= x"00";
                when 3 => tx_byte <= x"01";
                when 4 => tx_byte <= x"AA";
                when others => tx_byte <= x"87";
              end case;
              byte_start <= '1';
              if cmd_idx = 5 then
                cmd_idx <= 0;
                st <= S_CMD8_R1;
              else
                cmd_idx <= cmd_idx + 1;
              end if;
            end if;

          when S_CMD8_R1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              if rx_byte = x"01" then
                sd_v2 <= '1';
              elsif rx_byte = x"05" then
                sd_v2 <= '0';  -- illegal command on old card, but continue
              else
                st <= S_ERROR;
              end if;
              st <= S_CMD8_R7_3;
            end if;

          when S_CMD8_R7_3 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;
            if byte_done = '1' then
              st <= S_CMD8_R7_2;
            end if;

          when S_CMD8_R7_2 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;
            if byte_done = '1' then
              st <= S_CMD8_R7_1;
            end if;

          when S_CMD8_R7_1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;
            if byte_done = '1' then
              st <= S_CMD8_R7_0;
            end if;

          when S_CMD8_R7_0 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;
            if byte_done = '1' then
              cmd_idx <= 0;
              st <= S_CMD55_SEND;
            end if;

          -----------------------------------------------------------------------
          -- ACMD41 = CMD55 + CMD41 loop
          -----------------------------------------------------------------------
          when S_CMD55_SEND =>
            if byte_busy = '0' then
              case cmd_idx is
                when 0 => tx_byte <= x"77"; -- CMD55
                when 1 => tx_byte <= x"00";
                when 2 => tx_byte <= x"00";
                when 3 => tx_byte <= x"00";
                when 4 => tx_byte <= x"00";
                when others => tx_byte <= x"01";
              end case;
              byte_start <= '1';
              if cmd_idx = 5 then
                cmd_idx <= 0;
                st <= S_CMD55_R1;
              else
                cmd_idx <= cmd_idx + 1;
              end if;
            end if;

          when S_CMD55_R1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              if rx_byte = x"FF" then
                null;
              elsif rx_byte(0) = '1' then
                st <= S_ACMD41_SEND;
              else
                st <= S_ERROR;
              end if;
            end if;

          when S_ACMD41_SEND =>
            if byte_busy = '0' then
              case cmd_idx is
                when 0 => tx_byte <= x"69"; -- ACMD41
                when 1 =>
                  if sd_v2 = '1' then
                    tx_byte <= x"40";       -- HCS = 1 for SDHC/SDXC
                  else
                    tx_byte <= x"00";
                  end if;
                when 2 => tx_byte <= x"00";
                when 3 => tx_byte <= x"00";
                when 4 => tx_byte <= x"00";
                when others => tx_byte <= x"01";
              end case;
              byte_start <= '1';
              if cmd_idx = 5 then
                cmd_idx <= 0;
                st <= S_ACMD41_R1;
              else
                cmd_idx <= cmd_idx + 1;
              end if;
            end if;

          when S_ACMD41_R1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              if rx_byte = x"00" then
                cmd_idx <= 0;
                st <= S_CMD58_SEND;
              elsif init_try = 4095 then
                st <= S_ERROR;
              else
                init_try <= init_try + 1;
                st <= S_CMD55_SEND;
              end if;
            end if;

          -----------------------------------------------------------------------
          -- CMD58: READ_OCR
          -----------------------------------------------------------------------
          when S_CMD58_SEND =>
            if byte_busy = '0' then
              case cmd_idx is
                when 0 => tx_byte <= x"7A";
                when 1 => tx_byte <= x"00";
                when 2 => tx_byte <= x"00";
                when 3 => tx_byte <= x"00";
                when 4 => tx_byte <= x"00";
                when others => tx_byte <= x"01";
              end case;
              byte_start <= '1';
              if cmd_idx = 5 then
                cmd_idx <= 0;
                st <= S_CMD58_R1;
              else
                cmd_idx <= cmd_idx + 1;
              end if;
            end if;

          when S_CMD58_R1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              if rx_byte = x"00" or rx_byte = x"01" then
                st <= S_CMD58_OCR_3;
              else
                st <= S_ERROR;
              end if;
            end if;

          when S_CMD58_OCR_3 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;
            if byte_done = '1' then
              -- bit 30 = bit 6 of the first OCR byte
              if rx_byte(6) = '1' then
                high_capacity <= '1';
              else
                high_capacity <= '0';
              end if;
              st <= S_CMD58_OCR_2;
            end if;

          when S_CMD58_OCR_2 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;
            if byte_done = '1' then
              st <= S_CMD58_OCR_1;
            end if;

          when S_CMD58_OCR_1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;
            if byte_done = '1' then
              st <= S_CMD58_OCR_0;
            end if;

          when S_CMD58_OCR_0 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;
            if byte_done = '1' then
              if high_capacity = '0' then
                cmd_idx <= 0;
                st <= S_CMD16_SEND;
              else
                st <= S_READY;
              end if;
            end if;

          -----------------------------------------------------------------------
          -- CMD16: set block length to 512 on SDSC cards
          -----------------------------------------------------------------------
          when S_CMD16_SEND =>
            if byte_busy = '0' then
              case cmd_idx is
                when 0 => tx_byte <= x"50";
                when 1 => tx_byte <= x"00";
                when 2 => tx_byte <= x"00";
                when 3 => tx_byte <= x"02";
                when 4 => tx_byte <= x"00";
                when others => tx_byte <= x"01";
              end case;
              byte_start <= '1';
              if cmd_idx = 5 then
                cmd_idx <= 0;
                st <= S_CMD16_R1;
              else
                cmd_idx <= cmd_idx + 1;
              end if;
            end if;

          when S_CMD16_R1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              if rx_byte = x"00" then
                st <= S_READY;
              else
                st <= S_ERROR;
              end if;
            end if;

          -----------------------------------------------------------------------
          -- Ready
          -----------------------------------------------------------------------
          when S_READY =>
            busy    <= '0';
            sd_dat3 <= '0';
            if start_rd = '1' then
              is_write <= '0';
              byte_idx <= 0;
              cmd_idx  <= 0;
              st <= S_CMD17_SEND;
              busy <= '1';
            elsif start_wr = '1' then
              is_write <= '1';
              byte_idx <= 0;
              cmd_idx  <= 0;
              st <= S_CMD24_SEND;
              busy <= '1';
            end if;

          -----------------------------------------------------------------------
          -- CMD17: read one block
          -----------------------------------------------------------------------
          when S_CMD17_SEND =>
            if byte_busy = '0' then
              case cmd_idx is
                when 0 => tx_byte <= x"51";
                when 1 => tx_byte <= lba_to_arg(lba, high_capacity)(31 downto 24);
                when 2 => tx_byte <= lba_to_arg(lba, high_capacity)(23 downto 16);
                when 3 => tx_byte <= lba_to_arg(lba, high_capacity)(15 downto 8);
                when 4 => tx_byte <= lba_to_arg(lba, high_capacity)(7 downto 0);
                when others => tx_byte <= x"01";
              end case;
              byte_start <= '1';
              if cmd_idx = 5 then
                cmd_idx <= 0;
                st <= S_CMD17_R1;
              else
                cmd_idx <= cmd_idx + 1;
              end if;
            end if;

          when S_CMD17_R1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              if rx_byte = x"00" then
                st <= S_CMD17_TOKEN;
              else
                st <= S_ERROR;
              end if;
            end if;

          when S_CMD17_TOKEN =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              if rx_byte = x"FE" then
                byte_idx <= 0;
                st <= S_CMD17_DATA;
              end if;
            end if;

          when S_CMD17_DATA =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              ram_addr <= to_unsigned(byte_idx, ram_addr'length);
              ram_din  <= rx_byte;
              ram_we   <= '1';

              if byte_idx = 511 then
                st <= S_CMD17_CRC1;
              else
                byte_idx <= byte_idx + 1;
              end if;
            end if;

          when S_CMD17_CRC1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
              st <= S_CMD17_CRC2;
            end if;

          when S_CMD17_CRC2 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              st <= S_DONE;
            end if;

          -----------------------------------------------------------------------
          -- CMD24: write one block
          -----------------------------------------------------------------------
          when S_CMD24_SEND =>
            if byte_busy = '0' then
              case cmd_idx is
                when 0 => tx_byte <= x"58";
                when 1 => tx_byte <= lba_to_arg(lba, high_capacity)(31 downto 24);
                when 2 => tx_byte <= lba_to_arg(lba, high_capacity)(23 downto 16);
                when 3 => tx_byte <= lba_to_arg(lba, high_capacity)(15 downto 8);
                when 4 => tx_byte <= lba_to_arg(lba, high_capacity)(7 downto 0);
                when others => tx_byte <= x"01";
              end case;
              byte_start <= '1';
              if cmd_idx = 5 then
                cmd_idx <= 0;
                st <= S_CMD24_R1;
              else
                cmd_idx <= cmd_idx + 1;
              end if;
            end if;

          when S_CMD24_R1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              if rx_byte = x"00" then
                st <= S_CMD24_TOKEN;
              else
                st <= S_ERROR;
              end if;
            end if;

          when S_CMD24_TOKEN =>
            if byte_busy = '0' then
              tx_byte    <= x"FE";  -- data token
              byte_start <= '1';
              byte_idx   <= 0;
              st <= S_CMD24_REQ;
            end if;

          -- request RAM byte (one cycle for synchronous RAM)
          when S_CMD24_REQ =>
            ram_addr <= to_unsigned(byte_idx, ram_addr'length);
            st <= S_CMD24_SEND_BYTE;

          when S_CMD24_SEND_BYTE =>
            if byte_busy = '0' then
              tx_byte    <= ram_dout;
              byte_start <= '1';
              st <= S_CMD24_WAIT_BYTE;
            end if;

          when S_CMD24_WAIT_BYTE =>
            if byte_done = '1' then
              if byte_idx = 511 then
                st <= S_CMD24_CRC1;
              else
                byte_idx <= byte_idx + 1;
                st <= S_CMD24_REQ;
              end if;
            end if;

          when S_CMD24_CRC1 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
              st <= S_CMD24_CRC2;
            end if;

          when S_CMD24_CRC2 =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
              st <= S_CMD24_WAIT_RESP;
            end if;

          when S_CMD24_WAIT_RESP =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              -- data response token: accepted = 0x05 in low 5 bits
              if (rx_byte and x"1F") = x"05" then
                st <= S_CMD24_WAIT_BUSY;
              else
                st <= S_ERROR;
              end if;
            end if;

          when S_CMD24_WAIT_BUSY =>
            if byte_busy = '0' then
              tx_byte    <= x"FF";
              byte_start <= '1';
            end if;

            if byte_done = '1' then
              if rx_byte = x"FF" then
                st <= S_DONE;
              end if;
            end if;

          -----------------------------------------------------------------------
          -- Finish
          -----------------------------------------------------------------------
          when S_DONE =>
            busy    <= '0';
            done    <= '1';
            sd_dat3 <= '1';
            st      <= S_IDLE;

          when S_ERROR =>
            busy    <= '0';
            error   <= '1';
            sd_dat3 <= '1';
            st      <= S_IDLE;

          when others =>
            busy    <= '0';
            done    <= '0';
            error   <= '1';
            sd_dat3 <= '1';
            st      <= S_IDLE;
            
        end case;
      end if;
    end if;
  end process;

end architecture;
