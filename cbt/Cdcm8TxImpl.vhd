library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

Library UNISIM;
use UNISIM.vcomponents.all;

library UNIMACRO;
use UNIMACRO.Vcomponents.all;
--

entity Cdcm8TxImpl is
  generic
  (
    kSysW        : integer:= 1;  -- width of the ata for the system
    kDevW        : integer:= 8; -- width of the ata for the device
    kIoStandard  : string:= "LVDS" -- IOSTANDARD of OBUFDS
  );
  port
  (
    -- From the device to the system
    dInFromDevice   : in std_logic_vector(kDevW-1 downto 0);
    dOutToPinP      : out std_logic;
    dOutToPinN      : out std_logic;
    -- Clock and reset
    clkIn           : in std_logic;
    clkDivIn        : in std_logic;
    ioReset         : in std_logic
  );
end Cdcm8TxImpl;

architecture RTL of Cdcm8TxImpl is
  constant kMaxBit  : integer:= 14;
  signal din_oserdes  : std_logic_vector(kMaxBit-1 downto 0);
  signal ocascade_sm_d, ocascade_sm_t : std_logic;

  signal  data_out_to_pin   : std_logic;

  -- Feedback -------------------------------------------------------
  signal clk_in, clk_in_inv   : std_logic;
  signal feedback_out : std_logic;
  signal iserdes_q    : std_logic_vector(13 downto 0);
  signal rx_output    : std_logic_vector(dInFromDevice'range);

  attribute mark_debug  : string;
  attribute mark_debug of rx_output : signal is "true";
  attribute mark_debug of din_oserdes : signal is "true";

begin

  u_Tx_OBUFDS_inst : OBUFDS
    generic map
    (
      IOSTANDARD => kIoStandard, -- Specify the output I/O standard
      SLEW       => "FAST"     -- Specify the output slew rate
    )
    port map
    (
      O  => dOutToPinP,      -- Diff_p output (connect directly to top-level port)
      OB => dOutToPinN,      -- Diff_n output (connect directly to top-level port)
      I  => data_out_to_pin  -- Buffer input
    );



  u_OSERDESE2_master : OSERDESE2
    generic map (
       DATA_RATE_OQ => "DDR",    -- DDR, SDR
       DATA_RATE_TQ => "SDR",    -- DDR, BUF, SDR
       DATA_WIDTH   => kDevW,    -- Parallel data width (2-8,10,14)
       SERDES_MODE  => "MASTER", -- MASTER, SLAVE
       TRISTATE_WIDTH => 1       -- 3-state converter width (1,4)
    )
    port map (
       OFB => feedback_out,             -- 1-bit output: Feedback path for data
       OQ => data_out_to_pin,               -- 1-bit output: Data path output
       -- SHIFTOUT1 / SHIFTOUT2: 1-bit (each) output: Data output expansion (1-bit each)
       SHIFTOUT1 => open,
       SHIFTOUT2 => open,
       TBYTEOUT => open,   -- 1-bit output: Byte group tristate
       TFB => open,             -- 1-bit output: 3-state control
       TQ => open,               -- 1-bit output: 3-state control
       CLK => clkIn,             -- 1-bit input: High speed clock
       CLKDIV => clkDivIn,       -- 1-bit input: Divided clock
       -- D1 - D8: 1-bit (each) input: Parallel data inputs (1-bit each)
       D1 => din_oserdes(13),
       D2 => din_oserdes(12),
       D3 => din_oserdes(11),
       D4 => din_oserdes(10),
       D5 => din_oserdes(9),
       D6 => din_oserdes(8),
       D7 => din_oserdes(7),
       D8 => din_oserdes(6),
       OCE => '1',             -- 1-bit input: Output data clock enable
       RST => ioReset,             -- 1-bit input: Reset
       -- SHIFTIN1 / SHIFTIN2: 1-bit (each) input: Data input expansion (1-bit each)
       SHIFTIN1 => '0',
       SHIFTIN2 => '0',
       -- T1 - T4: 1-bit (each) input: Parallel 3-state inputs
       T1 => '0',
       T2 => '0',
       T3 => '0',
       T4 => '0',
       TBYTEIN => '0',     -- 1-bit input: Byte group tristate
       TCE => '0'              -- 1-bit input: 3-state clock enable
    );


  u_swap : for i in 0 to kDevW-1 generate
  begin
    din_oserdes(kMaxBit-i-1)     <= dInFromDevice(i);
    rx_output(i)   <= iserdes_q(kDevW-i-1);
  end generate;
  din_oserdes(kMaxBit-kDevW-1 downto 0)  <= (others => '0');

  -- Feedback ISERDES --------------------------------------------------------
  clk_in      <= clkIn;
  clk_in_inv  <= not clkIn;

  u_ISERDESE2_FB : ISERDESE2
    generic map (
       DATA_RATE          => "DDR",         -- DDR, SDR
       DATA_WIDTH         => kDevW,         -- Parallel data width (2-8,10,14)
       DYN_CLKDIV_INV_EN  => "FALSE",       -- Enable DYNCLKDIVINVSEL inversion (FALSE, TRUE)
       DYN_CLK_INV_EN     => "FALSE",       -- Enable DYNCLKINVSEL inversion (FALSE, TRUE)
       INTERFACE_TYPE     => "NETWORKING",  -- MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
       IOBDELAY           => "NONE",         -- NONE, BOTH, IBUF, IFD
       NUM_CE             => 2,             -- Number of clock enables (1,2)
       OFB_USED           => "TRUE",       -- Select OFB path (FALSE, TRUE)
       SERDES_MODE        => "MASTER"       -- MASTER, SLAVE
    )
    port map (
       O => open,                       -- 1-bit output: Combinatorial output
       -- Q1 - Q8: 1-bit (each) output: Registered data outputs
       Q1 => iserdes_q(0),
       Q2 => iserdes_q(1),
       Q3 => iserdes_q(2),
       Q4 => iserdes_q(3),
       Q5 => iserdes_q(4),
       Q6 => iserdes_q(5),
       Q7 => iserdes_q(6),
       Q8 => iserdes_q(7),
       -- SHIFTOUT1, SHIFTOUT2: 1-bit (each) output: Data width expansion output ports
       SHIFTOUT1 => open,
       SHIFTOUT2 => open,
       BITSLIP => '0',           -- 1-bit input: The BITSLIP pin performs a Bitslip operation synchronous to
                                     -- CLKDIV when asserted (active High). Subsequently, the data seen on the
                                     -- Q1 to Q8 output ports will shift, as in a barrel-shifter operation, one
                                     -- position every time Bitslip is invoked (DDR operation is different from
                                     -- SDR).

       -- CE1, CE2: 1-bit (each) input: Data register clock enable inputs
       CE1 => '1',
       CE2 => '1',
       CLKDIVP => '0',           -- 1-bit input: TBD
       -- Clocks: 1-bit (each) input: ISERDESE2 clock input ports
       CLK => clk_in,                   -- 1-bit input: High-speed clock
       CLKB => clk_in_inv,                 -- 1-bit input: High-speed secondary clock
       CLKDIV => clkDivIn,             -- 1-bit input: Divided clock
       OCLK => '0',                 -- 1-bit input: High speed output clock used when INTERFACE_TYPE="MEMORY"
       -- Dynamic Clock Inversions: 1-bit (each) input: Dynamic clock inversion pins to switch clock polarity
       DYNCLKDIVSEL => '0', -- 1-bit input: Dynamic CLKDIV inversion
       DYNCLKSEL => '0',       -- 1-bit input: Dynamic CLK/CLKB inversion
       -- Input Data: 1-bit (each) input: ISERDESE2 data input ports
       D => '0',                       -- 1-bit input: Data input
       DDLY => '0',                 -- 1-bit input: Serial data from IDELAYE2
       OFB => feedback_out,                   -- 1-bit input: Data feedback from OSERDESE2
       OCLKB => '0',               -- 1-bit input: High speed negative edge output clock
       RST => ioReset,                   -- 1-bit input: Active high asynchronous reset
       -- SHIFTIN1, SHIFTIN2: 1-bit (each) input: Data width expansion input ports
       SHIFTIN1 => '0',
       SHIFTIN2 => '0'
    );


end RTL;