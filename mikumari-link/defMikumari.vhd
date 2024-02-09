library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;

library mylib;
use mylib.defCDCM.all;

package defMikumari is

  -- K-type characters --
  -- For CDCM-10-1.5 --
  constant kMikuInitK1_1P5      : CbtUDataType:= B"0101_1101";
  constant kMikuInitK2_1P5      : CbtUDataType:= B"0101_1011";
  -- For CDCM-10-2.5 --
  constant kMikuInitK1_2P5      : CbtUDataType:= B"1000_1011";
  constant kMikuInitK2_2P5      : CbtUDataType:= B"1000_1110";

  constant kMikumariFsk         : CbtUDataType:= B"1111_0010";
  constant kMikumariFek         : CbtUDataType:= B"1111_0001";

  function GetInitK1(payload_width: integer) return CbtUDataType;
  function GetInitK2(payload_width: integer) return CbtUDataType;

  -- Back channel --
  type MikumariBackChannelType is (
    WaitCbtUp, SendInitK1, SendInitK2, MikumariRxUp
  );

  -- Mikumari Pulse --
  subtype  MikumariPulseType        is std_logic_vector(2 downto 0);
  subtype  EncodedPulseType         is std_logic_vector(3 downto 0);
  constant kIsPulseIndex          : integer:= MikumariPulseType'high +1;
  constant kWidthPulseCount       : integer:= 4;
  constant kWidthPulseSr          : integer:= 10;

  -- Check sum --
  constant kWidthCheckSum         : integer:= 8;

  -- Mikumari TX --
  constant kNumTxFlag         : integer:= 11;
  subtype flagId is integer range 0 to kNumTxFlag-1;
  type flagRecord is record
    index : flagId;
  end record;

  constant kUserDataTx    : flagRecord := (index => 0);
  constant kLastData      : flagRecord := (index => 1);
  constant kPulseReserve  : flagRecord := (index => 2);
  constant kPulseTx       : flagRecord := (index => 3);
  constant kInitMikuTx    : flagRecord := (index => 4);
  constant kCsReserve     : flagRecord := (index => 5);
  constant kCheckSumTx    : flagRecord := (index => 6);
  constant kFekReserve    : flagRecord := (index => 7);
  constant kFekTx         : flagRecord := (index => 8);
  constant kFskReserve    : flagRecord := (index => 9);
  constant kFskTx         : flagRecord := (index => 10);

  function isBusyTx(tx_flag : std_logic_vector(kNumTxFlag-1 downto 0)) return std_logic;
  function isBusyIFBuf(tx_flag : std_logic_vector(kNumTxFlag-1 downto 0)) return std_logic;
  function encodePulseType(pulse_type : MikumariPulseType) return EncodedPulseType;

  constant kWidthLinkDelay  : integer:= 64;

  -- Mikumari RX --
  function isPulseChar(cbt_data : CbtUDataType; is_ktype  : std_logic) return std_logic;
  function decodePulseType(cbt_data : CbtUDataType) return std_logic_vector;

  -- High-precision pulse mode --
  subtype  MikumariHpmRegType       is std_logic_vector(3 downto 0);
  subtype  EncodedHpmPulseType      is std_logic_vector(5 downto 0);
  constant kWidthPulseReg  : integer:= 4;

  subtype  HpmPulseMessageType      is std_logic_vector(kWidthPulseCount+kWidthPulseReg-1 downto 0);
  constant kPosPulseCount   : std_logic_vector(7 downto 4):= X"0";
  constant kPosPulseReg     : std_logic_vector(3 downto 0):= X"0";

  function encodePulseTypeHPM(pulse_type : MikumariPulseType; rd_flag : std_logic) return std_logic_vector;
  function decodePulseTypeHPM_RDM(cbt_data : CbtUDataType) return std_logic_vector;
  function decodePulseTypeHPM_RDP(cbt_data : CbtUDataType) return std_logic_vector;

  function encode3b4b(data_in : std_logic_vector; rd_flag : std_logic) return std_logic_vector;
  function decode3b4b_RDM(data_in : std_logic_vector) return std_logic_vector;
  function decode3b4b_RDP(data_in : std_logic_vector) return std_logic_vector;

  function encode5b6b(data_in : std_logic_vector; rd_flag : std_logic) return std_logic_vector;
  function decode5b6b_RDM(data_in : std_logic_vector) return std_logic_vector;
  function decode5b6b_RDP(data_in : std_logic_vector) return std_logic_vector;

  -- Scrambler/Descrambler --
  type SetSeedType is
     (
      WaitLinkUp, SendFirstFsk, WaitFirstFsk, SetSeed, SeedIsSet
    );


