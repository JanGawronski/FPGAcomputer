library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity terminal is
  port(
    CLOCK        : in  std_logic;
    PIXEL_CLK    : in  std_logic;
    RESET        : in  std_logic;
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

  constant FONT_HEIGHT : integer := 16;
  constant FONT_WIDTH  : integer := 8;
  
  type chartable_t is array(0 to 16383) of std_logic_vector(0 downto 0);
  signal chartable : chartable_t;

  attribute ram_init_file : string;
  attribute ram_init_file of chartable : signal is "../rtl/terminal/chartable.mif";

  signal i2c_ready : std_logic := '0';

  constant H_TOTAL   : integer := 2199;
  constant H_SYNC    : integer := 43;
  constant H_START   : integer := 189;
  constant H_END     : integer := 2109;
  constant H_VISIBLE : integer := 1920;
  
  constant V_TOTAL    : integer := 1124;
  constant V_SYNC     : integer := 4;
  constant V_START    : integer := 40;
  constant V_END      : integer := 1120;
  constant V_VISIBLE  : integer := 1080;

  signal h_count : integer range 0 to H_TOTAL := 0;
  signal v_count : integer range 0 to V_TOTAL := 0;
  signal pixel_x : unsigned(7 downto 0) := (others => '0');

  signal h_act    : std_logic := '0';
  signal h_act_d  : std_logic := '0';
  signal v_act    : std_logic := '0';

  signal pre_vga_de : std_logic := '0';
  signal vga_de      : std_logic := '0';
  signal boarder     : std_logic := '0';
  signal color_mode  : std_logic_vector(3 downto 0) := (others => '0');

  signal vga_hs : std_logic := '1';
  signal vga_vs : std_logic := '1';
  signal vga_r  : std_logic_vector(7 downto 0) := (others => '0');
  signal vga_g  : std_logic_vector(7 downto 0) := (others => '0');
  signal vga_b  : std_logic_vector(7 downto 0) := (others => '0');

  constant LINE_WIDTH : integer := H_VISIBLE / FONT_WIDTH;
  constant LINE_COUNT : integer := V_VISIBLE / FONT_HEIGHT / 8;
  
  type t_line  is array (0 to LINE_WIDTH - 1) of std_logic_vector(FONT_WIDTH - 1 downto 0);
  type t_lines is array (0 to LINE_COUNT - 1) of t_line;
  
  signal char_lines : t_lines := (others => (others => (others => '0')));

  signal cursor_position : integer range 0 to LINE_WIDTH - 1 := 0;
  signal cursor_line     : integer range 0 to LINE_COUNT - 1 := 0;

  signal char : std_logic_vector(FONT_WIDTH - 1 downto 0) := (others => '0');
  signal differential : std_logic := '0';
  signal last_differential : std_logic := '0';

  signal pixel : std_logic := '0';

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
  keyboard : entity work.keyboard
    generic map (
      G_CLK_HZ         => 50_000_000,
      G_BAUD           => 115200
      )
    port map (
      CLOCK        => CLOCK,
      RESET        => RESET,
      ENABLE       => ENABLE,

      FPGA_UART_RX => FPGA_UART_RX,

      CHAR         => char,
      DIFFERENTIAL => differential
      );

  
  u_i2c : entity work.hdmi_i2c
    port map (
      CLOCK      => CLOCK,
      RESET      => RESET,
      I2C_SCL_I  => HDMI_I2C_SCL_I,
      I2C_SDA_I  => HDMI_I2C_SDA_I,
      I2C_SCL_OE => HDMI_I2C_SCL_OE,
      I2C_SDA_OE => HDMI_I2C_SDA_OE,
      READY      => i2c_ready
      );


  sdcard : entity work.sdcard
    port map (
      clk      => CLOCK,
      rst      => RESET,
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

  sd_dat0 <= SD_DATA(0);

  SD_DATA(3) <= sd_dat3;
  
  READY <= i2c_ready;

  HDMI_ISEL <= not RESET;
  HDMI_PD_n <= '1';
  
  HDMI_TX_CLK_p <= not PIXEL_CLK;

  process(PIXEL_CLK, RESET)    
  begin
    if RESET = '1' then
      h_count     <= 0;
      v_count     <= 0;
      pixel_x     <= (others => '0');
      h_act       <= '0';
      h_act_d     <= '0';
      v_act       <= '0';
      pre_vga_de  <= '0';
      vga_de      <= '0';
      boarder     <= '0';
      vga_hs      <= '1';
      vga_vs      <= '1';
      vga_r       <= (others => '0');
      vga_g       <= (others => '0');
      vga_b       <= (others => '0');
      last_differential <= '0';
      char_lines  <= (others => (others => (others => '0')));
      cursor_position <= 0;
      cursor_line <= 0;
      pixel       <= '0';
      DONE        <= '0';
    elsif rising_edge(PIXEL_CLK) then
      if ENABLE /= '1' then
        h_count     <= 0;
        v_count     <= 0;
        pixel_x     <= (others => '0');
        h_act       <= '0';
        h_act_d     <= '0';
        v_act       <= '0';
        pre_vga_de  <= '0';
        vga_de      <= '0';
        boarder     <= '0';
        vga_hs      <= '1';
        vga_vs      <= '1';
        vga_r       <= (others => '0');
        vga_g       <= (others => '0');
        vga_b       <= (others => '0');
        last_differential <= '0';
        char_lines  <= (others => (others => (others => '0')));
        cursor_position <= 0;
        cursor_line <= 0;
        pixel       <= '0';
        DONE        <= '0';
      else

        if differential /= last_differential then
          last_differential <= not last_differential;
          char_lines(cursor_line)(cursor_position) <= char;
          cursor_position <= cursor_position + 1;
          if cursor_position = LINE_WIDTH - 1 then
            cursor_line <= cursor_line + 1;
          end if;
        end if;

        if cursor_position > 0 and char_lines(cursor_line)(cursor_position - 1) = "01110001" then
          DONE <= '1';
        end if;

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
        end if;

        if v_act = '1' and h_act = '1' then
          pre_vga_de <= '1';
        else
          pre_vga_de <= '0';
        end if;

        vga_de <= pre_vga_de;

        if h_count - H_START >= 0 and h_count - H_START < FONT_WIDTH * LINE_WIDTH and v_count - V_START >= 0 and v_count - V_START < FONT_HEIGHT * LINE_COUNT  then
          pixel <= chartable(to_integer(unsigned(char_lines(
            (v_count - V_START) / FONT_HEIGHT)(
            (h_count - H_START) / FONT_WIDTH))) * FONT_HEIGHT * FONT_WIDTH + ((v_count - V_START) mod FONT_HEIGHT) * FONT_WIDTH + ((h_count - H_START) mod FONT_WIDTH))(0);
          vga_r <= (others => pixel);
          vga_g <= (others => pixel);
          vga_b <= (others => pixel);
        else
          vga_r <= (others => '0');
          vga_g <= (others => '0');
          vga_b <= (others => '0');
        end if;
      end if;
    end if;
  end process;

  HDMI_TX_HS <= vga_hs;
  HDMI_TX_VS <= vga_vs;
  HDMI_TX_DE <= vga_de;
  HDMI_TX_D  <= vga_r & vga_g & vga_b;

end architecture rtl;

