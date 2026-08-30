library ieee, mylib;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use mylib.defBCT.all;
use mylib.defTopLevel.all;
use mylib.defTdcBlock.all;

package defMTDC is
  constant kNumTdcBlock          : positive:= 2;
  type arrayInput is array(kNumTdcBlock/2-1 downto 0) of std_logic_vector(kNumInput-1 downto 0);

  constant kMagicWordLeading  : std_logic_vector(kNumBitMagicWord-1 downto 0):= X"cc";
  constant kMagicWordTrailing : std_logic_vector(kNumBitMagicWord-1 downto 0):= X"cd";

  type TdcEventIdArray is array(integer range kNumTdcBlock-1 downto 0)
   of std_logic_vector(kWidthTdcEventId-1 downto 0);

  -- Self trigger ---------------------------------------------------------
  constant kWidthSelfHitThreshold : positive := 6;
  constant kSelfLatchWindowMax    : positive := 15;
  constant kWidthSelfLatchWindow  : positive := 4;

  constant kNumSelfGeoMax         : positive := 16;
  constant kWidthSelfGeoCount     : positive := 5;

  subtype HitVector is std_logic_vector(kNumInputBlock-1 downto 0);
  type SelfGeoMaskArray is array(0 to kNumSelfGeoMax-1) of HitVector;

  subtype LatchCountType is unsigned(kWidthSelfLatchWindow-1 downto 0);
  type LatchCountArray is array(0 to kNumInputBlock-1) of LatchCountType;

--  type typeInitCh is array(kNumTdcBlock/2 -1 downto 0) of integer;
--  constant kInitialCh : typeInitCh := (0);

  -- Local Address --------------------------------------------------------
  constant kEnBlock         : LocalAddressType := x"000"; -- W/R, [1:0] Enable blocks
  constant kOfsPtr          : LocalAddressType := x"010"; -- W/R, [10:0], pointer offset of the read pointer for ring buffer
  constant kWinMax          : LocalAddressType := x"020"; -- W/R, [10:0], Max coarse counter
  constant kWinMin          : LocalAddressType := x"030"; -- W/R, [10:0], Min coarse counter
  constant kSelfHitThreshold : LocalAddressType := x"040"; -- W/R, [5:0], Hit Threshold
  constant kSelfHitLatchWin  : LocalAddressType := x"050"; -- W/R, [3:0], Hit latch window
  constant kSelfGeoCount     : LocalAddressType := x"060"; -- W/R, [4:0],
  constant kSelfGeoMaskBase  : LocalAddressType := x"100"; -- W/R,

  type regMTDC is record
    tdc            : regTdc;
    hit_threshold  : std_logic_vector(kWidthSelfHitThreshold-1 downto 0);
    latch_window   : std_logic_vector(kWidthSelfLatchWindow-1 downto 0);
    geometry_count : std_logic_vector(kWidthSelfGeoCount-1 downto 0);
    geometry_mask  : SelfGeoMaskArray;
  end record;

end package defMTDC;
