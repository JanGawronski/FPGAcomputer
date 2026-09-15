library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_i2c is
  generic (
    G_CLOCK_HZ        : positive := 50_000_000;
    G_I2C_HZ          : positive := 400_000;
    G_STARTUP_DELAY_MS : positive := 500
    );
  port(
    CLOCK      : in  std_logic;
    RESET      : in  std_logic;

    I2C_SCL_I  : in  std_logic;
    I2C_SDA_I  : in  std_logic;

    I2C_SCL_OE : out std_logic;  -- '1' = drive low, '0' = release
    I2C_SDA_OE : out std_logic;  -- '1' = drive low, '0' = release

    READY      : out std_logic;
    ERROR      : out std_logic
    );
end entity;

architecture rtl of hdmi_i2c is
  type t_byte_array is array (natural range <>) of std_logic_vector(7 downto 0);
  constant C_BYTES : t_byte_array := (
    x"78", -- TFP410 write address
    x"08", -- CTL_1_MODE register
    x"BF"  -- 24-bit, single-edge, rising-edge capture, power enabled
    );

  constant C_HALF_PERIOD_CYCLES : positive :=
    (G_CLOCK_HZ + G_I2C_HZ) / (2 * G_I2C_HZ) + 1;
  constant C_BUS_TIMEOUT_CYCLES : positive := G_CLOCK_HZ / 1_000;
  constant C_STARTUP_DELAY_CYCLES : positive :=
    (G_CLOCK_HZ / 1_000) * G_STARTUP_DELAY_MS;

  type t_state is (
    idle,
    start_hold,
    bit_setup,
    bit_low,
    bit_high,
    ack_setup,
    ack_low,
    ack_high,
    stop_setup,
    stop_low,
    stop_high,
    stop_release,
    complete,
    failed
    );

  signal state : t_state := idle;

  signal phase_count : natural range 0 to C_HALF_PERIOD_CYCLES - 1 := 0;
  signal bus_timeout_count : natural range 0 to C_BUS_TIMEOUT_CYCLES - 1 := 0;
  signal startup_count : natural range 0 to C_STARTUP_DELAY_CYCLES - 1 := 0;
  signal byte_index : natural range C_BYTES'low to C_BYTES'high := C_BYTES'low;
  signal bit_index  : natural range 0 to 7 := 7;

  signal sda_oe : std_logic := '0';
  signal scl_oe : std_logic := '0';
  signal error_pending : std_logic := '0';
