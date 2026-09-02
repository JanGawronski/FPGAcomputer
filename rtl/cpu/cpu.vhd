library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu is
  generic (
    G_RAM_ADDR_WIDTH  : positive;
    G_READ_BASE_ADDR  : natural;
    G_READ_WORD_COUNT : positive;
    G_CPU_REGISTERS   : positive
    );
  port (
    CLOCK      : in  std_logic;
    RESET      : in  std_logic;
    ENABLE     : in  std_logic;

    RAM_READY  : in  std_logic;
    RAM_RVALID : in  std_logic;
    RAM_RDATA  : in  std_logic_vector(31 downto 0);
    RAM_VALID  : out std_logic;
    RAM_WRITE  : out std_logic;
    RAM_ADDR   : out std_logic_vector(G_RAM_ADDR_WIDTH - 1 downto 0);
    RAM_WDATA  : out std_logic_vector(31 downto 0);

    DONE       : out std_logic
    );
end entity cpu;

architecture rtl of cpu is
  constant C_OPCODE_LOAD       : std_logic_vector(7 downto 0) := x"01";
  constant C_OPCODE_STORE      : std_logic_vector(7 downto 0) := x"02";
  constant C_OPCODE_LOAD_ADDR  : std_logic_vector(7 downto 0) := x"03";
  constant C_OPCODE_STORE_ADDR : std_logic_vector(7 downto 0) := x"04";
  constant C_OPCODE_ADD        : std_logic_vector(7 downto 0) := x"05";
  constant C_OPCODE_HALT       : std_logic_vector(7 downto 0) := x"FF";
  
  subtype t_addr is std_logic_vector(G_RAM_ADDR_WIDTH - 1 downto 0);
  subtype t_register is std_logic_vector(31 downto 0);
  type t_registers is array (0 to G_CPU_REGISTERS - 1) of t_register;

  type t_state is (
    idle,
    issue_fetch1,
    wait_fetch1,
    issue_fetch2,
    wait_fetch2,
    execute,
    issue_read,
    wait_read,
    issue_write,
    advance_pc,
    done_hold
    );

  function f_code_addr(word_offset : natural) return t_addr is
  begin
    return std_logic_vector(to_unsigned(G_READ_BASE_ADDR + word_offset, t_addr'length));
  end function;

  function f_data_addr(instr2 : std_logic_vector(31 downto 0)) return t_addr is
    variable word_offset : natural;
  begin
    word_offset := to_integer(unsigned(instr2(G_RAM_ADDR_WIDTH - 1 downto 0)));
    return std_logic_vector(to_unsigned(G_READ_BASE_ADDR + word_offset, t_addr'length));
  end function;

  signal general_purpose_registers : t_registers := (others => (others => '0'));
  signal instruction1              : std_logic_vector(31 downto 0) := (others => '0');
  signal instruction2              : std_logic_vector(31 downto 0) := (others => '0');

  signal state            : t_state := idle;
  signal word_index       : natural range 0 to G_READ_WORD_COUNT - 1 := 0;
  signal target_reg_idx   : natural range 0 to G_CPU_REGISTERS - 1 := 0;
  signal target_reg_valid : std_logic := '0';
  signal done_reg         : std_logic := '0';

  signal ram_valid_reg : std_logic := '0';
  signal ram_write_reg : std_logic := '0';
  signal ram_addr_reg  : t_addr := (others => '0');
  signal ram_wdata_reg : std_logic_vector(31 downto 0) := (others => '0');
begin
  assert G_RAM_ADDR_WIDTH <= 32
    report "G_RAM_ADDR_WIDTH must be <= 32 for cpu instruction addresses"
    severity failure;

  RAM_VALID <= ram_valid_reg;
  RAM_WRITE <= ram_write_reg;
  RAM_ADDR  <= ram_addr_reg;
  RAM_WDATA <= ram_wdata_reg;
  DONE      <= done_reg;

  process (CLOCK, RESET)
    variable reg_idx_raw    : natural range 0 to 255;
    variable src_idx_raw    : natural range 0 to 255;
    variable effective_addr : t_addr;
  begin
    if RESET = '1' then
      general_purpose_registers <= (others => (others => '0'));
      instruction1          <= (others => '0');
      instruction2          <= (others => '0');
      state                 <= idle;
      word_index            <= 0;
      target_reg_idx        <= 0;
      target_reg_valid      <= '0';
      done_reg              <= '0';
      ram_valid_reg         <= '0';
      ram_write_reg         <= '0';
      ram_addr_reg          <= (others => '0');
      ram_wdata_reg         <= (others => '0');
    elsif rising_edge(CLOCK) then
      ram_valid_reg <= '0';
      ram_write_reg <= '0';

      if ENABLE = '0' then
        state                 <= idle;
        word_index            <= 0;
        target_reg_idx        <= 0;
        target_reg_valid      <= '0';
        done_reg              <= '0';
        ram_write_reg         <= '0';
        ram_addr_reg          <= (others => '0');
        ram_wdata_reg         <= (others => '0');
      else
        case state is
          when idle =>
            done_reg <= '0';
            if (G_READ_WORD_COUNT < 2) or (word_index + 1 >= G_READ_WORD_COUNT) then
              done_reg <= '1';
              state    <= done_hold;
            else
              state <= issue_fetch1;
            end if;

          when issue_fetch1 =>
            if RAM_READY = '1' then
              ram_addr_reg  <= f_code_addr(word_index);
              ram_valid_reg <= '1';
              state         <= wait_fetch1;
            end if;

          when wait_fetch1 =>
            if RAM_RVALID = '1' then
              instruction1 <= RAM_RDATA;
              state        <= issue_fetch2;
            end if;

          when issue_fetch2 =>
            if RAM_READY = '1' then
              ram_addr_reg  <= f_code_addr(word_index + 1);
              ram_valid_reg <= '1';
              state         <= wait_fetch2;
            end if;

          when wait_fetch2 =>
            if RAM_RVALID = '1' then
              instruction2 <= RAM_RDATA;
              state        <= execute;
            end if;

          when execute =>
            reg_idx_raw       := to_integer(unsigned(instruction1(7 downto 0)));
            src_idx_raw       := to_integer(unsigned(instruction2(7 downto 0)));
            effective_addr    := f_data_addr(instruction2);
            target_reg_valid  <= '0';
            target_reg_idx    <= 0;

            case instruction1(15 downto 8) is
              when C_OPCODE_LOAD =>
                if (reg_idx_raw < G_CPU_REGISTERS) and (src_idx_raw < G_CPU_REGISTERS) then
                  target_reg_idx   <= reg_idx_raw;
                  target_reg_valid <= '1';
                  ram_addr_reg     <= general_purpose_registers(src_idx_raw)(t_addr'range);
                  state            <= issue_read;
                else
                  state <= advance_pc;
                end if;

              when C_OPCODE_STORE =>
                if (reg_idx_raw < G_CPU_REGISTERS) and (src_idx_raw < G_CPU_REGISTERS) then
                  ram_addr_reg  <= general_purpose_registers(src_idx_raw)(t_addr'range);
                  ram_wdata_reg <= general_purpose_registers(reg_idx_raw);
                  state         <= issue_write;
                else
                  state <= advance_pc;
                end if;

              when C_OPCODE_LOAD_ADDR =>
                if reg_idx_raw < G_CPU_REGISTERS then
                  target_reg_idx   <= reg_idx_raw;
                  target_reg_valid <= '1';
                  ram_addr_reg     <= effective_addr;
                  state            <= issue_read;
                else
                  state <= advance_pc;
                end if;

              when C_OPCODE_STORE_ADDR =>
                if reg_idx_raw < G_CPU_REGISTERS then
                  ram_addr_reg  <= effective_addr;
                  ram_wdata_reg <= general_purpose_registers(reg_idx_raw);
                  state         <= issue_write;
                else
                  state <= advance_pc;
                end if;

              when C_OPCODE_ADD =>
                if (reg_idx_raw < G_CPU_REGISTERS) and (src_idx_raw < G_CPU_REGISTERS) then
                  general_purpose_registers(reg_idx_raw) <= std_logic_vector(
                    unsigned(general_purpose_registers(reg_idx_raw)) +
                    unsigned(general_purpose_registers(src_idx_raw))
                    );
                end if;
                state <= advance_pc;               

              when C_OPCODE_HALT =>
                done_reg <= '1';
                state    <= done_hold;

              when others =>
                state <= advance_pc;
            end case;

          when issue_read =>
            if RAM_READY = '1' then
              ram_valid_reg <= '1';
              state         <= wait_read;
            end if;

          when wait_read =>
            if RAM_RVALID = '1' then
              if target_reg_valid = '1' then
                general_purpose_registers(target_reg_idx) <= RAM_RDATA;
              end if;
              state <= advance_pc;
            end if;

          when issue_write =>
            if RAM_READY = '1' then
              ram_valid_reg <= '1';
              ram_write_reg <= '1';
              state         <= advance_pc;
            end if;

          when advance_pc =>
            if word_index + 2 >= G_READ_WORD_COUNT then
              done_reg <= '1';
              state    <= done_hold;
            else
              word_index <= word_index + 2;
              state      <= idle;
            end if;

          when done_hold =>
            done_reg <= '1';
        end case;
      end if;
    end if;
  end process;
end architecture rtl;
