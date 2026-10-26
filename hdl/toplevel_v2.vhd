library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.VComponents.all;

library mylib;
use mylib.defToplevel.all;
use mylib.defTRM.all;
use mylib.defTdcBlock.all;
use mylib.defMTDC.all;
use mylib.defYaenamiAdc.all;
use mylib.defRayrawAdcROV1.all;
use mylib.defYAENAMIController.all; -- Slow Control
use mylib.defMAX.all; -- APD_BIAS
use mylib.defEVB.all;
use mylib.defSiTCP.all;
use mylib.defRBCP.all;
use mylib.defMiiRstTimer.all;
use mylib.defBusAddressMap.all;
use mylib.defBCT.all;

use mylib.defCDCM.all;
use mylib.defMikumari.all;
use mylib.defMikumariUtil.all;
use mylib.defLaccp.all;
use mylib.defHeartBeatUnit.all;

entity toplevel is
  Port (
      -- System ---------------------------------------------------------------
    PROGB_ON            : out std_logic;
    BASE_CLKP           : in std_logic;
    BASE_CLKN           : in std_logic;
    USR_RSTB            : in std_logic;
    LED                 : out std_logic_vector(4 downto 1);
    DIP                 : in std_logic_vector(8 downto 1);
    VP                  : in std_logic;
    VN                  : in std_logic;

    -- GTX ------------------------------------------------------------------
    GTX_REFCLK_P        : in std_logic;        -- not included in .xlsx
    GTX_REFCLK_N        : in std_logic;        -- not included in .xlsx
    GTX_TX_P            : out std_logic_vector(0 downto 0);
    GTX_RX_P            : in std_logic_vector(0 downto 0);
    GTX_TX_N            : out std_logic_vector(0 downto 0);
    GTX_RX_N            : in std_logic_vector(0 downto 0);
    -- SFP_SCL             : inout std_logic;
    -- SFP_SDA             : inout std_logic;

    -- SPI flash ------------------------------------------------------------
    SPI_MOSI            : out std_logic;
    SPI_DIN             : in std_logic;
    -- SPI_D2              : in std_logic;
    -- SPI_D3              : in std_logic;
    FCSB                : out std_logic;

    -- EEPROM ---------------------------------------------------------------
    EEP_CS              : out std_logic;
    EEP_SK              : out std_logic;
    EEP_DI              : out std_logic;
    EEP_DO              : in std_logic;

    --EEP2_SCL            : out std_logic;
    --EEP2_SDA            : inout std_logic;

    -- NIM-IO ---------------------------------------------------------------
    NIM_IN              : in std_logic_vector(2 downto 1);
    NIM_OUT             : out std_logic_vector(4 downto 1);

    -- MIKUMARI -------------------------------------------------------------
    MIKUMARI_RXP        : in std_logic;
    MIKUMARI_RXN        : in std_logic;
    MIKUMARI_TXP        : out std_logic;
    MIKUMARI_TXN        : out std_logic;

    -- MISC -----------------------------------------------------------------
    EN3V3A              : out std_logic;
    AMUX_ADDR           : out std_logic_vector(1 downto 0);
    -- TEST_POINT          : out std_logic_vector(3 downto 0);

    -- ASIC -----------------------------------------------------------------
    ASIC_REFC           : out std_logic_vector(3 downto 0);
    ASIC_SSB            : out std_logic_vector(3 downto 0);
    ASIC_SCK            : out std_logic;
    ASIC_MOSI           : out std_logic;

    ASIC_DISCRI         : in std_logic_vector(31 downto 0);

    -- APD_BIAS -------------------------------------------------------------
    CP_CS_B             : out std_logic;
    CP_SCLK             : out std_logic;
    CP_DIN              : out std_logic;
    -- CP_CL_B             : in std_logic;

    -- ASIC_ADC -------------------------------------------------------------
    ADC_DATA_P          : in std_logic_vector(31 downto 0);
    ADC_DATA_N          : in std_logic_vector(31 downto 0);

    ADC_DFRAME_P        : in std_logic_vector(3 downto 0);
    ADC_DFRAME_N        : in std_logic_vector(3 downto 0);
    ADC_DCLK_P          : in std_logic_vector(3 downto 0);
    ADC_DCLK_N          : in std_logic_vector(3 downto 0)


    );
end toplevel;

