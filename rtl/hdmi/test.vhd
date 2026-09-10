library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity hdmi_test is
  port(
    CLOCK        : in  std_logic;
    PIXEL_CLK    : in  std_logic;
    RESET_50     : in  std_logic;
    RESET_PIXEL  : in  std_logic;

    HDMI_I2C_SCL_I  : in  std_logic;
    HDMI_I2C_SDA_I  : in  std_logic;
    HDMI_I2C_SCL_OE : out std_logic;
    HDMI_I2C_SDA_OE : out std_logic;

    HDMI_TX_HS    : out std_logic;
    HDMI_TX_VS    : out std_logic;
    HDMI_TX_D     : out std_logic_vector(23 downto 0);
    HDMI_TX_DE    : out std_logic;
    HDMI_TX_CLK_p : out std_logic;

    HDMI_ISEL  : out std_logic;
    HDMI_PD_n  : out std_logic;

    READY : out std_logic
  );
end entity hdmi_test;

architecture rtl of hdmi_test is
  signal i2c_ready : std_logic := '0';

  constant H_TOTAL : integer := 2199;
  constant H_SYNC  : integer := 43;
  constant H_START : integer := 189;
  constant H_END   : integer := 2109;

  constant V_TOTAL    : integer := 1124;
  constant V_SYNC     : integer := 4;
  constant V_START    : integer := 40;
  constant V_END      : integer := 1120;

  constant V_ACTIVE_14 : integer := 310;
  constant V_ACTIVE_24 : integer := 580;
  constant V_ACTIVE_34 : integer := 850;

  signal h_count : integer range 0 to H_TOTAL := 0;
  signal v_count : integer range 0 to V_TOTAL := 0;
  signal pixel_x : unsigned(7 downto 0) := (others => '0');

  signal h_act    : std_logic := '0';
  signal h_act_d  : std_logic := '0';
  signal v_act    : std_logic := '0';
  signal v_act_d  : std_logic := '0';

  signal pre_vga_de : std_logic := '0';
  signal vga_de      : std_logic := '0';
  signal boarder     : std_logic := '0';
  signal color_mode  : std_logic_vector(3 downto 0) := (others => '0');

  signal vga_hs : std_logic := '1';
  signal vga_vs : std_logic := '1';
  signal vga_r  : std_logic_vector(7 downto 0) := (others => '0');
  signal vga_g  : std_logic_vector(7 downto 0) := (others => '0');
  signal vga_b  : std_logic_vector(7 downto 0) := (others => '0');

begin
  u_i2c : entity work.hdmi_i2c
  port map(
    CLOCK      => CLOCK,
    RESET      => RESET_50,
    I2C_SCL_I  => HDMI_I2C_SCL_I,
    I2C_SDA_I  => HDMI_I2C_SDA_I,
    I2C_SCL_OE => HDMI_I2C_SCL_OE,
    I2C_SDA_OE => HDMI_I2C_SDA_OE,
    READY      => i2c_ready
  );
  
  READY <= i2c_ready;

  HDMI_ISEL <= not RESET_50;
  HDMI_PD_n <= '1';
  
  HDMI_TX_CLK_p <= not PIXEL_CLK;

  process(PIXEL_CLK, RESET_PIXEL)
  begin
    if RESET_PIXEL = '1' then
      h_count     <= 0;
      v_count     <= 0;
      pixel_x     <= (others => '0');
      h_act       <= '0';
      h_act_d     <= '0';
      v_act       <= '0';
      v_act_d     <= '0';
      pre_vga_de  <= '0';
      vga_de      <= '0';
      boarder     <= '0';
      color_mode  <= (others => '0');
      vga_hs      <= '1';
      vga_vs      <= '1';
      vga_r       <= (others => '0');
      vga_g       <= (others => '0');
      vga_b       <= (others => '0');
    elsif rising_edge(PIXEL_CLK) then
      h_act_d <= h_act;

      if h_count = H_TOTAL then
        h_count <= 0;
      else
        h_count <= h_count + 1;
      end if;

      if h_act_d = '1' then
        pixel_x <= pixel_x + 1;
      else
        pixel_x <= (others => '0');
      end if;

      if (h_count >= H_SYNC) and (h_count < H_TOTAL) then
        vga_hs <= '1';
      else
        vga_hs <= '0';
      end if;

      if h_count = H_START then
        h_act <= '1';
      elsif h_count = H_END then
        h_act <= '0';
      end if;

      if h_count = H_TOTAL then
        v_act_d <= v_act;
        if v_count = V_TOTAL then
          v_count <= 0;
        else
          v_count <= v_count + 1;
        end if;

        if (v_count >= V_SYNC) and (v_count < V_TOTAL) then
          vga_vs <= '1';
        else
          vga_vs <= '0';
        end if;

        if v_count = V_START then
          v_act <= '1';
        elsif v_count = V_END then
          v_act <= '0';
        end if;

        if v_count = V_START then
          color_mode(0) <= '1';
        elsif v_count = V_ACTIVE_14 then
          color_mode(0) <= '0';
        end if;

        if v_count = V_ACTIVE_14 then
          color_mode(1) <= '1';
        elsif v_count = V_ACTIVE_24 then
          color_mode(1) <= '0';
        end if;

        if v_count = V_ACTIVE_24 then
          color_mode(2) <= '1';
        elsif v_count = V_ACTIVE_34 then
          color_mode(2) <= '0';
        end if;

        if v_count = V_ACTIVE_34 then
          color_mode(3) <= '1';
        elsif v_count = V_END then
          color_mode(3) <= '0';
        end if;
      end if;

      if (v_act = '1' and h_act = '1') then
        pre_vga_de <= '1';
      else
        pre_vga_de <= '0';
      end if;
      vga_de <= pre_vga_de;

      if ((h_act_d = '0' and h_act = '1') or (h_count = H_END) or (v_act_d = '0' and v_act = '1') or (v_count = V_END)) then
        boarder <= '1';
      else
        boarder <= '0';
      end if;

      if boarder = '1' then
        vga_r <= (others => '1');
        vga_g <= (others => '1');
        vga_b <= (others => '1');
      else
        case color_mode is
          when "0001" =>
            vga_r <= std_logic_vector(pixel_x);
            vga_g <= (others => '0');
            vga_b <= (others => '0');
          when "0010" =>
            vga_r <= (others => '0');
            vga_g <= std_logic_vector(pixel_x);
            vga_b <= (others => '0');
          when "0100" =>
            vga_r <= (others => '0');
            vga_g <= (others => '0');
            vga_b <= std_logic_vector(pixel_x);
          when "1000" =>
            vga_r <= std_logic_vector(pixel_x);
            vga_g <= std_logic_vector(pixel_x);
            vga_b <= std_logic_vector(pixel_x);
          when others =>
            vga_r <= (others => '0');
            vga_g <= (others => '0');
            vga_b <= (others => '0');
        end case;
      end if;

    end if;
  end process;

  HDMI_TX_HS <= vga_hs;
  HDMI_TX_VS <= vga_vs;
  HDMI_TX_DE <= vga_de;
  HDMI_TX_D  <= vga_r & vga_g & vga_b;

end architecture rtl;
