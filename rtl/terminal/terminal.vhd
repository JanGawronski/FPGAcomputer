library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity terminal is
  port(
    CLOCK        : in  std_logic;
    PIXEL_CLK    : in  std_logic;
    RESET_50     : in  std_logic;
    RESET_PIXEL  : in  std_logic;
    ENABLE       : in  std_logic;
    FPGA_UART_RX : in  std_logic;  
    
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

    RAM_READY  : in  std_logic;
    RAM_RVALID : in  std_logic;
    RAM_RDATA  : in  std_logic_vector(31 downto 0);
    RAM_VALID  : out std_logic;
    RAM_WRITE  : out std_logic;
    RAM_ADDR   : out std_logic_vector(24 - 1 downto 0);
    RAM_WDATA  : out std_logic_vector(31 downto 0);

    SD_CLK     : out    std_logic;
    SD_DATA    : inout  std_logic_vector(3 downto 0);
    SD_CMD     : inout  std_logic;
    
    READY : out std_logic;
    DONE  : out std_logic
    );
end entity terminal;

architecture rtl of terminal is
  constant FONT_HEIGHT : positive := 16;
  constant FONT_WIDTH  : positive := 8;

  constant H_TOTAL   : natural := 2199;
  constant H_SYNC    : natural := 43;
  constant H_START   : natural := 189;
  constant H_END     : natural := 2109;
  constant H_VISIBLE : natural := 1920;

  constant V_TOTAL   : natural := 1124;
  constant V_SYNC    : natural := 4;
  constant V_START   : natural := 40;
  constant V_END     : natural := 1120;
  constant V_VISIBLE : natural := 1080;

  constant LINE_WIDTH       : positive := H_VISIBLE / FONT_WIDTH;
  constant LINE_COUNT       : positive := V_VISIBLE / FONT_HEIGHT;
  constant TEXT_DEPTH       : positive := LINE_WIDTH * LINE_COUNT;
  constant TEXT_ADDR_WIDTH  : positive := 14;
  constant TEXT_PIXEL_HEIGHT : positive := LINE_COUNT * FONT_HEIGHT;

  signal i2c_ready : std_logic := '0';

  signal h_count : natural range 0 to H_TOTAL := 0;
  signal v_count : natural range 0 to V_TOTAL := 0;

  signal video_hs_s0 : std_logic;
  signal video_vs_s0 : std_logic;
  signal video_de_s0 : std_logic;
  signal video_hs_d1 : std_logic := '1';
  signal video_hs_d2 : std_logic := '1';
  signal video_vs_d1 : std_logic := '1';
  signal video_vs_d2 : std_logic := '1';
  signal video_de_d1 : std_logic := '0';
  signal video_de_d2 : std_logic := '0';

  signal text_visible_s0 : std_logic := '0';
  signal text_visible_d1 : std_logic := '0';
  signal text_visible_d2 : std_logic := '0';
  signal glyph_x_s0      : natural range 0 to FONT_WIDTH - 1 := 0;
  signal glyph_x_d1      : natural range 0 to FONT_WIDTH - 1 := 0;
  signal glyph_y_s0      : natural range 0 to FONT_HEIGHT - 1 := 0;
  signal glyph_y_d1      : natural range 0 to FONT_HEIGHT - 1 := 0;

  signal text_wr_en   : std_logic := '0';
  signal text_wr_addr : unsigned(TEXT_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal text_wr_data : std_logic_vector(7 downto 0) := (others => '0');
  signal text_rd_addr : unsigned(TEXT_ADDR_WIDTH - 1 downto 0) := (others => '0');
  signal text_rd_char : std_logic_vector(7 downto 0) := (others => '0');

  signal font_char_code : std_logic_vector(6 downto 0) := (others => '0');
  signal font_rd_addr   : unsigned(13 downto 0) := (others => '0');
  signal font_pixel     : std_logic := '0';

  signal clear_active : std_logic := '1';
  signal clear_addr   : natural range 0 to TEXT_DEPTH - 1 := 0;
  signal cursor_addr  : natural range 0 to TEXT_DEPTH - 1 := 0;

  signal char                 : std_logic_vector(7 downto 0) := (others => '0');
  signal differential         : std_logic := '0';
  signal last_differential_50 : std_logic := '0';
  signal keyboard_enable      : std_logic := '0';

  signal enable_meta  : std_logic := '0';
  signal enable_pixel : std_logic := '0';
  signal clear_meta   : std_logic := '1';
  signal clear_pixel  : std_logic := '1';

  signal sd_start_rd : std_logic;
  signal sd_start_wr : std_logic; 
  signal sd_lba      : unsigned(31 downto 0);
  signal sd_busy     : std_logic;
  signal sd_done     : std_logic;
  signal sd_error    : std_logic;
  signal sd_addr     : unsigned(8 downto 0);
  signal sd_din      : std_logic_vector(7 downto 0);
  signal sd_dout     : std_logic_vector(7 downto 0);
  signal sd_we       : std_logic;
  signal sd_dat0     : std_logic;
  signal sd_dat3     : std_logic;

begin
  keyboard_enable <= ENABLE and not clear_active;

  keyboard : entity work.keyboard
    generic map (
      G_CLK_HZ         => 50_000_000,
      G_BAUD           => 115200
      )
    port map (
      CLOCK        => CLOCK,
      RESET        => RESET_50,
      ENABLE       => keyboard_enable,

      FPGA_UART_RX => FPGA_UART_RX,

      CHAR         => char,
      DIFFERENTIAL => differential
      );

  u_i2c : entity work.hdmi_i2c
    port map (
      CLOCK      => CLOCK,
      RESET      => RESET_50,
      I2C_SCL_I  => HDMI_I2C_SCL_I,
      I2C_SDA_I  => HDMI_I2C_SDA_I,
      I2C_SCL_OE => HDMI_I2C_SCL_OE,
      I2C_SDA_OE => HDMI_I2C_SDA_OE,
      READY      => i2c_ready
      );

  sdcard : entity work.sdcard
    port map (
      clk      => CLOCK,
      rst      => RESET_50,
      start_rd => sd_start_rd,
      start_wr => sd_start_wr,
      lba      => sd_lba,
      busy     => sd_busy,
      done     => sd_done,
      error    => sd_error,
      sd_clk   => SD_CLK,
      sd_cmd   => SD_CMD,
      sd_dat0  => sd_dat0,
      sd_dat3  => sd_dat3,
      
      ram_addr => sd_addr,
      ram_din  => sd_din,
      ram_dout => sd_dout,
      ram_we   => sd_we
      );

  sd_start_rd <= '0';
  sd_start_wr <= '0';
  sd_lba      <= (others => '0');
  sd_dout     <= (others => '0');

  sd_dat0 <= SD_DATA(0);
  SD_DATA(0) <= 'Z';
  SD_DATA(1) <= 'Z';
  SD_DATA(2) <= 'Z';
  SD_DATA(3) <= sd_dat3;

  RAM_VALID <= '0';
  RAM_WRITE <= '0';
  RAM_ADDR  <= (others => '0');
  RAM_WDATA <= (others => '0');

  READY <= i2c_ready and not clear_active;

  HDMI_ISEL <= not RESET_50;
  HDMI_PD_n <= '1';
  HDMI_TX_CLK_p <= not PIXEL_CLK;

  text_wr_en <= '1'
    when RESET_50 = '0' and ENABLE = '1' and
      (clear_active = '1' or differential /= last_differential_50)
    else '0';

  text_wr_addr <= to_unsigned(clear_addr, text_wr_addr'length)
    when clear_active = '1'
    else to_unsigned(cursor_addr, text_wr_addr'length);

  text_wr_data <= (others => '0') when clear_active = '1' else char;

  process (CLOCK, RESET_50)
  begin
    if RESET_50 = '1' then
      clear_active         <= '1';
      clear_addr           <= 0;
      cursor_addr          <= 0;
      last_differential_50 <= '0';
      DONE                 <= '0';
    elsif rising_edge(CLOCK) then
      if ENABLE = '0' then
        clear_active         <= '1';
        clear_addr           <= 0;
        cursor_addr          <= 0;
        last_differential_50 <= differential;
        DONE                 <= '0';
      elsif clear_active = '1' then
        last_differential_50 <= differential;
        DONE                 <= '0';

        if clear_addr = TEXT_DEPTH - 1 then
          clear_active <= '0';
          clear_addr   <= 0;
        else
          clear_addr <= clear_addr + 1;
        end if;
      elsif differential /= last_differential_50 then
        last_differential_50 <= differential;

        if char = x"71" then
          DONE <= '1';
        end if;

        if cursor_addr = TEXT_DEPTH - 1 then
          cursor_addr <= 0;
        else
          cursor_addr <= cursor_addr + 1;
        end if;
      end if;
    end if;
  end process;

  u_text_ram : entity work.terminal_text_ram
    generic map (
      G_DEPTH      => TEXT_DEPTH,
      G_ADDR_WIDTH => TEXT_ADDR_WIDTH
      )
    port map (
      WR_CLK  => CLOCK,
      WR_EN   => text_wr_en,
      WR_ADDR => text_wr_addr,
      WR_DATA => text_wr_data,
      RD_CLK  => PIXEL_CLK,
      RD_ADDR => text_rd_addr,
      RD_DATA => text_rd_char
      );

  process (h_count, v_count)
    variable x_coord : natural range 0 to H_VISIBLE - 1;
    variable y_coord : natural range 0 to TEXT_PIXEL_HEIGHT - 1;
    variable address : natural range 0 to TEXT_DEPTH - 1;
  begin
    text_visible_s0 <= '0';
    text_rd_addr    <= (others => '0');
    glyph_x_s0      <= 0;
    glyph_y_s0      <= 0;

    if h_count >= H_START and h_count < H_END and
       v_count >= V_START and v_count < V_START + TEXT_PIXEL_HEIGHT then
      x_coord := h_count - H_START;
      y_coord := v_count - V_START;
      address := (y_coord / FONT_HEIGHT) * LINE_WIDTH +
                 (x_coord / FONT_WIDTH);

      text_visible_s0 <= '1';
      text_rd_addr    <= to_unsigned(address, text_rd_addr'length);
      glyph_x_s0      <= x_coord mod FONT_WIDTH;
      glyph_y_s0      <= y_coord mod FONT_HEIGHT;
    end if;
  end process;

  video_hs_s0 <= '1' when h_count >= H_SYNC and h_count < H_TOTAL else '0';
  video_vs_s0 <= '1' when v_count >= V_SYNC and v_count < V_TOTAL else '0';
  video_de_s0 <= '1'
    when h_count >= H_START and h_count < H_END and
         v_count >= V_START and v_count < V_END
    else '0';

  process (PIXEL_CLK, RESET_PIXEL)
  begin
    if RESET_PIXEL = '1' then
      enable_meta  <= '0';
      enable_pixel <= '0';
      clear_meta   <= '1';
      clear_pixel  <= '1';
    elsif rising_edge(PIXEL_CLK) then
      enable_meta  <= ENABLE;
      enable_pixel <= enable_meta;
      clear_meta   <= clear_active;
      clear_pixel  <= clear_meta;
    end if;
  end process;

  process (PIXEL_CLK, RESET_PIXEL)
  begin
    if RESET_PIXEL = '1' then
      h_count         <= 0;
      v_count         <= 0;
      video_hs_d1     <= '1';
      video_hs_d2     <= '1';
      video_vs_d1     <= '1';
      video_vs_d2     <= '1';
      video_de_d1     <= '0';
      video_de_d2     <= '0';
      text_visible_d1 <= '0';
      text_visible_d2 <= '0';
      glyph_x_d1      <= 0;
      glyph_y_d1      <= 0;
    elsif rising_edge(PIXEL_CLK) then
      if enable_pixel = '0' then
        h_count         <= 0;
        v_count         <= 0;
        video_hs_d1     <= '1';
        video_hs_d2     <= '1';
        video_vs_d1     <= '1';
        video_vs_d2     <= '1';
        video_de_d1     <= '0';
        video_de_d2     <= '0';
        text_visible_d1 <= '0';
        text_visible_d2 <= '0';
        glyph_x_d1      <= 0;
        glyph_y_d1      <= 0;
      else
        if h_count = H_TOTAL then
          h_count <= 0;
          if v_count = V_TOTAL then
            v_count <= 0;
          else
            v_count <= v_count + 1;
          end if;
        else
          h_count <= h_count + 1;
        end if;

        video_hs_d1 <= video_hs_s0;
        video_hs_d2 <= video_hs_d1;
        video_vs_d1 <= video_vs_s0;
        video_vs_d2 <= video_vs_d1;
        video_de_d1 <= video_de_s0;
        video_de_d2 <= video_de_d1;

        text_visible_d1 <= text_visible_s0 and not clear_pixel;
        text_visible_d2 <= text_visible_d1;
        glyph_x_d1      <= glyph_x_s0;
        glyph_y_d1      <= glyph_y_s0;
      end if;
    end if;
  end process;

  font_char_code <= text_rd_char(6 downto 0)
    when text_rd_char(7) = '0'
    else "0111111";

  font_rd_addr <= unsigned(
    font_char_code &
    std_logic_vector(to_unsigned(glyph_y_d1, 4)) &
    std_logic_vector(to_unsigned(glyph_x_d1, 3))
    );

  u_font_rom : entity work.terminal_font_rom
    port map (
      CLOCK => PIXEL_CLK,
      ADDR  => font_rd_addr,
      DATA  => font_pixel
      );

  HDMI_TX_HS <= video_hs_d2;
  HDMI_TX_VS <= video_vs_d2;
  HDMI_TX_DE <= video_de_d2;
  HDMI_TX_D  <= (others => font_pixel) when text_visible_d2 = '1'
                else (others => '0');

end architecture rtl;
