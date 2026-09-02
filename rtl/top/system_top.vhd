library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library pll;

entity system_top is
  port (
    -- CLOCK
    CLOCK0_50  : in    std_logic;
    CLOCK1_50  : in    std_logic;
    CLOCK2_50  : in    std_logic;
    CLOCK3_50  : in    std_logic;

    -- KEY (low-active)
    KEY        : in    std_logic_vector(1 downto 0);

    -- FPGA UART
    FPGA_UART_TX : out  std_logic;
    FPGA_UART_RX : in   std_logic;

    -- SW
    SW         : in     std_logic_vector(1 downto 0);

    -- LED (low-active)
    LED        : out    std_logic_vector(3 downto 0);

    -- SDRAM
    DRAM_CLK   : out    std_logic;
    DRAM_CKE   : out    std_logic;
    DRAM_ADDR  : out    std_logic_vector(12 downto 0);
    DRAM_BA    : out    std_logic_vector(1 downto 0);
    DRAM_DQ    : inout  std_logic_vector(31 downto 0);
    DRAM_CS_n  : out    std_logic;
    DRAM_WE_n  : out    std_logic;
    DRAM_CAS_n : out    std_logic;
    DRAM_RAS_n : out    std_logic;
    DRAM_DQM   : out    std_logic_vector(3 downto 0);

    -- SD
    SD_CLK     : out    std_logic;
    SD_DATA    : inout  std_logic_vector(3 downto 0);
    SD_CMD     : inout  std_logic;

    -- HDMI
    HDMI_I2C_SCL  : inout std_logic;
    HDMI_I2C_SDA  : inout std_logic;
    HDMI_TX_HS    : out   std_logic;
    HDMI_TX_VS    : out   std_logic;
    HDMI_TX_D     : out   std_logic_vector(23 downto 0);
    HDMI_TX_DE    : out   std_logic;
    HDMI_TX_CLK_p : out   std_logic;
    HDMI_ISEL     : out   std_logic;
    HDMI_PD_n     : out   std_logic;
    DDC_I2C_SCL   : inout std_logic;
    DDC_I2C_SDA   : inout std_logic;

    -- NET
    NET_TX_CLK   : out   std_logic;
    NET_TX_DATA  : out   std_logic_vector(3 downto 0);
    NET_TX_CTRL  : out   std_logic;
    NET_RX_CLK   : in    std_logic;
    NET_RX_DATA  : in    std_logic_vector(3 downto 0);
    NET_RX_CTRL  : in    std_logic;
    NET_MDC      : out   std_logic;
    NET_MDIO     : inout std_logic;
    NET_RESET_n  : out   std_logic;

    -- GPIO
    GPIO_D       : inout std_logic_vector(35 downto 0);

    -- TMD0
    TMD0_D       : inout std_logic_vector(7 downto 0);

    -- TMD1
    TMD1_D       : inout std_logic_vector(7 downto 0)
    );
end entity system_top;