architecture Behavioral of toplevel is
  attribute mark_debug : string;
  attribute keep       : string;
  constant kEnDebugTop : string := "false";

  -- System ------------------------------------------------------------------
  signal sitcp_reset  : std_logic;
  signal system_reset : std_logic;
  signal user_reset   : std_logic;
  signal bct_reset    : std_logic;
  signal emergency_reset : std_logic;
  signal rst_from_bus : std_logic;

  signal delayed_usr_rstb : std_logic;

  signal pwr_on_reset : std_logic;
  signal raw_pwr_on_reset : std_logic;

  -- DIP ---------------------------------------------------------------------
  signal dip_sw       : std_logic_vector(DIP'range);
  subtype DipID is integer range 1 to 8;
  type regLeaf is record
    Index : DipID;
  end record;
  constant kSiTCP       : regLeaf := (Index => 1);
  constant kStandAlone  : regLeaf := (Index => 2);
  constant kNC2         : regLeaf := (Index => 3);
  constant kNC3         : regLeaf := (Index => 4);
  constant kNC4         : regLeaf := (Index => 5);
  constant kNC5         : regLeaf := (Index => 6);
  constant kNC6         : regLeaf := (Index => 7);
  constant kNC7         : regLeaf := (Index => 8);

    -- MIKUMARI -----------------------------------------------------------------------------
  constant  kPcbVersion : string:= "v1";
--  constant  kPcbVersion : string:= "GN-2006-1";

  function GetMikuIoStd(version: string) return string is
  begin
    case version is
      when  "v1" => return "LVDS";
      when others       => return "LVDS_25";
    end case;
  end function;

  constant kNumMikumari       : integer:= 1;
  constant kIdMikuSec         : integer:= 0;

  signal miku_txp, miku_txn, miku_rxp, miku_rxn   : std_logic_vector(kNumMikumari-1 downto 0);

  subtype MikuScalarPort is std_logic_vector(kNumMikumari-1 downto 0);

  -- CDCM --
  signal power_on_init        : std_logic;

  signal cbt_lane_up          : MikuScalarPort;
  signal pattern_error        : MikuScalarPort;
  signal watchdog_error       : MikuScalarPort;

  signal mod_clk, gmod_clk    : std_logic;

  --type TapValueArray  is array(kNumMikumari-1 downto 0) of std_logic_vector(kWidthTap-1 downto 0);
  --type SerdesOffsetArray is array(kNumMikumari-1 downto 0) of signed(kWidthSerdesOffset-1 downto 0);
  signal tap_value_out        : TapArrayType(kNumMikumari-1 downto 0);
  signal bitslip_num_out      : BitslipArrayType(kNumMikumari-1 downto 0);
  signal serdes_offset        : SerdesOfsArrayType(kNumMikumari-1 downto 0);

  -- Mikumari --
  type MikuDataArray is array(kNumMikumari-1 downto 0) of std_logic_vector(7 downto 0);
  type MikuPulseTypeArray is array(kNumMikumari-1 downto 0) of MikumariPulseType;

  signal miku_tx_ack        : MikuScalarPort;
  signal miku_data_tx       : MikuDataArray;
  signal miku_valid_tx      : MikuScalarPort;
  signal miku_last_tx       : MikuScalarPort;
  signal busy_pulse_tx      : MikuScalarPort;

  signal mikumari_link_up   : MikuScalarPort;
  signal miku_data_rx       : MikuDataArray;
  signal miku_valid_rx      : MikuScalarPort;
  signal miku_last_rx       : MikuScalarPort;
  signal checksum_err       : MikuScalarPort;
  signal frame_broken       : MikuScalarPort;
  signal recv_terminated    : MikuScalarPort;

  signal pulse_tx, pulse_rx : MikuScalarPort;
  signal pulse_type_tx, pulse_type_rx  : MikuPulseTypeArray;

 -- LACCP --
  signal laccp_reset        : MikuScalarPort;
  signal laccp_pulse_out    : std_logic_vector(kNumLaccpPulse-1 downto 0);

  signal is_ready_for_daq   : MikuScalarPort;
  signal sync_pulse_out     : std_logic;

  signal is_ready_laccp_intra   : std_logic_vector(kNumExtIntraPort-1 downto 0);
  signal valid_laccp_intra_in   : std_logic_vector(kNumExtIntraPort-1 downto 0);
  signal valid_laccp_intra_out  : std_logic_vector(kNumExtIntraPort-1 downto 0);
  signal data_laccp_intra_in    : ExtIntraType;
  signal data_laccp_intra_out   : ExtIntraType;

  -- RLIGP --
  --type LinkAddrArray is array(kNumMikumari-1 downto 0) of std_logic_vector(kPosRegister'range);

  signal link_addr_partter  : IpAddrArrayType(kNumMikumari-1 downto 0);
  signal valid_link_addr    : MikuScalarPort;

  -- RCAP --
--  signal idelay_tap_in      : unsigned(tap_value_out'range);

  signal valid_hbc_offset   : std_logic;
  signal hbc_offset         : std_logic_vector(kWidthHbCount-1 downto 0);
  signal laccp_fine_offset  : signed(kWidthLaccpFineOffset-1 downto 0);
  signal local_fine_offset  : signed(kWidthLaccpFineOffset-1 downto 0);

  -- Heartbeat --
  signal hbu_reset          : std_logic;
  signal hbu_is_synchronized  : std_logic;
  signal heartbeat_signal   : std_logic;
  signal heartbeat_count    : std_logic_vector(kWidthHbCount-1 downto 0);
  signal hbf_number         : std_logic_vector(kWidthHbfNum-1 downto 0);
  signal hbf_state          : HbfStateType;
  signal frame_ctrl_gate    : std_logic;
  signal hbf_num_mismatch   : std_logic;

  attribute mark_debug of is_ready_for_daq   : signal is kEnDebugTop;
  attribute mark_debug of sync_pulse_out     : signal is kEnDebugTop;
  attribute mark_debug of serdes_offset      : signal is kEnDebugTop;
  attribute mark_debug of laccp_fine_offset  : signal is kEnDebugTop;
  attribute mark_debug of local_fine_offset  : signal is kEnDebugTop;

  -- Mikumari Util ------------------------------------------------------------
  signal cbt_init_from_mutil  : MikuScalarPort;
  signal rst_from_miku        : std_logic;


  -- ASIC IO -----------------------------------------------------------------
  signal asic_adc_data            :  std_logic_vector(ADC_DATA_P'range);
  signal asic_adc_fco             :  std_logic_vector(ADC_DFRAME_P'range);
  signal asic_adc_dco             :  std_logic_vector(ADC_DCLK_P'range);

  signal asic_discri_input        :  std_logic_vector(ASIC_DISCRI'range);

  signal dummy_signal             : std_logic;

  -- TRM ---------------------------------------------------------------------
  signal seq_busy, module_busy    : std_logic;
  attribute keep of seq_busy      : signal is "TRUE";
  attribute keep of module_busy   : signal is "TRUE";

  signal reg_trm2evb              : dataTrm2Evb;
  signal reg_evb2trm              : dataEvb2Trm;
  signal trigger_out              : TrigDownType;

  signal trm_event_id             : std_logic_vector(mylib.defTRM.kWidthEventId-1 downto 0);

  -- DCT -----------------------------------------------------------------------------------
  signal daq_gate                 : std_logic;
  signal evb_reset_from_DCT       : std_logic;

  -- TDC ---------------------------------------------------------------------
  signal sig_in_tdc     : arrayInput;
  signal tdc_busy       : std_logic;
  signal data_tdc_bbus  : BBusDataTDC;

  signal self_trig_nim    : std_logic;
  signal tdc_leading_hit  : std_logic_vector(kNumInput-1 downto 0);
  signal tdc_trailing_hit : std_logic_vector(kNumInput-1 downto 0);

  signal tdc_sample_id    : std_logic_vector(kWidthTdcSampleId-1 downto 0);
  signal tdc_event_id     : std_logic_vector(kWidthTdcEventId-1 downto 0);

  -- ADC ---------------------------------------------------------------------
  signal adc_busy         : std_logic;
  signal gclk_adc         : std_logic_vector(kNumASIC-1 downto 0);
  signal c_stop           : std_logic;

  -- MIKUMARI TimeStamp ------------------------------------------------------
  signal miku_ts_busy     : std_logic;

  -- IOM ----------------------------------------------------------------------------------
  signal ext_L1           : std_logic;
  signal ext_L2           : std_logic;
  signal ext_clr          : std_logic;
  signal ext_busy         : std_logic;

  -- EVB ----------------------------------------------------------------------------------
  signal evb_reset        : std_logic;

  signal addr_bbus          : BBusAddressType;
  signal data_bbus          : BBusDataArray;
  signal re_bbus            : BBusControlType;
  signal rv_bbus            : BBusControlType;
  signal dready_bbus        : BBusControlType;
  signal bind_bbus          : BBusControlType;
  signal isbound_to_builder : BBusControlType;

  -- SDS ---------------------------------------------------------------------
  signal shutdown_over_temp     : std_logic;
  signal uncorrectable_flag     : std_logic;

  -- FMP ---------------------------------------------------------------------

  -- BCT --------------------------------------------------------------------
  signal addr_LocalBus          : LocalAddressType;
  signal data_LocalBusIn        : LocalBusInType;
  signal data_LocalBusOut       : DataArray;
  signal re_LocalBus            : ControlRegArray;
  signal we_LocalBus            : ControlRegArray;
  signal ready_LocalBus         : ControlRegArray;

  -- TSD ---------------------------------------------------------------------
  signal daq_data                          : std_logic_vector(kWidthDataTCP-1 downto 0);
  signal valid_data, empty_data, req_data  : std_logic;

  -- SiTCP ---------------------------------------------------------------------------------
  signal tmp_sitcp_reset        : std_logic;
  signal tmp_sitcp_reset_prev   : std_logic;
  signal os_sitcp_reset         : std_logic;

  signal mii_reset    : std_logic;

  type typeUdpAddr is array(kNumGtx-1 downto 0) of std_logic_vector(kWidthAddrRBCP-1 downto 0);
  type typeUdpData is array(kNumGtx-1 downto 0) of std_logic_vector(kWidthDataRBCP-1 downto 0);
  type typeTcpData is array(kNumGtx-1 downto 0) of std_logic_vector(kWidthDataTCP-1 downto 0);
  type typeIpAddr  is array(kNumGtx-1 downto 0) of std_logic_vector(31 downto 0);

  signal sitcp_ip_addr  : typeIpAddr;

  signal tcp_isActive, close_req, close_act    : std_logic_vector(kNumGtx-1 downto 0);

  signal tcp_tx_clk   : std_logic_vector(kNumGtx-1 downto 0);
  signal tcp_rx_wr    : std_logic_vector(kNumGtx-1 downto 0);
  signal tcp_rx_data  : typeTcpData;
  signal tcp_tx_full  : std_logic_vector(kNumGtx-1 downto 0);
  signal tcp_tx_wr    : std_logic_vector(kNumGtx-1 downto 0);
  signal tcp_tx_data  : typeTcpData;

  signal rbcp_addr    : typeUdpAddr;
  signal rbcp_wd      : typeUdpData;
  signal rbcp_we      : std_logic_vector(kNumGtx-1 downto 0); --: Write enable
  signal rbcp_re      : std_logic_vector(kNumGtx-1 downto 0); --: Read enable
  signal rbcp_ack     : std_logic_vector(kNumGtx-1 downto 0); -- : Access acknowledge
  signal rbcp_rd      : typeUdpData;

  signal rbcp_gmii_addr    : typeUdpAddr;
  signal rbcp_gmii_wd      : typeUdpData;
  signal rbcp_gmii_we      : std_logic_vector(kNumGtx-1 downto 0); --: Write enable
  signal rbcp_gmii_re      : std_logic_vector(kNumGtx-1 downto 0); --: Read enable
  signal rbcp_gmii_ack     : std_logic_vector(kNumGtx-1 downto 0); -- : Access acknowledge
  signal rbcp_gmii_rd      : typeUdpData;

  component WRAP_SiTCP_GMII_XC7K_32K
    port
      (
        CLK                   : in std_logic; --: System Clock >129MHz
        RST                   : in std_logic; --: System reset
        -- Configuration parameters
        FORCE_DEFAULTn        : in std_logic; --: Load default parameters
        EXT_IP_ADDR           : in std_logic_vector(31 downto 0); --: IP address[31:0]
        EXT_TCP_PORT          : in std_logic_vector(15 downto 0); --: TCP port #[15:0]
        EXT_RBCP_PORT         : in std_logic_vector(15 downto 0); --: RBCP port #[15:0]
        PHY_ADDR              : in std_logic_vector(4 downto 0);  --: PHY-device MIF address[4:0]

        -- EEPROM
        EEPROM_CS             : out std_logic; --: Chip select
        EEPROM_SK             : out std_logic; --: Serial data clock
        EEPROM_DI             : out    std_logic; --: Serial write data
        EEPROM_DO             : in std_logic; --: Serial read data
        --    user data, intialial values are stored in the EEPROM, 0xFFFF_FC3C-3F
        USR_REG_X3C           : out    std_logic_vector(7 downto 0); --: Stored at 0xFFFF_FF3C
        USR_REG_X3D           : out    std_logic_vector(7 downto 0); --: Stored at 0xFFFF_FF3D
        USR_REG_X3E           : out    std_logic_vector(7 downto 0); --: Stored at 0xFFFF_FF3E
        USR_REG_X3F           : out    std_logic_vector(7 downto 0); --: Stored at 0xFFFF_FF3F
        -- MII interface
        GMII_RSTn             : out    std_logic; --: PHY reset
        GMII_1000M            : in std_logic;  --: GMII mode (0:MII, 1:GMII)
        -- TX
        GMII_TX_CLK           : in std_logic; -- : Tx clock
        GMII_TX_EN            : out    std_logic; --: Tx enable
        GMII_TXD              : out    std_logic_vector(7 downto 0); --: Tx data[7:0]
        GMII_TX_ER            : out    std_logic; --: TX error
        -- RX
        GMII_RX_CLK           : in std_logic; -- : Rx clock
        GMII_RX_DV            : in std_logic; -- : Rx data valid
        GMII_RXD              : in std_logic_vector(7 downto 0); -- : Rx data[7:0]
        GMII_RX_ER            : in std_logic; --: Rx error
        GMII_CRS              : in std_logic; --: Carrier sense
        GMII_COL              : in std_logic; --: Collision detected
        -- Management IF
        GMII_MDC              : out std_logic; --: Clock for MDIO
        GMII_MDIO_IN          : in std_logic; -- : Data
        GMII_MDIO_OUT         : out    std_logic; --: Data
        GMII_MDIO_OE          : out    std_logic; --: MDIO output enable
        -- User I/F
        SiTCP_RST             : out    std_logic; --: Reset for SiTCP and related circuits
        IP_ADDR               : out    std_logic_vector(31 downto 0);
        -- TCP connection control
        TCP_OPEN_REQ          : in std_logic; -- : Reserved input, shoud be 0
        TCP_OPEN_ACK          : out    std_logic; --: Acknowledge for open (=Socket busy)
        TCP_ERROR             : out    std_logic; --: TCP error, its active period is equal to MSL
        TCP_CLOSE_REQ         : out    std_logic; --: Connection close request
        TCP_CLOSE_ACK         : in std_logic ;-- : Acknowledge for closing
        -- FIFO I/F
        TCP_RX_WC             : in std_logic_vector(15 downto 0); --: Rx FIFO write count[15:0] (Unused bits should be set 1)
        TCP_RX_WR             : out    std_logic; --: Write enable
        TCP_RX_DATA           : out    std_logic_vector(7 downto 0); --: Write data[7:0]
        TCP_TX_FULL           : out    std_logic; --: Almost full flag
        TCP_TX_WR             : in std_logic; -- : Write enable
        TCP_TX_DATA           : in std_logic_vector(7 downto 0); -- : Write data[7:0]
        -- RBCP
        RBCP_ACT              : out std_logic; -- RBCP active
        RBCP_ADDR             : out    std_logic_vector(31 downto 0); --: Address[31:0]
        RBCP_WD               : out    std_logic_vector(7 downto 0); --: Data[7:0]
        RBCP_WE               : out    std_logic; --: Write enable
        RBCP_RE               : out    std_logic; --: Read enable
        RBCP_ACK              : in std_logic; -- : Access acknowledge
        RBCP_RD               : in std_logic_vector(7 downto 0 ) -- : Read data[7:0]
        );
  end component;

  -- SFP transceiver -----------------------------------------------------------------------
  constant kPcsPmaLinkStatus  : integer:= 0;
  signal pcs_pma_status       : std_logic_vector(15 downto 0);

  constant kMiiPhyad      : std_logic_vector(kWidthPhyAddr-1 downto 0):= "00000";
  signal mii_init_mdc, mii_init_mdio : std_logic;

  component mii_initializer is
    port(
      -- System
      CLK         : in std_logic;
      --RST         => system_reset,
      RST         : in std_logic;
      -- PHY
      PHYAD       : in std_logic_vector(kWidthPhyAddr-1 downto 0);
      -- MII
      MDC         : out std_logic;
      MDIO_OUT    : out std_logic;
      -- status
      COMPLETE    : out std_logic
      );
  end component;

  signal mmcm_reset_all   : std_logic;
  signal mmcm_reset       : std_logic_vector(kNumGtx-1 downto 0);
  signal mmcm_locked      : std_logic;

  signal gt0_qplloutclk, gt0_qplloutrefclk  : std_logic;
  signal gtrefclk_i, gtrefclk_bufg  : std_logic;
  signal txout_clk, rxout_clk       : std_logic_vector(kNumGtx-1 downto 0);
  signal user_clk, user_clk2, rxuser_clk, rxuser_clk2   : std_logic;

  signal eth_tx_clk       : std_logic_vector(kNumGtx-1 downto 0);
  signal eth_tx_en        : std_logic_vector(kNumGtx-1 downto 0);
  signal eth_tx_er        : std_logic_vector(kNumGtx-1 downto 0);
  signal eth_tx_d         : typeTcpData;

  signal eth_rx_clk       : std_logic_vector(kNumGtx-1 downto 0);
  signal eth_rx_dv        : std_logic_vector(kNumGtx-1 downto 0);
  signal eth_rx_er        : std_logic_vector(kNumGtx-1 downto 0);
  signal eth_rx_d         : typeTcpData;


  -- Clock -------------------------------------------------------------------
  signal clk_tdc                    : std_logic_vector(kNumTdcClock-1 downto 0);
  signal clk_sys                    : std_logic;
  signal clk_link, clk_indep        : std_logic;
  signal clk_spi                    : std_logic;
  signal clk_locked_sys             : std_logic;
  signal clk_locked_cdcm            : std_logic;
  signal clk_locked                 : std_logic;
  signal mmcm_cdcm_reset            : std_logic;

  signal clk_10MHz, clk_1MHz, clk_100kHz, clk_10kHz, clk_1kHz : std_logic;

  component clk_wiz_sys
    port
     (-- Clock in ports
      -- Clock out ports
      clk_link          : out    std_logic;
      clk_indep          : out    std_logic;
      clk_spi          : out    std_logic;
      clk_10MHz          : out    std_logic;
      -- Status and control signals
      reset             : in     std_logic;
      locked            : out    std_logic;
      clk_in1_p         : in     std_logic;
      clk_in1_n         : in     std_logic
     );
  end component;

  component clk_wiz_cdcm
    port
     (-- Clock in ports
      -- Clock out ports
      clk_sys          : out    std_logic;
      clk_tdc0          : out    std_logic;
      clk_tdc1          : out    std_logic;
      clk_tdc2          : out    std_logic;
      clk_tdc3          : out    std_logic;
      -- Status and control signals
      reset             : in     std_logic;
      locked            : out    std_logic;
      clk_in1           : in     std_logic
     );
  end component;

  signal clk_slow, clk_fast, clk_locked_miku  : std_logic;

  component mmcm_mikumari
    port
     (-- Clock in ports
      clk_in2           : in     std_logic;
      clk_in_sel        : in     std_logic;
      -- Clock out ports
      clk_slow          : out    std_logic;
      clk_fast          : out    std_logic;
      -- Status and control signals
      reset             : in     std_logic;
      locked            : out    std_logic;
      clk_in1           : in     std_logic
     );
    end component;

  -- debug -----------------------------------------------------------------------------
  --attribute mark_debug of clk_150MHz : signal is "true";
  -- attribute mark_debug of self_trig_nim : signal is "true";
  -- attribute mark_debug of module_busy : signal is "true";

begin
  -- ===================================================================================
  -- body
  -- ===================================================================================

  -- Global ------------------------------------------------------------------
  u_DelayUsrRstb : entity mylib.DelayGen
    generic map(kNumDelay => 128)
    port map(clk_link, USR_RSTB, delayed_usr_rstb);

  --mmcm_cdcm_reset <= (not delayed_usr_rstb);

  --clk_locked    <= clk_locked_sys and clk_locked_cdcm;
  --miku_reset        <= (not clk_locked_miku) or (not USR_RSTB);
  system_reset      <= (NOT clk_locked_cdcm) or (not USR_RSTB);
  raw_pwr_on_reset  <= (not clk_locked_cdcm);
  u_KeepPwrOnRst : entity mylib.RstDelayTimer
    port map(raw_pwr_on_reset, X"0FFFFFFF", clk_link, open, pwr_on_reset);

  user_reset        <= system_reset or rst_from_bus or emergency_reset;
  bct_reset         <= system_reset or emergency_reset;

  dip_sw(1)   <= DIP(1);
  dip_sw(2)   <= DIP(2);
  dip_sw(3)   <= DIP(3);
  dip_sw(4)   <= DIP(4);
  dip_sw(5)   <= DIP(5);
  dip_sw(6)   <= DIP(6);
  dip_sw(7)   <= DIP(7);
  dip_sw(8)   <= DIP(8);

  NIM_OUT(1)  <= clk_sys;
  NIM_OUT(2)  <= module_busy;
  NIM_OUT(3)  <= self_trig_nim;
  NIM_OUT(4)  <= '0';
--  NIM_OUT(2)  <= gclk_adc(0) when (DIP(7 downto 6) = "00") else
--                 gclk_adc(1) when (DIP(7 downto 6) = "01") else
--                 gclk_adc(2) when (DIP(7 downto 6) = "10") else
--                 gclk_adc(3) when (DIP(7 downto 6) = "11") else gclk_adc(0);

  ASIC_REFC <= (clk_sys & clk_sys & clk_sys & clk_sys);

  dummy_signal  <= or_reduce(asic_adc_data) or or_reduce(asic_adc_fco) or or_reduce(asic_adc_dco);

  EN3V3A      <= '1';

  -- Mezzanine connection --------------------------------------------------------------
  MIKUMARI_TXP  <= miku_txp(kIdMikuSec);
  MIKUMARI_TXN  <= miku_txn(kIdMikuSec);
  miku_rxp(kIdMikuSec)  <= MIKUMARI_RXP;
  miku_rxn(kIdMikuSec)  <= MIKUMARI_RXN;

  -- MIKUMARI --------------------------------------------------------------------------
  u_KeepInit : entity mylib.RstDelayTimer
    port map(system_reset, X"0FFFFFFF", clk_slow, open, power_on_init );

  gen_mikumari : for i in 0 to kNumMikumari-1 generate
    laccp_reset(i) <= system_reset or (not mikumari_link_up(i));

    u_Miku_Inst : entity mylib.MikumariBlock
      generic map(
        -- CBT generic -------------------------------------------------------------
        -- CDCM-Mod-Pattern --
        kCdcmModWidth    => 8,
        -- CDCM-TX --
        kIoStandardTx    => GetMikuIoStd(kPcbVersion),
        kTxPolarity      => TRUE,
        -- CDCM-RX --
        genIDELAYCTRL    => TRUE,
        kDiffTerm        => TRUE,
        kIoStandardRx    => GetMikuIoStd(kPcbVersion),
        kRxPolarity      => TRUE,
        kIoDelayGroup    => "idelay_miku",
        kFixIdelayTap    => FALSE,
        kFreqFastClk     => 500.0,
        kFreqRefClk      => 200.0,
        -- Encoder/Decoder
        kNumEncodeBits   => 1,
        -- Master/Slave
        kCbtMode         => "Slave",
        -- DEBUG --
        enDebugCBT       => FALSE,

        -- MIKUMARI generic --------------------------------------------------------
        enScrambler      => TRUE,
        kHighPrecision   => FALSE,
        -- DEBUG --
        enDebugMikumari  => FALSE
      )
      port map(
        -- System ports -----------------------------------------------------------
        rst           => system_reset,
        pwrOnRst      => pwr_on_reset,
        clkSer        => clk_fast,
        clkPar        => clk_slow,
        clkIndep      => clk_indep,
        clkIdctrl     => clk_indep,
        initIn        => power_on_init or cbt_init_from_mutil(i),

        TXP           => MIKUMARI_TXP,
        TXN           => MIKUMARI_TXN,
        RXP           => MIKUMARI_RXP,
        RXN           => MIKUMARI_RXN,
        modClk        => mod_clk,
        tapValueIn    => (others => '0'),
        txBeat        => open,

        -- CBT ports ------------------------------------------------------------
        laneUp        => cbt_lane_up(i),
        idelayErr     => open,
        bitslipErr    => open,
        pattErr       => pattern_error(i),
        watchDogErr   => watchdog_error(i),

        tapValueOut   => tap_value_out(i),
        bitslipNum    => bitslip_num_out(i),
        serdesOffset  => serdes_offset(i),
        firstBitPatt  => open,

        -- Mikumari ports -------------------------------------------------------
        linkUp        => mikumari_link_up(i),

        -- TX port --
        -- Data I/F --
        dataInTx      => miku_data_tx(i),
        validInTx     => miku_valid_tx(i),
        frameLastInTx => miku_last_tx(i),
        txAck         => miku_tx_ack(i),

        pulseIn       => pulse_tx(i),
        pulseTypeTx   => pulse_type_tx(i),
        pulseRegTx    => "0000",
        busyPulseTx   => busy_pulse_tx(i),

        -- RX port --
        -- Data I/F --
        dataOutRx   => miku_data_rx(i),
        validOutRx  => miku_valid_rx(i),
        frameLastRx => miku_last_rx(i),
        checksumErr => checksum_err(i),
        frameBroken => frame_broken(i),
        recvTermnd  => recv_terminated(i),

        pulseOut    => pulse_rx(i),
        pulseTypeRx => pulse_type_rx(i),
        pulseRegRx  => open

      );

    --
    --idelay_tap_in   <= unsigned(tap_value_out);

    u_LACCP : entity mylib.LaccpMainBlock
      generic map
        (
          kPrimaryMode      => false,
          kNumInterconnect  => 1,
          enDebug           => false
        )
      port map
        (
          -- System --------------------------------------------------------
          rst               => laccp_reset(i),
          clk               => clk_slow,

          -- User Interface ------------------------------------------------
          isReadyForDaq     => is_ready_for_daq(i),
          laccpPulsesIn     => (others => '0'),
          laccpPulsesOut    => laccp_pulse_out,
          pulseInRejected   => open,

          -- RLIGP --
          addrMyLink        => sitcp_ip_addr(0),
          validMyLink       => not emergency_reset,
          addrPartnerLink   => link_addr_partter(i),
          validPartnerLink  => valid_link_addr(i),

          -- RCAP --
          idelayTapIn       => unsigned(tap_value_out(i)),
          serdesLantencyIn  => serdes_offset(i),
          idelayTapOut      => open,
          serdesLantencyOut => open,

          hbuIsSyncedIn     => hbu_is_synchronized,
          syncPulseIn       => '0',
          syncPulseOut      => sync_pulse_out,

          upstreamOffset    => (others => '0'),
          validOffset       => valid_hbc_offset,
          hbcOffset         => hbc_offset,
          fineOffset        => laccp_fine_offset,
          fineOffsetLocal   => local_fine_offset,

          -- LACCP Bus Port ------------------------------------------------
          -- Intra-port--
          isReadyIntraIn    => is_ready_laccp_intra,
          dataIntraIn       => data_laccp_intra_in,
          validIntraIn      => valid_laccp_intra_in,
          dataIntraOut      => data_laccp_intra_out,
          validIntraOut     => valid_laccp_intra_out,

          -- Interconnect --
          isReadyInterIn    => (others => '0'),
          existInterOut     => open,
          dataInterIn       => (others => (others => '0')),
          validInterIn      => (others => '0'),
          dataInterOut      => open,
          validInterOut     => open,

          -- MIKUMARI-Link -------------------------------------------------
          mikuLinkUpIn      => mikumari_link_up(i),

          -- TX port --
          dataTx            => miku_data_tx(i),
          validTx           => miku_valid_tx(i),
          frameLastTx       => miku_last_tx(i),
          txAck             => miku_tx_ack(i),

          pulseTx           => pulse_tx(i),
          pulseTypeTx       => pulse_type_tx(i),
          busyPulseTx       => busy_pulse_tx(i),

          -- RX port --
          dataRx            => miku_data_rx(i),
          validRx           => miku_valid_rx(i),
          frameLastRx       => miku_last_rx(i),
          checkSumErrRx     => checksum_err(i),
          frameBrokenRx     => frame_broken(i),
          recvTermndRx      => recv_terminated(i),

          pulseRx           => pulse_rx(i),
          pulseTypeRx       => pulse_type_rx(i)

        );
  end generate;

  --
  --u_sync_nim1 : entity mylib.synchronizer port map(clk_slow, NIM_IN(1), frame_ctrl_gate);
  frame_ctrl_gate <= '0';
  hbu_reset       <= system_reset when(dip_sw(kStandAlone.Index) = '1') else laccp_reset(0);

  u_HBU : entity mylib.HeartBeatUnit
    generic map
      (
        enDebug           => false
      )
    port map
      (
        -- System --
        rst               => hbu_reset,
        clk               => clk_slow,
        enStandAlone      => DIP(kStandAlone.Index),
        keepLocalHbfNum   => '1',

        -- Sync I/F --
        syncPulseIn       => sync_pulse_out,
        hbcOffsetIn       => hbc_offset,
        validOffsetIn     => valid_hbc_offset,
        isSynchronized    => hbu_is_synchronized,

        -- HeartBeat I/F --
        heartbeatOut      => heartbeat_signal,
        heartbeatCount    => heartbeat_count,
        hbfNumber         => hbf_number,
        hbfNumMismatch    => hbf_num_mismatch,
        clkDiv16          => open,

        -- DAQ I/F --
        hbfCtrlGateIn     => frame_ctrl_gate,
        forceOn           => '1',
        frameState        => hbf_state,

        hbfFlagsIn        => "00",
        frameFlags        => open,

        -- LACCP Bus --
        dataBusIn         => data_laccp_intra_out(GetExtIntraIndex(kPortHBU)),
        validBusIn        => valid_laccp_intra_out(GetExtIntraIndex(kPortHBU)),
        dataBusOut        => data_laccp_intra_in(GetExtIntraIndex(kPortHBU)),
        validBusOut       => valid_laccp_intra_in(GetExtIntraIndex(kPortHBU)),
        isReadyOut        => is_ready_laccp_intra(GetExtIntraIndex(kPortHBU))

      );

  -- MIKUMARI utility ---------------------------------------------------------------------
  u_MUTIL : entity mylib.MikumariUtil
    generic map(
      kNumMikumari => kNumMikumari,
      kSecondaryId => kIdMikuSec,
      kWidthHbCount => kWidthHbCount,
      kWidthLaccpFineOffset => kWidthLaccpFineOffset
    )
    port map(
      -- System ----------------------------------------------------
      rst               => user_reset,
      clk               => clk_slow,

      clockRootMode     => DIP(kStandAlone.Index),

      -- CBT status ports --
      cbtLaneUp           => cbt_lane_up,
      tapValueIn          => tap_value_out,
      bitslipNumIn        => bitslip_num_out,
      cbtInitOut          => cbt_init_from_mutil,
      tapValueOut         => open,
      rstOverMikuOut      => open,

      -- MIKUMARI Link ports --
      mikuLinkUp          => mikumari_link_up,

      -- LACCP ports --
      laccpUp             => is_ready_for_daq,
      partnerIpAddr       => link_addr_partter,
      hbcOffset           => hbc_offset,
      localFineOffset     => std_logic_vector(local_fine_offset),
      laccpFineOffset     => std_logic_vector(laccp_fine_offset),
      hbfState            => open,

      -- Local bus --
      addrLocalBus        => addr_LocalBus,
      dataLocalBusIn      => data_LocalBusIn,
      dataLocalBusOut     => data_LocalBusOut(kMUTIL.ID),
      reLocalBus          => re_LocalBus(kMUTIL.ID),
      weLocalBus          => we_LocalBus(kMUTIL.ID),
      readyLocalBus       => ready_LocalBus(kMUTIL.ID)
    );


  -- Fixed IO ports --------------------------------------------------------------------
  asic_discri_input  <= ASIC_DISCRI;

  -- TRM -------------------------------------------------------------------------------
  -- LED <= clk_locked_sys & clk_locked_cdcm & module_busy &  tcp_isActive;
  LED <= sitcp_reset & clk_locked_miku & module_busy &  tcp_isActive;

  seq_busy   <= tdc_busy OR adc_busy or miku_ts_busy; -- OR dip_sw(kFBUSY.Index);

  u_TRM_Inst :  entity mylib.TriggerManager
    port map(
      RST                     => user_reset,
      CLK                     => clk_sys,

      -- Busy In --
      sequenceBusy            => seq_busy,
      gateDAQ                 => daq_gate,

      -- Busy Out --
      moduleBusy              => module_busy,

      -- Ext trigger    In --
      ExtClear                => '0',
      ExtL1                   => ext_L1,
      ExtL2                   => '0',
      ExtTAG                  => "0000",

      -- J0 trigger --
      J0Clear                 => '0',
      J0L1                    => '0',
      J0L2                    => '0',
      J0TAG                   => "0000",
      EnJ0C                   => open,

      -- RM trigger --
      RMClear                 => '0',
      RML1                    => '0',
      RML2                    => '0',
      RMTAG                   => "0000",

      -- Self trigger --
      SelfClear                 => '0',
      SelfL1                    => '0',
      SelfL2                    => '0',
      SelfTAG                   => "0000",

      -- module input --
      dInTRM                  => reg_evb2trm,

      -- module output --
      TriggerToDAQ            => trigger_out,
      dOutTRM                 => reg_trm2evb,

      -- Local bus --
      addrLocalBus        => addr_LocalBus,
      dataLocalBusIn      => data_LocalBusIn,
      dataLocalBusOut     => data_LocalBusOut(kTRM.ID),
      reLocalBus          => re_LocalBus(kTRM.ID),
      weLocalBus          => we_LocalBus(kTRM.ID),
      readyLocalBus       => ready_LocalBus(kTRM.ID),

      -- Event Id --
      eventIdOut          => trm_event_id
      );

  -- DCT -------------------------------------------------------------------------------
  u_DCT_Inst :  entity mylib.DAQController
    port map(
      rst                 => user_reset,
      clk                 => clk_sys,
      -- Module output --
      daqGate             => daq_gate,
      rstEvb              => evb_reset_from_DCT,
      -- Local bus --
      addrLocalBus        => addr_LocalBus,
      dataLocalBusIn      => data_LocalBusIn,
      dataLocalBusOut     => data_LocalBusOut(kDCT.ID),
      reLocalBus          => re_LocalBus(kDCT.ID),
      weLocalBus          => we_LocalBus(kDCT.ID),
      readyLocalBus       => ready_LocalBus(kDCT.ID)
      );

  -- TDC -------------------------------------------------------------------------------
  --sig_in_tdc(0)(0)             <= NIM_IN(2);
  --sig_in_tdc(0)(31 downto 1)   <= ASIC_DISCRI(31 downto 1);
  sig_in_tdc(0)   <= ASIC_DISCRI;

  data_bbus(kBbTDCL0.ID) <= data_tdc_bbus(0);
  data_bbus(kBbTDCT0.ID) <= data_tdc_bbus(1);

  u_TDC_Inst : entity mylib.MTDC
    port map(
      rst         => user_reset,
      clk         => clk_sys,
      clkTdc      => clk_tdc,

      -- Module input --
      enRM        => '0',
      triggerIn   => trigger_out,
      sigIn       => sig_in_tdc,

      -- Module output --
      busyTdc     => tdc_busy,
      cStop       => c_stop,

      -- Builder bus --
      addrBuilderBus      => addr_bbus,
      dataBuilderBusOut   => data_tdc_bbus,
      reBuilderBus        => re_bbus(kBbTDCT0.ID downto kBbTDCL0.ID),
      rvBuilderBus        => rv_bbus(kBbTDCT0.ID downto kBbTDCL0.ID),
      dReadyBuilderBus    => dready_bbus(kBbTDCT0.ID downto kBbTDCL0.ID),
      bindBuilderBus      => bind_bbus(kBbTDCT0.ID downto kBbTDCL0.ID),
      isBoundToBuilder    => isbound_to_builder(kBbTDCT0.ID downto kBbTDCL0.ID),

      -- Local bus --
      addrLocalBus        => addr_LocalBus,
      dataLocalBusIn      => data_LocalBusIn,
      dataLocalBusOut     => data_LocalBusOut(kTDC.ID),
      reLocalBus          => re_LocalBus(kTDC.ID),
      weLocalBus          => we_LocalBus(kTDC.ID),
      readyLocalBus       => ready_LocalBus(kTDC.ID),

      -- Self trigger --
      selfTrig            => self_trig_nim,

      -- Hit info --
      tdcLeadingHitOut     => tdc_leading_hit,
      tdcTrailingHitOut    => tdc_trailing_hit,

      -- Tdc Id --
      tdcSampleIdOut       => tdc_sample_id,

      -- Event Id --
      eventIdIn            => trm_event_id,
      eventIdOut           => tdc_event_id
      );

  -- ADC -------------------------------------------------------------------------------
   --<= data_adc_bbus;

  u_ADC_Inst : entity mylib.AdcBlock
    port map(
      rst           => user_reset,
      clkSys        => clk_sys,
      clkIdelayRef  => clk_indep,
      clkAdc        => open, -- gclk_adc

      -- Module input --
      ADC_DATA_P    => ADC_DATA_P,
      ADC_DATA_N    => ADC_DATA_N,
      ADC_DFRAME_P  => ADC_DFRAME_P,
      ADC_DFRAME_N  => ADC_DFRAME_N,
      ADC_DCLK_P    => ADC_DCLK_P,
      ADC_DCLK_N    => ADC_DCLK_N,
      cStop         => c_stop,

      -- Modle output --
      busyAdc => adc_busy,

      -- Builder bus -- TODO: change later
      addrBuilderBus      => addr_bbus,
      dataBuilderBusOut   => data_bbus(kBbADC.ID),
      reBuilderBus        => re_bbus(kBbADC.ID),
      rvBuilderBus        => rv_bbus(kBbADC.ID),
      dReadyBuilderBus    => dready_bbus(kBbADC.ID),
      bindBuilderBus      => bind_bbus(kBbADC.ID),
      isBoundToBuilder    => isbound_to_builder(kBbADC.ID),

      -- Local bus --
      addrLocalBus        => addr_LocalBus,
      dataLocalBusIn      => data_LocalBusIn,
      dataLocalBusOut     => data_LocalBusOut(kADC.ID),
      reLocalBus          => re_LocalBus(kADC.ID),
      weLocalBus          => we_LocalBus(kADC.ID),
      readyLocalBus       => ready_LocalBus(kADC.ID),

      -- Tdc hit --
      tdcLeadingHitIn     => tdc_leading_hit,
      tdcTrailingHitIn    => tdc_trailing_hit,

      -- Sample Id --
      tdcSampleIdIn       => tdc_sample_id,

      -- Event Id --
      eventIdIn           => tdc_event_id
      );


  -- MIKUMARI TimeStamp ----------------------------------------------------------------
  u_MIKUTS_Inst : entity mylib.MikuTimeStamp
    port map (
      rst                 => user_reset,
      clk                 => clk_sys,
      clkSlow             => clk_slow,

      -- LACCP TimeStamp --
      timeStamp           => hbf_number(7 downto 0) & heartbeat_count,

      -- data in --
      triggerIn           => trigger_out,

      -- data out --
      moduleBusy          => miku_ts_busy,

      -- Builder bus --
      addrBuilderBus      => addr_bbus,
      dataBuilderBusOut   => data_bbus(kBbMIKUTS.ID),
      reBuilderBus        => re_bbus(kBbMIKUTS.ID),
      rvBuilderBus        => rv_bbus(kBbMIKUTS.ID),
      dReadyBuilderBus    => dready_bbus(kBbMIKUTS.ID),
      bindBuilderBus      => bind_bbus(kBbMIKUTS.ID),
      isBoundToBuilder    => isbound_to_builder(kBbMIKUTS.ID)

      );

  -- IOM -------------------------------------------------------------------------------
  u_IOM_Inst : entity mylib.IOManager
    port map(
      rst                 => user_reset,
      clk                 => clk_sys,

      -- Analog Monitor (rayraw-v2 only) --
      addrAmon            => AMUX_ADDR,

      -- NIM input signal --
      NimIn               => NIM_IN,
      ExtL1               => ext_L1,
      ExtL2               => ext_L2,
      ExtClr              => ext_clr,
      ExtBusy             => ext_busy,

      -- NIM output signal --
      -- NimOut              => NIM_OUT,
      NimOut              => open,
      ModuleBusy          => module_busy,
      DaqGate             => daq_gate,
      clk1MHz             => clk_1MHz,
      clk100kHz           => clk_100kHz,
      clk10kHz            => clk_10kHz,
      clk1kHz             => clk_1kHz,

      -- Local bus --
      addrLocalBus        => addr_LocalBus,
      dataLocalBusIn      => data_LocalBusIn,
      dataLocalBusOut     => data_LocalBusOut(kIOM.ID),
      reLocalBus          => re_LocalBus(kIOM.ID),
      weLocalBus          => we_LocalBus(kIOM.ID),
      readyLocalBus       => ready_LocalBus(kIOM.ID)
      );
  -- YSC (YAENAMI Slow Control) ---------------------------------------------------------
  u_YSC_Inst : entity mylib.YAENAMIController
    generic map  -- use generic parameters in SctDriver.vhd
    (
      kFreqSysClk   => 75_000_000,
      kNumIO        => kNumIO,   -- # of MOSI lines: defined in defToplevel.vhd
      kNumASIC      => kNumASIC, -- # of ASICs; defined in defToplevel.vhd
      enDebug       => false
    )
    port map
    (
      -- System --
      rst         => user_reset,   -- port name(defined in SctDriver) => signal name
      clk         => clk_sys,

      -- Rx Chip port --
      SSB         => ASIC_SSB,  -- vector
      MOSI        => ASIC_MOSI,
      SCK         => ASIC_SCK,

      -- Local bus --
      addrLocalBus      => addr_LocalBus,
      dataLocalBusIn    => data_LocalBusIn,
      dataLocalBusOut   => data_LocalBusOut(kYSC.ID),
      reLocalBus        => re_LocalBus(kYSC.ID),
      weLocalBus        => we_LocalBus(kYSC.ID),
      readyLocalBus     => ready_LocalBus(kYSC.ID)
  );

  -- APD_BIAS -------------------------------------------------------------------------
  u_APD_Inst : entity mylib.MAX1932Controller
    generic map(
      kSysClkFreq         => 100_000_000
    )
    port map(
      rst	          => user_reset,
      clk	          => clk_sys,

      -- Module output --
      CSB_SPI           => CP_CS_B,
      SCLK_SPI          => CP_SCLK,
      MOSI_SPI          => CP_DIN,

      -- Local bus --
      addrLocalBus	    => addr_LocalBus,
      dataLocalBusIn	  => data_LocalBusIn,
      dataLocalBusOut	  => data_LocalBusOut(kAPD.ID),
      reLocalBus	      => re_LocalBus(kAPD.ID),
      weLocalBus	      => we_LocalBus(kAPD.ID),
      readyLocalBus	    => ready_LocalBus(kAPD.ID)
    );


  -- EVB -------------------------------------------------------------------------------
  evb_reset   <= user_reset OR evb_reset_from_DCT;

  u_EVB_Inst : entity mylib.EventBuilder
    generic map(
      kEigenWord  => x"ffff0162"
    )
    port map(
      rst         => evb_reset,
      clk         => clk_sys,
      clkLink     => clk_link,
      EnRM        => '0',

      -- TRM data --
      dInTRM      => reg_trm2evb,
      dOutTRM     => reg_evb2trm,

      -- Builder bus --
      addrBuilderBus      => addr_bbus,
      dataBuilderBusIn    => data_bbus,
      reBuilderBus        => re_bbus,
      rvBuilderBus        => rv_bbus,
      dReadyBuilderBus    => dready_bbus,
      bindBuilderBus      => bind_bbus,
      isBoundToBuilder    => isbound_to_builder,

      -- TSD data --
      rdToTSD     => daq_data,
      rvToTSD     => valid_data,
      emptyToTSD  => empty_data,
      reFromTSD   => req_data
      );

  -- SDS --------------------------------------------------------------------
  u_SDS_Inst : entity mylib.SelfDiagnosisSystem
    port map(
      rst               => user_reset,
      clk               => clk_sys,
      clkIcap           => clk_spi,

      -- Module input  --
      VP                => VP,
      VN                => VN,

      -- Module output --
      shutdownOverTemp  => shutdown_over_temp,
      xadcTempOut        => open,
      uncorrectableAlarm => uncorrectable_flag,

      -- Local bus --
      addrLocalBus      => addr_LocalBus,
      dataLocalBusIn    => data_LocalBusIn,
      dataLocalBusOut   => data_LocalBusOut(kSDS.ID),
      reLocalBus        => re_LocalBus(kSDS.ID),
      weLocalBus        => we_LocalBus(kSDS.ID),
      readyLocalBus     => ready_LocalBus(kSDS.ID)
      );


  -- FMP --------------------------------------------------------------------
  u_FMP_Inst : entity mylib.FlashMemoryProgrammer
    port map(
      rst	              => user_reset,
      clk	              => clk_sys,
      clkSpi            => clk_spi,

      -- Module output --
      CS_SPI            => FCSB,
--      SCLK_SPI          => USR_CLK,
      MOSI_SPI          => SPI_MOSI,
      MISO_SPI          => SPI_DIN,

      -- Local bus --
      addrLocalBus      => addr_LocalBus,
      dataLocalBusIn    => data_LocalBusIn,
      dataLocalBusOut   => data_LocalBusOut(kFMP.ID),
      reLocalBus        => re_LocalBus(kFMP.ID),
      weLocalBus        => we_LocalBus(kFMP.ID),
      readyLocalBus     => ready_LocalBus(kFMP.ID)
      );


  -- BCT --------------------------------------------------------------------
  u_BCT_Inst : entity mylib.BusController
    port map(
      rstSys                    => bct_reset or sitcp_reset,
      rstFromBus                => rst_from_bus,
      reConfig                  => PROGB_ON,
      clk                       => clk_sys,
      -- Local Bus --
      addrLocalBus              => addr_LocalBus,
      dataFromUserModules       => data_LocalBusOut,
      dataToUserModules         => data_LocalBusIn,
      reLocalBus                => re_LocalBus,
      weLocalBus                => we_LocalBus,
      readyLocalBus             => ready_LocalBus,
      -- RBCP --
      addrRBCP                  => rbcp_addr(0),
      wdRBCP                    => rbcp_wd(0),
      weRBCP                    => rbcp_we(0),
      reRBCP                    => rbcp_re(0),
      ackRBCP                   => rbcp_ack(0),
      rdRBCP                    => rbcp_rd(0)
      );

  -- TSD ---------------------------------------------------------------------
  u_TSD_Inst : entity mylib.TCP_sender
    port map(
      RST               => pwr_on_reset,
      CLK               => clk_link,

      -- data from EVB --
      rdFromEVB         => daq_data,
      rvFromEVB         => valid_data,
      emptyFromEVB      => empty_data,
      reToEVB           => req_data,

      -- data to SiTCP
      isActive          => tcp_isActive(0),
      afullTx           => tcp_tx_full(0),
      weTx              => tcp_tx_wr(0),
      wdTx              => tcp_tx_data(0)
      );


  -- SiTCP Inst ------------------------------------------------------------------------
  --sitcp_reset     <= system_reset OR (NOT USR_RSTB);
  u_SiTCPRst : entity mylib.ResetGen
    port map((not pcs_pma_status(kPcsPmaLinkStatus)) or (not delayed_usr_rstb ), clk_link, tmp_sitcp_reset);

  process(clk_link)
  begin
    if(clk_link'event and clk_link='1') then
      -- Edge detection of tmp_sitcp_reset and make one clock wide pulse
      os_sitcp_reset <= tmp_sitcp_reset OR (tmp_sitcp_reset_prev AND (not tmp_sitcp_reset));
      tmp_sitcp_reset_prev <= tmp_sitcp_reset;
    end if;
  end process;

  u_KeepSiTCPRst : entity mylib.RstDelayTimer
    port map(os_sitcp_reset, X"00000FFF", clk_link, open, sitcp_reset);

  gen_SiTCP : for i in 0 to kNumGtx-1 generate

    eth_tx_clk(i)      <= eth_rx_clk(0);

    u_SiTCP_Inst : WRAP_SiTCP_GMII_XC7K_32K
      port map
      (
        CLK               => clk_link, --: System Clock >129MHz
        RST               => sitcp_reset, --: System reset
        -- Configuration parameters
        FORCE_DEFAULTn    => dip_sw(kSiTCP.Index), --: Load default parameters
        --FORCE_DEFAULTn    => '0', --: Load default parameters
        EXT_IP_ADDR       => X"00000000", --: IP address[31:0]
        EXT_TCP_PORT      => X"0000", --: TCP port #[15:0]
        EXT_RBCP_PORT     => X"0000", --: RBCP port #[15:0]
        PHY_ADDR          => "00000", --: PHY-device MIF address[4:0]
        -- EEPROM
        EEPROM_CS         => EEP_CS, --: Chip select
        EEPROM_SK         => EEP_SK, --: Serial data clock
        EEPROM_DI         => EEP_DI, --: Serial write data
        EEPROM_DO         => EEP_DO, --: Serial read data
        --    user data, intialial values are stored in the EEPROM, 0xFFFF_FC3C-3F
        USR_REG_X3C       => open, --: Stored at 0xFFFF_FF3C
        USR_REG_X3D       => open, --: Stored at 0xFFFF_FF3D
        USR_REG_X3E       => open, --: Stored at 0xFFFF_FF3E
        USR_REG_X3F       => open, --: Stored at 0xFFFF_FF3F
        -- MII interface
        GMII_RSTn         => open, --: PHY reset
        GMII_1000M        => '1',  --: GMII mode (0:MII, 1:GMII)
        -- TX
        GMII_TX_CLK       => eth_tx_clk(i), --: Tx clock
        GMII_TX_EN        => eth_tx_en(i),  --: Tx enable
        GMII_TXD          => eth_tx_d(i),   --: Tx data[7:0]
        GMII_TX_ER        => eth_tx_er(i),  --: TX error
        -- RX
        GMII_RX_CLK       => eth_rx_clk(0), --: Rx clock
        GMII_RX_DV        => eth_rx_dv(i),  --: Rx data valid
        GMII_RXD          => eth_rx_d(i),   --: Rx data[7:0]
        GMII_RX_ER        => eth_rx_er(i),  --: Rx error
        GMII_CRS          => '0', --: Carrier sense
        GMII_COL          => '0', --: Collision detected
        -- Management IF
        GMII_MDC          => open, --: Clock for MDIO
        GMII_MDIO_IN      => '1', -- : Data
        GMII_MDIO_OUT     => open, --: Data
        GMII_MDIO_OE      => open, --: MDIO output enable
        -- User I/F
        SiTCP_RST         => emergency_reset, --: Reset for SiTCP and related circuits
        IP_ADDR           => sitcp_ip_addr(i),
        -- TCP connection control
        TCP_OPEN_REQ      => '0', -- : Reserved input, shoud be 0
        TCP_OPEN_ACK      => tcp_isActive(i), --: Acknowledge for open (=Socket busy)
        --    TCP_ERROR           : out    std_logic; --: TCP error, its active period is equal to MSL
        TCP_CLOSE_REQ     => close_req(i), --: Connection close request
        TCP_CLOSE_ACK     => close_act(i), -- : Acknowledge for closing
        -- FIFO I/F
        TCP_RX_WC         => X"0000",    --: Rx FIFO write count[15:0] (Unused bits should be set 1)
        TCP_RX_WR         => open, --: Read enable
        TCP_RX_DATA       => open, --: Read data[7:0]
        TCP_TX_FULL       => tcp_tx_full(i), --: Almost full flag
        TCP_TX_WR         => tcp_tx_wr(i),   -- : Write enable
        TCP_TX_DATA       => tcp_tx_data(i), -- : Write data[7:0]
        -- RBCP
        RBCP_ACT          => open, --: RBCP active
        RBCP_ADDR         => rbcp_gmii_addr(i), --: Address[31:0]
        RBCP_WD           => rbcp_gmii_wd(i),   --: Data[7:0]
        RBCP_WE           => rbcp_gmii_we(i),   --: Write enable
        RBCP_RE           => rbcp_gmii_re(i),   --: Read enable
        RBCP_ACK          => rbcp_gmii_ack(i),  --: Access acknowledge
        RBCP_RD           => rbcp_gmii_rd(i)    --: Read data[7:0]
        );

  u_RbcpCdc : entity mylib.RbcpCdc
  port map(
    -- Mikumari clock domain --
    rstSys      => system_reset or sitcp_reset,
    clkSys      => clk_sys,
    rbcpAddr    => rbcp_addr(i),
    rbcpWd      => rbcp_wd(i),
    rbcpWe      => rbcp_we(i),
    rbcpRe      => rbcp_re(i),
    rbcpAck     => rbcp_ack(i),
    rbcpRd      => rbcp_rd(i),

    -- GMII clock domain --
    rstXgmii    => pwr_on_reset or sitcp_reset,
    clkXgmii    => clk_link,
    rbcpXgAddr  => rbcp_gmii_addr(i),
    rbcpXgWd    => rbcp_gmii_wd(i),
    rbcpXgWe    => rbcp_gmii_we(i),
    rbcpXgRe    => rbcp_gmii_re(i),
    rbcpXgAck   => rbcp_gmii_ack(i),
    rbcpXgRd    => rbcp_gmii_rd(i)
    );

    u_gTCP_inst : entity mylib.global_sitcp_manager
      port map(
        RST           => pwr_on_reset or sitcp_reset,
        CLK           => clk_link,
        ACTIVE        => tcp_isActive(i),
        REQ           => close_req(i),
        ACT           => close_act(i),
        rstFromTCP    => open
        );
  end generate;

  -- SFP transceiver -------------------------------------------------------------------
  u_MiiRstTimer_Inst : entity mylib.MiiRstTimer
    port map(
      rst         => (not pcs_pma_status(kPcsPmaLinkStatus)),
      clk         => clk_link,
      rstMiiOut   => mii_reset
    );

  u_MiiInit_Inst : mii_initializer
    port map(
      -- System
      CLK         => clk_link,
      --RST         => system_reset,
      RST         => mii_reset,
      -- PHY
      PHYAD       => kMiiPhyad,
      -- MII
      MDC         => mii_init_mdc,
      MDIO_OUT    => mii_init_mdio,
      -- status
      COMPLETE    => open
      );

  mmcm_reset_all  <= or_reduce(mmcm_reset);

  u_GtClockDist_Inst : entity mylib.GtClockDistributer2
    port map(
      -- GTX refclk --
      GT_REFCLK_P   => GTX_REFCLK_P,
      GT_REFCLK_N   => GTX_REFCLK_N,

      gtRefClk      => gtrefclk_i,
      gtRefClkBufg  => gtrefclk_bufg,

      -- USERCLK2 --
      mmcmReset     => mmcm_reset_all,
      mmcmLocked    => mmcm_locked,
      txOutClk      => txout_clk(0),
      rxOutClk      => rxout_clk(0),

      userClk       => user_clk,
      userClk2      => user_clk2,
      rxuserClk     => rxuser_clk,
      rxuserClk2    => rxuser_clk2,

      -- GTXE_COMMON --
      reset         => pwr_on_reset,
      clkIndep      => clk_indep,
      clkQPLL       => gt0_qplloutclk,
      refclkQPLL    => gt0_qplloutrefclk
      );

  gen_pcspma : for i in 0 to kNumGtx-1 generate
    u_pcspma_Inst : entity mylib.GbEPcsPma
      port map(

        --An independent clock source used as the reference clock for an
        --IDELAYCTRL (if present) and for the main GT transceiver reset logic.
        --This example design assumes that this is of frequency 200MHz.
        independent_clock    => clk_indep,

        -- Tranceiver Interface
        -----------------------
        gtrefclk             => gtrefclk_i,
        gtrefclk_bufg        => gtrefclk_bufg,

        gt0_qplloutclk       => gt0_qplloutclk,
        gt0_qplloutrefclk    => gt0_qplloutrefclk,

        userclk              => user_clk,
        userclk2             => user_clk2,
        rxuserclk            => rxuser_clk,
        rxuserclk2           => rxuser_clk2,

        mmcm_locked          => mmcm_locked,
        mmcm_reset           => mmcm_reset(i),

        -- clockout --
        txoutclk             => txout_clk(i),
        rxoutclk             => rxout_clk(i),

        -- Tranceiver Interface
        -----------------------
        txp                  => GTX_TX_P(i),
        txn                  => GTX_TX_N(i),
        rxp                  => GTX_RX_P(i),
        rxn                  => GTX_RX_N(i),

        -- GMII Interface (client MAC <=> PCS)
        --------------------------------------
        gmii_tx_clk          => eth_tx_clk(i),
        gmii_rx_clk          => eth_rx_clk(i),
        gmii_txd             => eth_tx_d(i),
        gmii_tx_en           => eth_tx_en(i),
        gmii_tx_er           => eth_tx_er(i),
        gmii_rxd             => eth_rx_d(i),
        gmii_rx_dv           => eth_rx_dv(i),
        gmii_rx_er           => eth_rx_er(i),
        -- Management: MDIO Interface
        -----------------------------

        mdc                  => mii_init_mdc,
        mdio_i               => mii_init_mdio,
        mdio_o               => open,
        mdio_t               => open,
        phyaddr              => "00000",
        configuration_vector => "00000",
        configuration_valid  => '0',

        -- General IO's
        ---------------
        status_vector        => pcs_pma_status,
        reset                => pwr_on_reset
        );
  end generate;


  -- Clock inst ------------------------------------------------------------------------
  u_ClkSys_Inst : clk_wiz_sys
    port map
     (-- Clock in ports
      -- Clock out ports
      clk_link          => clk_link,
      clk_indep         => clk_indep,
      clk_spi           => clk_spi,
      clk_10MHz         => clk_10MHz,
      -- Status and control signals
      reset             => '0',
      locked            => clk_locked_sys,
      clk_in1_p         => BASE_CLKP,
      clk_in1_n         => BASE_CLKN
     );

  u_ClkCdcm_Inst : clk_wiz_cdcm
   port map
    (-- Clock in ports
     -- Clock out ports
     clk_sys           => clk_sys,
     clk_tdc0          => clk_tdc(0),
     clk_tdc1          => clk_tdc(1),
     clk_tdc2          => clk_tdc(2),
     clk_tdc3          => clk_tdc(3),
     -- Status and control signals
     reset             => (not clk_locked_sys),
     locked            => clk_locked_cdcm,
     clk_in1           => clk_link
    );

  u_BUFG :  BUFG
    port map (
      O => gmod_clk, -- 1-bit output: Clock output
      I => mod_clk  -- 1-bit input: Clock input
    );

  u_ClkMiku_Inst : mmcm_mikumari
    port map
     (-- Clock in ports
      clk_in2           => gmod_clk,
      clk_in_sel        => dip_sw(kStandAlone.Index),
      -- Clock out ports
      clk_slow          => clk_slow,
      clk_fast          => clk_fast,
      -- Status and control signals
      reset             => (not clk_locked_sys),
      locked            => clk_locked_miku,
      clk_in1           => clk_link
     );

  u_ClkDivision : entity mylib.ClkDivision
    port map(
      rst         => system_reset,
      clk         => clk_10MHz,

      -- module output --
      clk1MHz     => clk_1MHz,
      clk100kHz   => clk_100kHz,
      clk10kHz    => clk_10kHz,
      clk1kHz     => clk_1kHz
      );


end Behavioral;