begin
  I2C_SCL_OE <= scl_oe;
  I2C_SDA_OE <= sda_oe;

  process(CLOCK, RESET)
  begin
    if RESET = '1' then
      READY             <= '0';
      ERROR             <= '0';
      sda_oe            <= '0';
      scl_oe            <= '0';
      state             <= idle;
      phase_count       <= 0;
      bus_timeout_count <= 0;
      startup_count     <= 0;
      byte_index        <= C_BYTES'low;
      bit_index         <= 7;
      error_pending     <= '0';
    elsif rising_edge(CLOCK) then
      case state is
        when idle =>
          READY         <= '0';
          ERROR         <= '0';
          error_pending <= '0';
          sda_oe        <= '0';
          scl_oe        <= '0';
          byte_index    <= C_BYTES'low;
          bit_index     <= 7;

          if startup_count < C_STARTUP_DELAY_CYCLES - 1 then
            startup_count     <= startup_count + 1;
            phase_count       <= 0;
            bus_timeout_count <= 0;
          elsif I2C_SCL_I /= '0' and I2C_SDA_I /= '0' then
            bus_timeout_count <= 0;
            if phase_count = C_HALF_PERIOD_CYCLES - 1 then
              phase_count <= 0;
              sda_oe      <= '1';
              state       <= start_hold;
            else
              phase_count <= phase_count + 1;
            end if;
          else
            phase_count <= 0;
            if bus_timeout_count = C_BUS_TIMEOUT_CYCLES - 1 then
              ERROR <= '1';
              state <= failed;
            else
              bus_timeout_count <= bus_timeout_count + 1;
            end if;
          end if;

        when start_hold =>
          if phase_count = C_HALF_PERIOD_CYCLES - 1 then
            phase_count <= 0;
            scl_oe      <= '1';
            state       <= bit_setup;
          else
            phase_count <= phase_count + 1;
          end if;

        when bit_setup =>
          scl_oe <= '1';
          if C_BYTES(byte_index)(bit_index) = '0' then
            sda_oe <= '1';
          else
            sda_oe <= '0';
          end if;
          phase_count <= 0;
          state       <= bit_low;

        when bit_low =>
          if phase_count = C_HALF_PERIOD_CYCLES - 1 then
            phase_count       <= 0;
            bus_timeout_count <= 0;
            scl_oe            <= '0';
            state             <= bit_high;
          else
            phase_count <= phase_count + 1;
          end if;

        when bit_high =>
          if I2C_SCL_I /= '0' then
            bus_timeout_count <= 0;
            if phase_count = C_HALF_PERIOD_CYCLES - 1 then
              phase_count <= 0;
              scl_oe      <= '1';
              if bit_index = 0 then
                state <= ack_setup;
              else
                bit_index <= bit_index - 1;
                state     <= bit_setup;
              end if;
            else
              phase_count <= phase_count + 1;
            end if;
          else
            phase_count <= 0;
            if bus_timeout_count = C_BUS_TIMEOUT_CYCLES - 1 then
              ERROR  <= '1';
              sda_oe <= '0';
              scl_oe <= '0';
              state  <= failed;
            else
              bus_timeout_count <= bus_timeout_count + 1;
            end if;
          end if;

        when ack_setup =>
          scl_oe      <= '1';
          sda_oe      <= '0';
          phase_count <= 0;
          state       <= ack_low;

        when ack_low =>
          if phase_count = C_HALF_PERIOD_CYCLES - 1 then
            phase_count       <= 0;
            bus_timeout_count <= 0;
            scl_oe            <= '0';
            state             <= ack_high;
          else
            phase_count <= phase_count + 1;
          end if;

        when ack_high =>
          if I2C_SCL_I /= '0' then
            bus_timeout_count <= 0;
            if phase_count = C_HALF_PERIOD_CYCLES - 1 then
              phase_count <= 0;
              scl_oe      <= '1';

              if I2C_SDA_I /= '0' then
                error_pending <= '1';
                state         <= stop_setup;
              elsif byte_index = C_BYTES'high then
                state <= stop_setup;
              else
                byte_index <= byte_index + 1;
                bit_index  <= 7;
                state      <= bit_setup;
              end if;
            else
              phase_count <= phase_count + 1;
            end if;
          else
            phase_count <= 0;
            if bus_timeout_count = C_BUS_TIMEOUT_CYCLES - 1 then
              ERROR  <= '1';
              sda_oe <= '0';
              scl_oe <= '0';
              state  <= failed;
            else
              bus_timeout_count <= bus_timeout_count + 1;
            end if;
          end if;

        when stop_setup =>
          scl_oe      <= '1';
          sda_oe      <= '1';
          phase_count <= 0;
          state       <= stop_low;

        when stop_low =>
          if phase_count = C_HALF_PERIOD_CYCLES - 1 then
            phase_count       <= 0;
            bus_timeout_count <= 0;
            scl_oe            <= '0';
            state             <= stop_high;
          else
            phase_count <= phase_count + 1;
          end if;

        when stop_high =>
          if I2C_SCL_I /= '0' then
            bus_timeout_count <= 0;
            if phase_count = C_HALF_PERIOD_CYCLES - 1 then
              phase_count <= 0;
              sda_oe      <= '0';
              state       <= stop_release;
            else
              phase_count <= phase_count + 1;
            end if;
          else
            phase_count <= 0;
            if bus_timeout_count = C_BUS_TIMEOUT_CYCLES - 1 then
              ERROR  <= '1';
              sda_oe <= '0';
              scl_oe <= '0';
              state  <= failed;
            else
              bus_timeout_count <= bus_timeout_count + 1;
            end if;
          end if;

        when stop_release =>
          if phase_count = C_HALF_PERIOD_CYCLES - 1 then
            phase_count <= 0;
            if error_pending = '1' then
              ERROR <= '1';
              state <= failed;
            else
              READY <= '1';
              state <= complete;
            end if;
          else
            phase_count <= phase_count + 1;
          end if;

        when complete =>
          READY  <= '1';
          ERROR  <= '0';
          sda_oe <= '0';
          scl_oe <= '0';

        when failed =>
          READY  <= '0';
          ERROR  <= '1';
          sda_oe <= '0';
          scl_oe <= '0';
      end case;
    end if;
  end process;
end architecture;
