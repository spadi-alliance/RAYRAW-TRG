library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library mylib;
use mylib.defYaenamiAdc.all;
use mylib.defRayrawAdcROV1.all;
use mylib.defBCT.all;

package defAdcBlock is
  constant kNumAdcInputBlock  : positive:= kNumAsicBlock*kNumAdcCh; -- 32: 4*8
  constant kWidthCoarseCount  : positive:= 11;
  constant kWidthAdcSampleId  : positive:= 16;
  constant kWidthAdcEventId   : positive:= 10;

  -- Hit buffer --
  type HitBuildProcessType is (
    WaitLeading, WaitTrailing
  );

  type HitBuildStateArray is array(0 to kNumAdcInputBlock-1) of HitBuildProcessType;

  type HitSampleArray is array(0 to kNumAdcInputBlock-1)
   of std_logic_vector(kWidthAdcSampleId-1 downto 0);

  type HitIntervalArray is array(0 to kNumAdcInputBlock-1)
   of std_logic_vector(2*kWidthAdcSampleId-1 downto 0);

  -- hit delay --
  constant kDelayTdcHit         : positive:= 10;
  constant kWidthTimeoutSamples : positive:= 8;
  constant kHitTimeoutSamples   : positive := 200;

  type TdcHitDelayArray is array(0 to kDelayTdcHit-1)
    of std_logic_vector(kNumAdcInputBlock-1 downto 0);

  -- hit delay --
  constant kDelayTdcHit       : positive:= 10;

  type TdcHitDelayArray is array(0 to kDelayTdcHit-1)
    of std_logic_vector(kNumAdcInputBlock-1 downto 0);

  -- channel buffer --
  constant kWidthAdcChDataCount  : positive:= 12;
  constant kMaxAdcChDepth        : positive:= 4096;
  constant kMaxAdcChThreshold    : positive:= 10;
  type chAdcDcountArray is array (integer range kNumAdcInputBlock-1 downto 0)
    of std_logic_vector(kWidthAdcChDataCount-1 downto 0);

  type chAdcReservedDcountArray is array (integer range kNumAdcInputBlock-1 downto 0)
    of unsigned(kWidthAdcChDataCount-1 downto 0);

  -- block buffer
  constant kWidthAdcData      : positive:= kWidthCoarseCount + kNumAdcBit; -- 11+10
  constant kWidthDataBit      : positive:= 1;
  constant kWidthAdcChData    : positive:= kWidthDataBit + kWidthAdcData;
  type chAdcDataArray is array (integer range kNumAdcInputBlock-1 downto 0)
    of std_logic_vector(kWidthAdcChData-1 downto 0); -- 1+11+10

  -- Hit search sequence --
  type HitSearchProcessType is (
    Init,
    WaitCommonStop, ReadRingBuffer, LastWord, Finalize,
    Done
    );

  constant kIndexAdcDataBit   : positive:= kWidthAdcChData-1;
  constant isData             : std_logic:= '1';
  constant isSeparator        : std_logic:= '0';
  constant kWidthLastCount    : positive:= 3;


  -- Event build sequence --
  type BuildProcessType is (
    Init,
    WaitDready, DreadyInterval, StartPosition, ReadInterval, ReadOneChannel, EndOneChannel,
    Finalize,
    Done
    );

  constant kWidthAdcNWord     : positive:= 18;
  constant kWidthAdcChIndex   : positive:= 5;
  constant kWidthAdcChannel   : positive:= 5;

  -- Control register --
  type regAdc is record
    --enable_block    : std_logic; -- enable this block
    offset_ptr     : std_logic_vector(kWidthCoarseCount-1 downto 0); -- 2047 - window_max +2
    window_max     : std_logic_vector(kWidthCoarseCount-1 downto 0);
    window_min     : std_logic_vector(kWidthCoarseCount-1 downto 0);
    enable_zerosup : std_logic;
    hit_timeout    : std_logic_vector(kWidthTimeoutSamples-1 downto 0);
  end record;

  -- Local Address --------------------------------------------------------
  constant kOfsPtr          : LocalAddressType := x"000"; -- W/R, [10:0], pointer offset of the read pointer for ring buffer
  constant kWinMax          : LocalAddressType := x"010"; -- W/R, [10:0], Max coarse counter
  constant kWinMin          : LocalAddressType := x"020"; -- W/R, [10:0], Min coarse counter
  constant kAdcRoReset      : LocalAddressType := x"030"; -- W/R, [0:0], Reset to AdcRo (default is HIGH)
  constant kIsReady         : LocalAddressType := x"040"; -- R,   [3:0], AdcRo IsReady signals
  constant kEnZeroSup       : LocalAddressType := x"050"; -- W/R, [0:0], Zero Suppression Enable
  constant kHitTimeout      : LocalAddressType := x"060"; -- W/R, [7:0], Hit Time out

  -- Region of interest ---------------------------------------------------
  constant kRoiPre          : positive:= 20; -- -> change into register [4:0]
  constant kRoiPost         : positive:= 80; -- -> change into register [6:0]
  constant kWidthRoiCount   : positive:= 8;

  type AdcDelayArray is array(0 to kRoiPre) of chAdcDataArray;

  type RoiCountArray is array(0 to kNumAdcInputBlock-1)
    of unsigned(kWidthRoiCount-1 downto 0);

end package defAdcBlock;