architecture rtl of system_top is
  constant C_RAM_ADDR_WIDTH : positive := 24;
  constant C_RAM_DATA_WIDTH : positive := 32;
  constant C_RAM_WORD_COUNT : positive := 512;

  constant C_CLK_HZ : positive := 50_000_000;
  constant C_BAUD   : positive := 115200;

  constant C_TRANSFER_START : natural := 0;
  constant C_TRANSFER_END   : natural := 255;
  constant C_TRANSFER_WORDS : positive := C_TRANSFER_END - C_TRANSFER_START + 1;

  constant C_TRANSFER_START_VEC : std_logic_vector(C_RAM_ADDR_WIDTH - 1 downto 0) :=
    std_logic_vector(to_unsigned(C_TRANSFER_START, C_RAM_ADDR_WIDTH));
  constant C_TRANSFER_END_VEC : std_logic_vector(C_RAM_ADDR_WIDTH - 1 downto 0) :=
    std_logic_vector(to_unsigned(C_TRANSFER_END, C_RAM_ADDR_WIDTH));

  type t_owner is (
    owner_terminal,
    owner_uart_load,
    owner_cpu,
    owner_uart_send,
    owner_hdmi_example,
    owner_done
    );

  signal owner : t_owner := owner_terminal;

  signal reset : std_logic;

  -- UART -> RAM loader
  signal load_enable    : std_logic;
  signal load_done      : std_logic;
  signal load_ram_ready : std_logic;
  signal load_ram_valid : std_logic;
  signal load_ram_write : std_logic;
  signal load_ram_addr  : std_logic_vector(C_RAM_ADDR_WIDTH - 1 downto 0);
  signal load_ram_wdata : std_logic_vector(C_RAM_DATA_WIDTH - 1 downto 0);
  signal load_ram_be    : std_logic_vector((C_RAM_DATA_WIDTH / 8) - 1 downto 0);
  signal load_fpga_uart_rx : std_logic;
  
  -- CPU
  signal cpu_enable      : std_logic;
  signal cpu_done        : std_logic;
  signal cpu_ram_ready   : std_logic;
  signal cpu_ram_valid   : std_logic;
  signal cpu_ram_write   : std_logic;
  signal cpu_ram_addr    : std_logic_vector(C_RAM_ADDR_WIDTH - 1 downto 0);
  signal cpu_ram_wdata   : std_logic_vector(31 downto 0);
  signal cpu_ram_rvalid  : std_logic;
  signal cpu_ram_rdata   : std_logic_vector(31 downto 0);

  -- RAM -> UART sender
  signal send_enable     : std_logic;
  signal send_done       : std_logic;
  signal send_ram_ready  : std_logic;
  signal send_ram_valid  : std_logic;
  signal send_ram_write  : std_logic;
  signal send_ram_addr   : std_logic_vector(C_RAM_ADDR_WIDTH - 1 downto 0);
  signal send_ram_wdata  : std_logic_vector(C_RAM_DATA_WIDTH - 1 downto 0);
  signal send_ram_be     : std_logic_vector((C_RAM_DATA_WIDTH / 8) - 1 downto 0);
  signal send_ram_rvalid : std_logic;
  signal send_ram_rdata  : std_logic_vector(C_RAM_DATA_WIDTH - 1 downto 0);
  signal uart_tx_out     : std_logic;

  -- Shared RAM fabric
  signal ram_valid_mux : std_logic;
  signal ram_write_mux : std_logic;
  signal ram_addr_mux  : std_logic_vector(C_RAM_ADDR_WIDTH - 1 downto 0);
  signal ram_wdata_mux : std_logic_vector(C_RAM_DATA_WIDTH - 1 downto 0);
  signal ram_be_mux    : std_logic_vector((C_RAM_DATA_WIDTH / 8) - 1 downto 0);
  signal ram_ready     : std_logic;
  signal ram_rvalid    : std_logic;
  signal ram_rdata     : std_logic_vector(C_RAM_DATA_WIDTH - 1 downto 0);

  signal led_status : std_logic_vector(3 downto 0);
  signal pll_locked : std_logic := '0';
  signal pll_outclk : std_logic := '0';

  
  signal terminal_ready : std_logic := '0';

  signal terminal_hdmi_i2c_scl  : std_logic := 'Z';
  signal terminal_hdmi_i2c_sda  : std_logic := 'Z';
  signal terminal_hdmi_tx_hs    : std_logic := '0';
  signal terminal_hdmi_tx_vs    : std_logic := '0';
  signal terminal_hdmi_tx_d     : std_logic_vector(23 downto 0) := (others => '0');
  signal terminal_hdmi_tx_de    : std_logic := '0';
  signal terminal_hdmi_tx_clk_p : std_logic := '0';
  signal terminal_hdmi_isel     : std_logic := '0';
  signal terminal_hdmi_pd_n     : std_logic := '0';

  signal terminal_enable      : std_logic;
  signal terminal_done        : std_logic;
  signal terminal_ram_ready   : std_logic;
  signal terminal_ram_valid   : std_logic;
  signal terminal_ram_write   : std_logic;
  signal terminal_ram_addr    : std_logic_vector(C_RAM_ADDR_WIDTH - 1 downto 0);
  signal terminal_ram_wdata   : std_logic_vector(31 downto 0);
  signal terminal_ram_rvalid  : std_logic;
  signal terminal_ram_rdata   : std_logic_vector(31 downto 0);
  signal terminal_fpga_uart_rx : std_logic;
  
  
  signal hdmi_ready         : std_logic := '0';

  signal test_hdmi_i2c_scl  : std_logic := 'Z';
  signal test_hdmi_i2c_sda  : std_logic := 'Z';
  signal test_hdmi_tx_hs    : std_logic := '0';
  signal test_hdmi_tx_vs    : std_logic := '0';
  signal test_hdmi_tx_d     : std_logic_vector(23 downto 0) := (others => '0');
  signal test_hdmi_tx_de    : std_logic := '0';
  signal test_hdmi_tx_clk_p : std_logic := '0';
  signal test_hdmi_isel     : std_logic := '0';
  signal test_hdmi_pd_n     : std_logic := '0';
  
  signal terminal_hdmi_i2c_scl_oe : std_logic := '0';
  signal terminal_hdmi_i2c_sda_oe : std_logic := '0';

  signal test_hdmi_i2c_scl_oe : std_logic := '0';
  signal test_hdmi_i2c_sda_oe : std_logic := '0';

  signal sel_hdmi_i2c_scl_oe : std_logic := '0';
  signal sel_hdmi_i2c_sda_oe : std_logic := '0';  
  