end package defMikumari;
-- ----------------------------------------------------------------------------------
-- Package body
-- ----------------------------------------------------------------------------------
package body defMikumari is
  -- Mikumari TX --------------------------------------------------------------------
  function isBusyTx(tx_flag : std_logic_vector(kNumTxFlag-1 downto 0)) return std_logic is
    variable result   : std_logic;
  begin
    result  := or_reduce(tx_flag(kFskTx.index downto kPulseTx.Index));
    --result  := or_reduce(tx_flag(kFekTx.index downto kLastData.index));
    --result  := or_reduce(tx_flag(kFskTx.index downto kLastData.index));

    return result;

  end isBusyTx;

  function isBusyIFBuf(tx_flag : std_logic_vector(kNumTxFlag-1 downto 0)) return std_logic is
    variable result   : std_logic;
  begin
    --result  := or_reduce(tx_flag(kCheckSumTx.index downto kLastData.index));
    result  := or_reduce(tx_flag(kFekTx.index downto kLastData.index));

    return result;

  end isBusyIFBuf;

  -- Low latency mode -----------------------------------------------------------------------
  function encodePulseType(pulse_type : MikumariPulseType) return EncodedPulseType is
  begin
    case pulse_type is
      when "000" => return "1010";
      when "001" => return "1110";
      when "010" => return "1011";
      when "011" => return "1101";
      when "100" => return "0111";
      when "101" => return "1001";
      when "110" => return "0110";
      when "111" => return "1100";
      when others => return "1001";
    end case;
  end encodePulseType;

  -- Mikumari RX --------------------------------------------------------------------
  function isPulseChar(cbt_data : CbtUDataType; is_ktype : std_logic) return std_logic is
  begin
    if(is_ktype = '1') then
      case cbt_data(CbtUDataType'left downto 4) is
        when "1010" => return '1';
        when "1110" => return '1';
        when "1011" => return '1';
        when "1101" => return '1';
        when "0111" => return '1';
        when "1001" => return '1';
        when "0110" => return '1';
        when "1100" => return '1';
        when others => return '0';
      end case;
    else
      return '0';
    end if;
  end isPulseChar;

  function decodePulseType(cbt_data : CbtUDataType) return std_logic_vector is
  begin
    case cbt_data(CbtUDataType'left downto 4) is
      when "1010" => return "1000";
      when "1110" => return "1001";
      when "1011" => return "1010";
      when "1101" => return "1011";
      when "0111" => return "1100";
      when "1001" => return "1101";
      when "0110" => return "1110";
      when "1100" => return "1111";
      when others => return "0000";
    end case;
  end decodePulseType;

  -- High precision mode --------------------------------------------------------------------
  -- Pulse Type (3b6b) --
  function encodePulseTypeHPM(pulse_type : MikumariPulseType; rd_flag : std_logic)
  return std_logic_vector is
  begin
    if(rd_flag = '0') then
      -- RD minus --
      -- But # of high-bits is larger than low-bits. --
      case pulse_type is
        when "000" =>  return "101111";
        when "001" =>  return "110011";
        when "010" =>  return "101101";
        when "011" =>  return "100111";
        when "100" =>  return "011110";
        when "101" =>  return "001111";
        when "110" =>  return "011011";
        when "111" =>  return "110111";
        when others => return "001100";
      end case;
    else
      -- RD plus --
      -- But # of high-bits is smaller than low-bits. --
      case pulse_type is
        when "000" =>  return "010011";
        when "001" =>  return "110011";
        when "010" =>  return "101101";
        when "011" =>  return "100111";
        when "100" =>  return "011110";
        when "101" =>  return "001111";
        when "110" =>  return "011011";
        when "111" =>  return "001011";
        when others => return "001100";
      end case;
    end if;
  end encodePulseTypeHPM;

  function decodePulseTypeHPM_RDM(cbt_data : CbtUDataType) return std_logic_vector is
  begin
    case cbt_data(CbtUDataType'left downto 2) is
      when "101111" => return "1000";
      when "110011" => return "1001";
      when "101101" => return "1010";
      when "100111" => return "1011";
      when "011110" => return "1100";
      when "001111" => return "1101";
      when "011011" => return "1110";
      when "110111" => return "1111";
      when others   => return "0000"; -- RD seems to be plus --
    end case;
  end decodePulseTypeHPM_RDM;

  function decodePulseTypeHPM_RDP(cbt_data : CbtUDataType) return std_logic_vector is
  begin
    case cbt_data(CbtUDataType'left downto 2) is
      when "010011" => return "1000";
      when "110011" => return "1001";
      when "101101" => return "1010";
      when "100111" => return "1011";
      when "011110" => return "1100";
      when "001111" => return "1101";
      when "011011" => return "1110";
      when "001011" => return "1111";
      when others   => return "0000"; -- RD seems to be minus --
    end case;
  end decodePulseTypeHPM_RDP;

  -- Data (3b4b) --
  function encode3b4b(data_in : std_logic_vector; rd_flag : std_logic) return std_logic_vector is
  begin
    if(rd_flag = '0') then
      -- RD minus --
      case data_in is
        when "000" =>  return "0100";
        when "001" =>  return "1001";
        when "010" =>  return "1100";
        when "011" =>  return "0011";
        when "100" =>  return "0010";
        when "101" =>  return "1000";
        when "110" =>  return "0110";
        when "111" =>  return "0001";
        when others => return "0000";
      end case;
    else
      -- RD plus --
      -- But # of high-bits is smaller than low-bits. --
      case data_in is
        when "000" =>  return "1011";
        when "001" =>  return "1001";
        when "010" =>  return "1100";
        when "011" =>  return "0011";
        when "100" =>  return "1101";
        when "101" =>  return "0111";
        when "110" =>  return "0110";
        when "111" =>  return "1110";
        when others => return "0000";
      end case;
    end if;
  end encode3b4b;

  function decode3b4b_RDM(data_in : std_logic_vector) return std_logic_vector is
  begin
    case data_in is
      when "0100" => return "1000";
      when "1001" => return "1001";
      when "1100" => return "1010";
      when "0011" => return "1011";
      when "0010" => return "1100";
      when "1000" => return "1101";
      when "0110" => return "1110";
      when "0001" => return "1111";
      when others => return "0000"; -- RD seems to be plus --
    end case;
  end decode3b4b_RDM;

  function decode3b4b_RDP(data_in : std_logic_vector) return std_logic_vector is
  begin
    case data_in is
      when "1011" => return "1000";
      when "1001" => return "1001";
      when "1100" => return "1010";
      when "0011" => return "1011";
      when "1101" => return "1100";
      when "0111" => return "1101";
      when "0110" => return "1110";
      when "1110" => return "1111";
      when others => return "0000"; -- RD seems to be minus --
    end case;
  end decode3b4b_RDP;

  -- Data (5b6b) --
  function encode5b6b(data_in : std_logic_vector; rd_flag : std_logic) return std_logic_vector is
  begin
    if(rd_flag = '0') then
      -- RD minus --
      case data_in is
        when "00000" =>  return "100111";
        when "00001" =>  return "011101";
        when "00010" =>  return "101101";
        when "00011" =>  return "110001";
        when "00100" =>  return "110101";
        when "00101" =>  return "101001";
        when "00110" =>  return "011001";
        when "00111" =>  return "111000";
        --
        when "01000" =>  return "111001";
        when "01001" =>  return "100101";
        when "01010" =>  return "101000";
        when "01011" =>  return "110100";
        when "01100" =>  return "001101";
        when "01101" =>  return "101100";
        when "01110" =>  return "011100";
        when "01111" =>  return "010111";
        --
        when "10000" =>  return "011011";
        when "10001" =>  return "100011";
        when "10010" =>  return "010011";
        when "10011" =>  return "110010";
        when "10100" =>  return "001011";
        when "10101" =>  return "000111";
        when "10110" =>  return "011010";
        when "10111" =>  return "111010";
        --
        when "11000" =>  return "110011";
        when "11001" =>  return "100110";
        when "11010" =>  return "010110";
        when "11011" =>  return "110110";
        when "11100" =>  return "001110";
        when "11101" =>  return "101110";
        when "11110" =>  return "011110";
        when "11111" =>  return "101011";
        when others  =>  return "000000";
      end case;
    else
      -- RD plus --
      -- But # of high-bits is smaller than low-bits. --
      case data_in is
        when "00000" =>  return "011000";
        when "00001" =>  return "100010";
        when "00010" =>  return "010010";
        when "00011" =>  return "110001";
        when "00100" =>  return "001010";
        when "00101" =>  return "101001";
        when "00110" =>  return "011001";
        when "00111" =>  return "111000";
        --
        when "01000" =>  return "000110";
        when "01001" =>  return "100101";
        when "01010" =>  return "010111";
        when "01011" =>  return "110100";
        when "01100" =>  return "001101";
        when "01101" =>  return "101100";
        when "01110" =>  return "011100";
        when "01111" =>  return "101000";
        --
        when "10000" =>  return "100100";
        when "10001" =>  return "100011";
        when "10010" =>  return "010011";
        when "10011" =>  return "110010";
        when "10100" =>  return "001011";
        when "10101" =>  return "000111";
        when "10110" =>  return "011010";
        when "10111" =>  return "000101";
        --
        when "11000" =>  return "001100";
        when "11001" =>  return "100110";
        when "11010" =>  return "010110";
        when "11011" =>  return "001001";
        when "11100" =>  return "001110";
        when "11101" =>  return "010001";
        when "11110" =>  return "100001";
        when "11111" =>  return "010100";
        when others  =>  return "000000";
      end case;
    end if;
  end encode5b6b;

  function decode5b6b_RDM(data_in : std_logic_vector) return std_logic_vector is
  begin
    case data_in is
      when "100111" =>  return "100000";
      when "011101" =>  return "100001";
      when "101101" =>  return "100010";
      when "110001" =>  return "100011";
      when "110101" =>  return "100100";
      when "101001" =>  return "100101";
      when "011001" =>  return "100110";
      when "111000" =>  return "100111";
      --
      when "111001" =>  return "101000";
      when "100101" =>  return "101001";
      when "101000" =>  return "101010";
      when "110100" =>  return "101011";
      when "001101" =>  return "101100";
      when "101100" =>  return "101101";
      when "011100" =>  return "101110";
      when "010111" =>  return "101111";
      --
      when "011011" =>  return "110000";
      when "100011" =>  return "110001";
      when "010011" =>  return "110010";
      when "110010" =>  return "110011";
      when "001011" =>  return "110100";
      when "000111" =>  return "110101";
      when "011010" =>  return "110110";
      when "111010" =>  return "110111";
      --
      when "110011" =>  return "111000";
      when "100110" =>  return "111001";
      when "010110" =>  return "111010";
      when "110110" =>  return "111011";
      when "001110" =>  return "111100";
      when "101110" =>  return "111101";
      when "011110" =>  return "111110";
      when "101011" =>  return "111111";
      when others   =>  return "000000"; -- RD seems to be plus --
    end case;
  end decode5b6b_RDM;

  function decode5b6b_RDP(data_in : std_logic_vector) return std_logic_vector is
  begin
    case data_in is
      when "011000" =>  return "100000";
      when "100010" =>  return "100001";
      when "010010" =>  return "100010";
      when "110001" =>  return "100011";
      when "001010" =>  return "100100";
      when "101001" =>  return "100101";
      when "011001" =>  return "100110";
      when "111000" =>  return "100111";
      --
      when "000110" =>  return "101000";
      when "100101" =>  return "101001";
      when "010111" =>  return "101010";
      when "110100" =>  return "101011";
      when "001101" =>  return "101100";
      when "101100" =>  return "101101";
      when "011100" =>  return "101110";
      when "101000" =>  return "101111";
      --
      when "100100" =>  return "110000";
      when "100011" =>  return "110001";
      when "010011" =>  return "110010";
      when "110010" =>  return "110011";
      when "001011" =>  return "110100";
      when "000111" =>  return "110101";
      when "011010" =>  return "110110";
      when "000101" =>  return "110111";
      --
      when "001100" =>  return "111000";
      when "100110" =>  return "111001";
      when "010110" =>  return "111010";
      when "001001" =>  return "111011";
      when "001110" =>  return "111100";
      when "010001" =>  return "111101";
      when "100001" =>  return "111110";
      when "010100" =>  return "111111";
      when others   => return  "000000"; -- RD seems to be minus --
    end case;
  end decode5b6b_RDP;


  -- CBT K-char selector -------------------------------------------------------------
  function GetInitK1(payload_width: integer) return CbtUDataType is
  begin
    case payload_width is
      when 1      =>  return(kMikuInitK1_1P5);
      when 2      =>  return(kMikuInitK1_2P5);
      when others =>  return(kMikuInitK1_1P5);
    end case;
  end GetInitK1;

  function GetInitK2(payload_width: integer) return CbtUDataType is
  begin
    case payload_width is
      when 1      =>  return(kMikuInitK2_1P5);
      when 2      =>  return(kMikuInitK2_2P5);
      when others =>  return(kMikuInitK2_1P5);
    end case;
  end GetInitK2;



end package body defMikumari;
