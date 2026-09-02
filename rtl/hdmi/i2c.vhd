library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_i2c is
  port(
    CLOCK      : in  std_logic;
    RESET      : in  std_logic;

    I2C_SCL_I  : in  std_logic;
    I2C_SDA_I  : in  std_logic;

    I2C_SCL_OE : out std_logic;  -- '1' = drive low, '0' = release
    I2C_SDA_OE : out std_logic;  -- '1' = drive low, '0' = release

    READY      : out std_logic
  );
end entity;

architecture rtl of hdmi_i2c is
  type byte_array_t is array (0 to 2) of std_logic_vector(7 downto 0);
  constant BYTES : byte_array_t := (x"78", x"08", x"BF"); -- slave, pointer, data

  constant HALF : integer := 63; -- ~400 kHz SCL (50 MHz / (2*63) ≈ 396.8 kHz)
  signal phase_cnt : integer := 0;

  signal sda_oe : std_logic := '0';
  signal scl_oe : std_logic := '0';

  signal state    : integer := 0;
  signal byte_idx : integer range 0 to 2 := 0;
  signal bit_idx  : integer range 0 to 7 := 7;
begin
  I2C_SCL_OE <= scl_oe;
  I2C_SDA_OE <= sda_oe;

  process(CLOCK, RESET)
  begin
    if RESET = '1' then
      READY <= '0';
      sda_oe <= '0';
      scl_oe <= '0';
      state <= 0;
      byte_idx <= 0;
      bit_idx <= 7;
      phase_cnt <= 0;

    elsif rising_edge(CLOCK) then
      case state is
        when 0 =>
          sda_oe <= '0';
          scl_oe <= '0';
          phase_cnt <= 0;
          state <= 1;

        when 1 =>
          sda_oe <= '1';
          scl_oe <= '0';
          phase_cnt <= 0;
          state <= 2;

        when 2 =>
          if phase_cnt < HALF then
            phase_cnt <= phase_cnt + 1;
          else
            phase_cnt <= 0;
            scl_oe <= '1';
            byte_idx <= 0;
            bit_idx <= 7;
            state <= 10;
          end if;

        when 10 =>
          scl_oe <= '1';
          if BYTES(byte_idx)(bit_idx) = '0' then
            sda_oe <= '1';
          else
            sda_oe <= '0';
          end if;
          phase_cnt <= 0;
          state <= 11;

        when 11 =>
          if phase_cnt < HALF then
            phase_cnt <= phase_cnt + 1;
          else
            phase_cnt <= 0;
            scl_oe <= '0';
            state <= 12;
          end if;

        when 12 =>
          if phase_cnt < HALF then
            phase_cnt <= phase_cnt + 1;
          else
            phase_cnt <= 0;
            scl_oe <= '1';
            if bit_idx = 0 then
              state <= 20;
            else
              bit_idx <= bit_idx - 1;
              state <= 10;
            end if;
          end if;

        when 20 =>
          sda_oe <= '0';
          scl_oe <= '1';
          phase_cnt <= 0;
          state <= 21;

        when 21 =>
          if phase_cnt < HALF then
            phase_cnt <= phase_cnt + 1;
          else
            phase_cnt <= 0;
            scl_oe <= '0';
            state <= 22;
          end if;

        when 22 =>
          if phase_cnt < HALF then
            phase_cnt <= phase_cnt + 1;
          else
            phase_cnt <= 0;
            scl_oe <= '1';
            if byte_idx < 2 then
              byte_idx <= byte_idx + 1;
              bit_idx <= 7;
              state <= 10;
            else
              state <= 30;
            end if;
          end if;

        when 30 =>
          scl_oe <= '1';
          sda_oe <= '1';
          phase_cnt <= 0;
          state <= 31;

        when 31 =>
          if phase_cnt < HALF then
            phase_cnt <= phase_cnt + 1;
          else
            phase_cnt <= 0;
            scl_oe <= '0';
            state <= 32;
          end if;

        when 32 =>
          if phase_cnt < HALF then
            phase_cnt <= phase_cnt + 1;
          else
            phase_cnt <= 0;
            sda_oe <= '0';
            state <= 40;
          end if;

        when 40 =>
          if phase_cnt < HALF then
            phase_cnt <= phase_cnt + 1;
          else
            READY <= '1';
            state <= 255;
          end if;

        when others =>
          READY <= '1';
      end case;
    end if;
  end process;
end architecture;