begin
  reset <= not KEY(0);

  load_enable <= '1' when owner = owner_uart_load else '0';
  cpu_enable  <= '1' when owner = owner_cpu else '0';
  send_enable <= '1' when owner = owner_uart_send else '0';
  terminal_enable <= '1' when owner = owner_terminal else '0';

  ram_valid_mux <= load_ram_valid when owner = owner_uart_load else
                   cpu_ram_valid when owner = owner_cpu else
                   send_ram_valid when owner = owner_uart_send else
                   terminal_ram_valid when owner = owner_terminal else
                   '0';

  ram_write_mux <= load_ram_write when owner = owner_uart_load else
                   cpu_ram_write when owner = owner_cpu else
                   send_ram_write when owner = owner_uart_send else
                   terminal_ram_write when owner = owner_terminal else
                   '0';

  ram_addr_mux <= load_ram_addr when owner = owner_uart_load else
                  cpu_ram_addr when owner = owner_cpu else
                  send_ram_addr when owner = owner_uart_send else
                  terminal_ram_addr when owner = owner_terminal else
                  (others => '0');

  ram_wdata_mux <= load_ram_wdata when owner = owner_uart_load else
                   std_logic_vector(resize(unsigned(cpu_ram_wdata), C_RAM_DATA_WIDTH)) when owner = owner_cpu else
                   send_ram_wdata when owner = owner_uart_send else
                   terminal_ram_wdata when owner = owner_terminal else
                   (others => '0');

  ram_be_mux <= load_ram_be when owner = owner_uart_load else
                (others => '1') when owner = owner_cpu else
                send_ram_be when owner = owner_uart_send else
                (others => '1') when owner = owner_terminal else
                (others => '0');

  load_ram_ready <= ram_ready when owner = owner_uart_load else '0';
  cpu_ram_ready  <= ram_ready when owner = owner_cpu else '0';
  send_ram_ready <= ram_ready when owner = owner_uart_send else '0';
  terminal_ram_ready <= ram_ready when owner = owner_terminal else '0';
  
  cpu_ram_rvalid  <= ram_rvalid when owner = owner_cpu else '0';
  cpu_ram_rdata   <= ram_rdata(31 downto 0) when owner = owner_cpu else (others => '0');
  
  send_ram_rvalid <= ram_rvalid when owner = owner_uart_send else '0';
  send_ram_rdata  <= ram_rdata when owner = owner_uart_send else (others => '0');

  terminal_ram_rvalid <= ram_rvalid when owner = owner_terminal else '0';
  terminal_ram_rdata <= ram_rdata when owner = owner_terminal else (others => '0');
  
  terminal_fpga_uart_rx <= FPGA_UART_RX when owner = owner_terminal else '0';
  load_fpga_uart_rx     <= FPGA_UART_RX when owner = owner_uart_load else '0';

  
  HDMI_TX_HS <= '0' when pll_locked /= '1' else
                terminal_hdmi_tx_hs when owner = owner_terminal else
                test_hdmi_tx_hs;

  HDMI_TX_VS <= '0' when pll_locked /= '1' else
                terminal_hdmi_tx_vs when owner = owner_terminal else
                test_hdmi_tx_vs;

  HDMI_TX_DE <= '0' when pll_locked /= '1' else
                terminal_hdmi_tx_de when owner = owner_terminal else
                test_hdmi_tx_de;

  HDMI_TX_D <= (others => '0') when pll_locked /= '1' else
                terminal_hdmi_tx_d when owner = owner_terminal else
                test_hdmi_tx_d;

  HDMI_TX_CLK_p <= '0' when pll_locked /= '1' else
                terminal_hdmi_tx_clk_p when owner = owner_terminal else
                test_hdmi_tx_clk_p;
  
  HDMI_ISEL <= terminal_hdmi_isel when owner = owner_terminal else test_hdmi_isel;
  HDMI_PD_n <= terminal_hdmi_pd_n when owner = owner_terminal else test_hdmi_pd_n;

  sel_hdmi_i2c_scl_oe <= terminal_hdmi_i2c_scl_oe when owner = owner_terminal else test_hdmi_i2c_scl_oe;
  sel_hdmi_i2c_sda_oe <= terminal_hdmi_i2c_sda_oe when owner = owner_terminal else test_hdmi_i2c_sda_oe;

  HDMI_I2C_SCL <= '0' when sel_hdmi_i2c_scl_oe = '1' else 'Z';
  HDMI_I2C_SDA <= '0' when sel_hdmi_i2c_sda_oe = '1' else 'Z';

  process (CLOCK0_50, reset)
  begin
    if reset = '1' then
      owner <= owner_terminal;
    elsif rising_edge(CLOCK0_50) then
      case owner is
        when owner_terminal =>
          if terminal_done = '1' then
            owner <= owner_uart_load;
          end if;
            
        when owner_hdmi_example =>
          owner <= owner_hdmi_example;

        when owner_uart_load =>
          if load_done = '1' then
            owner <= owner_cpu;
          end if;
          
        when owner_cpu =>
          if cpu_done = '1' then
            owner <= owner_uart_send;
          end if;
          
        when owner_uart_send =>
          if send_done = '1' then
            owner <= owner_terminal;
          end if;
          
        when owner_done =>
          owner <= owner_done;
      end case;
    end if;
  end process;

  u_on_chip_ram : entity work.on_chip_ram
    generic map (
      G_ADDR_WIDTH => C_RAM_ADDR_WIDTH,
      G_DATA_WIDTH => C_RAM_DATA_WIDTH,
      G_WORD_COUNT => C_RAM_WORD_COUNT
      )
    port map (
      CLOCK       => CLOCK0_50,
      RESET       => reset,
      RAM_VALID   => ram_valid_mux,
      RAM_WRITE   => ram_write_mux,
      RAM_ADDR    => ram_addr_mux,
      RAM_WDATA   => ram_wdata_mux,
      RAM_BYTE_EN => ram_be_mux,
      RAM_READY   => ram_ready,
      RAM_RVALID  => ram_rvalid,
      RAM_RDATA   => ram_rdata
      );

  u_uart_loader : entity work.load_from_uart_to_ram
    generic map (
      G_RAM_ADDR_WIDTH => C_RAM_ADDR_WIDTH,
      G_RAM_DATA_WIDTH => C_RAM_DATA_WIDTH,
      G_CLK_HZ         => C_CLK_HZ,
      G_BAUD           => C_BAUD
      )
    port map (
      CLOCK        => CLOCK0_50,
      RESET        => reset,
      ENABLE       => load_enable,
      FPGA_UART_RX => load_fpga_uart_rx,
      RAM_START    => C_TRANSFER_START_VEC,
      RAM_END      => C_TRANSFER_END_VEC,
      RAM_READY    => load_ram_ready,
      RAM_VALID    => load_ram_valid,
      RAM_WRITE    => load_ram_write,
      RAM_ADDR     => load_ram_addr,
      RAM_WDATA    => load_ram_wdata,
      RAM_BYTE_EN  => load_ram_be,
      DONE         => load_done
      );

  u_cpu : entity work.cpu
    generic map (
      G_RAM_ADDR_WIDTH  => C_RAM_ADDR_WIDTH,
      G_READ_BASE_ADDR  => C_TRANSFER_START,
      G_READ_WORD_COUNT => C_TRANSFER_WORDS,
      G_CPU_REGISTERS   => 32
      )
    port map (
      CLOCK      => CLOCK0_50,
      RESET      => reset,
      ENABLE     => cpu_enable,
      RAM_READY  => cpu_ram_ready,
      RAM_RVALID => cpu_ram_rvalid,
      RAM_RDATA  => cpu_ram_rdata,
      RAM_VALID  => cpu_ram_valid,
      RAM_WRITE  => cpu_ram_write,
      RAM_ADDR   => cpu_ram_addr,
      RAM_WDATA  => cpu_ram_wdata,
      DONE       => cpu_done
      );

  u_uart_sender : entity work.send_from_ram_to_uart
    generic map (
      G_RAM_ADDR_WIDTH => C_RAM_ADDR_WIDTH,
      G_RAM_DATA_WIDTH => C_RAM_DATA_WIDTH,
      G_CLK_HZ         => C_CLK_HZ,
      G_BAUD           => C_BAUD
      )
    port map (
      CLOCK        => CLOCK0_50,
      RESET        => reset,
      ENABLE       => send_enable,
      FPGA_UART_TX => uart_tx_out,
      RAM_START    => C_TRANSFER_START_VEC,
      RAM_END      => C_TRANSFER_END_VEC,
      RAM_READY    => send_ram_ready,
      RAM_RVALID   => send_ram_rvalid,
      RAM_RDATA    => send_ram_rdata,
      RAM_VALID    => send_ram_valid,
      RAM_WRITE    => send_ram_write,
      RAM_ADDR     => send_ram_addr,
      RAM_WDATA    => send_ram_wdata,
      RAM_BYTE_EN  => send_ram_be,
      DONE         => send_done
      );

  FPGA_UART_TX <= uart_tx_out;

  led_status(0) <= '1' when owner = owner_uart_load  else '0';
  led_status(1) <= '1' when owner = owner_cpu else '0';
  led_status(2) <= '1' when owner = owner_terminal else '0';
  led_status(3) <= '1' when owner = owner_hdmi_example else '0';
  LED <= not led_status;


  -- instantiate PLL to generate pixel clock
  u_pll : entity pll.pll
    port map (
      refclk   => CLOCK0_50,
      locked   => pll_locked,
      rst      => reset,
      outclk_0 => pll_outclk
      );


  terminal : entity work.terminal
  port map (
    CLOCK         => CLOCK0_50,
    PIXEL_CLK     => pll_outclk,
    RESET         => reset,
    ENABLE        => terminal_enable,         
    FPGA_UART_RX  => terminal_fpga_uart_rx,
    HDMI_I2C_SCL_I  => HDMI_I2C_SCL,
    HDMI_I2C_SDA_I  => HDMI_I2C_SDA,
    HDMI_I2C_SCL_OE => terminal_hdmi_i2c_scl_oe,
    HDMI_I2C_SDA_OE => terminal_hdmi_i2c_sda_oe,
    HDMI_TX_HS    => terminal_hdmi_tx_hs,
    HDMI_TX_VS    => terminal_hdmi_tx_vs,
    HDMI_TX_D     => terminal_hdmi_tx_d,
    HDMI_TX_DE    => terminal_hdmi_tx_de,
    HDMI_TX_CLK_p => terminal_hdmi_tx_clk_p,
    HDMI_ISEL     => terminal_hdmi_isel,
    HDMI_PD_n     => terminal_hdmi_pd_n,    
    RAM_READY  => terminal_ram_ready,
    RAM_RVALID => terminal_ram_rvalid,
    RAM_RDATA  => terminal_ram_rdata,
    RAM_VALID  => terminal_ram_valid,
    RAM_WRITE  => terminal_ram_write,
    RAM_ADDR   => terminal_ram_addr,
    RAM_WDATA  => terminal_ram_wdata,
    SD_CLK     => SD_CLK,
    SD_DATA    => SD_DATA,
    SD_CMD     => SD_CMD,
    READY      => terminal_ready,
    DONE       => terminal_done
    );
  
  u_hdmi_test : entity work.hdmi_test
  port map (
    CLOCK         => CLOCK0_50,
    PIXEL_CLK     => pll_outclk,
    RESET         => reset,
    HDMI_I2C_SCL_I  => HDMI_I2C_SCL,
    HDMI_I2C_SDA_I  => HDMI_I2C_SDA,
    HDMI_I2C_SCL_OE => test_hdmi_i2c_scl_oe,
    HDMI_I2C_SDA_OE => test_hdmi_i2c_sda_oe,
    HDMI_TX_HS    => test_hdmi_tx_hs,
    HDMI_TX_VS    => test_hdmi_tx_vs,
    HDMI_TX_D     => test_hdmi_tx_d,
    HDMI_TX_DE    => test_hdmi_tx_de,
    HDMI_TX_CLK_p => test_hdmi_tx_clk_p,
    HDMI_ISEL     => test_hdmi_isel,
    HDMI_PD_n     => test_hdmi_pd_n,
    READY         => hdmi_ready
  );
  
  DDC_I2C_SCL <= 'Z';
  DDC_I2C_SDA <= 'Z';

  NET_TX_CLK  <= '0';
  NET_TX_DATA <= (others => '0');
  NET_TX_CTRL <= '0';
  NET_MDC     <= '0';
  NET_MDIO    <= 'Z';
  NET_RESET_n <= '0';

  GPIO_D <= (others => 'Z');
  TMD0_D <= (others => 'Z');
  TMD1_D <= (others => 'Z');

  DRAM_CLK   <= '0';
  DRAM_CKE   <= '0';
  DRAM_ADDR  <= (others => '0');
  DRAM_BA    <= (others => '0');
  DRAM_CS_n  <= '1';
  DRAM_WE_n  <= '1';
  DRAM_CAS_n <= '1';
  DRAM_RAS_n <= '1';
  DRAM_DQM   <= (others => '1');
  DRAM_DQ    <= (others => 'Z');

end architecture rtl;
