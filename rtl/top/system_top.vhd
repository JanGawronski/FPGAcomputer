library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

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
        HDMI_I2C_SCL : inout std_logic;
        HDMI_I2C_SDA : inout std_logic;
        HDMI_TX_HS   : out   std_logic;
        HDMI_TX_VS   : out   std_logic;
        HDMI_TX_D    : out   std_logic_vector(23 downto 0);
        HDMI_TX_DE   : out   std_logic;
        HDMI_TX_CLK_p : out  std_logic;
        HDMI_ISEL    : out   std_logic;
        HDMI_PD_n    : out   std_logic;
        DDC_I2C_SCL  : inout std_logic;
        DDC_I2C_SDA  : inout std_logic;

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
begin
-- Structural coding goes here
end architecture rtl;
