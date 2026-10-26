library IEEE, mylib;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.ALL;

use mylib.defTRM.all;
use mylib.defEVB.all;

entity MikuTimeStamp is
  port (
    rst                 : in std_logic;
    clk                 : in std_logic;
    clkSlow             : in std_logic;

    -- LACCP TimeStamp --
    timeStamp           : in std_logic_vector(23 downto 0);

    -- data in --
    triggerIn           : in TrigDownType;

    -- data out --
    moduleBusy          : out std_logic;

    -- Builder bus --
    addrBuilderBus      : in  BBusAddressType;
    dataBuilderBusOut   : out BBusDataType;
    reBuilderBus        : in  std_logic;
    rvBuilderBus        : out std_logic;
    dReadyBuilderBus    : out std_logic;
    bindBuilderBus      : in  std_logic;
    isBoundToBuilder    : out std_logic

    );
end MikuTimeStamp;

architecture RTL of MikuTimeStamp is
  attribute keep  : string;
  attribute mark_debug  : string;

  -- System --
  signal sync_reset       : std_logic;

  -- timestamp --
  signal synced_timestamp     : std_logic_vector(timeStamp'range);
  signal trg_in_mikudomain    : std_logic;
  signal valid_timestamp      : std_logic;
  signal empty_timestamp      : std_logic;
  signal we_mikuts_fifo       : std_logic;

  -- builder bus control --
  signal num_word_event_summary               : BBusDataType;
  signal state_bbus                           : BBusSlaveType;

  -- builder bus rename --
  signal addr_bbus                            : BBusAddressType;
  signal dout_bbus                            : BBusDataType;
  signal re_bbus, rv_bbus                     : std_logic;
  signal bind_bbus, is_bound_to_builder       : std_logic;

  -- data --
  signal din_block_buffer, dout_block_buffer    : std_logic_vector(kWidthDaqWord-1 downto 0);
  signal we_block_buffer                        : std_logic;
  signal re_block_buffer, rv_block_buffer       : std_logic;
  signal afull_block_buffer, full_block_buffer  : std_logic;
  signal empty_block_buffer                     : std_logic;
  signal data_ready                             : std_logic;
  signal busy_mikuts                                : std_logic;
  attribute keep of busy_mikuts : signal is "TRUE";

--  attribute mark_debug of num_word_event_summary : signal is "TRUE";
--  attribute mark_debug of state_bbus : signal is "TRUE";
--  attribute mark_debug of re_bbus : signal is "TRUE";
--  attribute mark_debug of rv_bbus : signal is "TRUE";
--  attribute mark_debug of bind_bbus : signal is "TRUE";
--  attribute mark_debug of is_bound_to_builder : signal is "TRUE";

  COMPONENT mikuts_fifo
    PORT (
      wr_clk : IN STD_LOGIC;
      rd_clk : IN STD_LOGIC;
      din : IN STD_LOGIC_VECTOR(23 DOWNTO 0);
      wr_en : IN STD_LOGIC;
      rd_en : IN STD_LOGIC;
      dout : OUT STD_LOGIC_VECTOR(23 DOWNTO 0);
      full : OUT STD_LOGIC;
      empty : OUT STD_LOGIC;
      valid : OUT STD_LOGIC
    );
  END COMPONENT;

  COMPONENT data_buffer
    PORT (
      clk         : IN STD_LOGIC;
      srst        : IN STD_LOGIC;
      din         : IN STD_LOGIC_VECTOR(kWidthDaqWord-1 DOWNTO 0);
      wr_en       : IN STD_LOGIC;
      rd_en       : IN STD_LOGIC;
      dout        : OUT STD_LOGIC_VECTOR(kWidthDaqWord-1 DOWNTO 0);
      full        : OUT STD_LOGIC;
      almost_full : OUT STD_LOGIC;
      empty       : OUT STD_LOGIC;
      valid       : OUT STD_LOGIC
      );
  END COMPONENT;

begin
  -- =========================================================================
  --                                      body
  -- =========================================================================

  -- signal connection -------------------------------------------------------
  u_trg_sync : entity mylib.synchronizer
    port map(clk=>clkSlow, dIn=>triggerIn.L1Accept, dOut=>trg_in_mikudomain);

  u_make_we : entity mylib.EdgeDetector
    port map(clk=>clkSlow, dIn=>trg_in_mikudomain, dOut=>we_mikuts_fifo);

  u_sync_fifo :  mikuts_fifo
    port map (
      wr_clk  => clkSlow,
      rd_clk  => clk,
      din     => timeStamp,
      wr_en   => we_mikuts_fifo,
      rd_en   => not empty_timestamp,
      dout    => synced_timestamp,
      full    => open,
      empty   => empty_timestamp,
      valid   => valid_timestamp
    );

  we_block_buffer <= valid_timestamp;
  busy_mikuts     <= afull_block_buffer OR full_block_buffer;
  moduleBusy      <= busy_mikuts;

  din_block_buffer <= X"f3" & synced_timestamp;
  num_word_event_summary <= std_logic_vector(to_unsigned(1, kWidthBBusData));

  -- builder bus --
  -- At present, just rename
  addr_bbus       <= addrBuilderBus;
  re_bbus         <= reBuilderBus;
  bind_bbus       <= bindBuilderBus;

  dataBuilderBusOut   <= dout_bbus;
  rvBuilderBus        <= rv_bbus;
  dReadyBuilderBus    <= data_ready;
  isBoundToBuilder    <= is_bound_to_builder;

  -- data process --
  u_block_buffer : data_buffer
    port map (
      clk         => clk,
      srst        => sync_reset,
      din         => din_block_buffer,
      wr_en       => we_block_buffer,
      rd_en       => re_block_buffer,
      dout        => dout_block_buffer,
      full        => full_block_buffer,
      almost_full => afull_block_buffer,
      empty       => empty_block_buffer,
      valid       => rv_block_buffer
      );

  u_data_ready  : process(sync_reset, clk)
  begin
    if(sync_reset = '1') then
      data_ready  <= '0';
    elsif(clk'event AND clk='1') then
      data_ready  <= NOT empty_block_buffer;
    end if;
  end process;

  -- Builder bus process --
  u_BuilderBusProcess : process(sync_reset, clk)
  begin
    if(sync_reset = '1') then
      dout_bbus           <= (others => '0');
      rv_bbus             <= '0';
      is_bound_to_builder <= '0';

      re_block_buffer     <= '0';
      state_bbus          <= Init;
    elsif(clk'event and clk = '1') then
      case state_bbus is
        when Init =>
          dout_bbus           <= (others => '0');
          rv_bbus             <= '0';
          is_bound_to_builder <= '0';

          re_block_buffer     <= '0';
          state_bbus          <= Idle;

        when Idle =>
          re_block_buffer  <= '0';
          if(bind_bbus = '1') then
            state_bbus <= BoundBus;
          end if;

        when BoundBus =>
          case addr_bbus is
            when kEventSummary =>
              re_block_buffer  <= '0';
              dout_bbus       <= num_word_event_summary;
              rv_bbus         <= re_bbus;
            when kDataBuffer =>
              re_block_buffer <= re_bbus;
              dout_bbus       <= dout_block_buffer;
              rv_bbus         <= rv_block_buffer;
            when others =>
              null;
          end case;

          is_bound_to_builder  <= '1';
          if(bind_bbus = '0') then
            state_bbus  <= CloseBus;
          end if;

        when CloseBus =>
          re_block_buffer     <= '0';
          rv_bbus             <= '0';
          is_bound_to_builder <= '0';
          state_bbus          <= Idle;

        when others =>
          state_bbus  <= Init;
      end case;
    end if;
  end process;

  -- Reset sequence --
  u_reset_gen_sys   : entity mylib.ResetGen
    port map(rst, clk, sync_reset);

end RTL;
