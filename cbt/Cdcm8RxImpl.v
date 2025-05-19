`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/17/2024 04:01:01 PM
// Design Name: 
// Module Name: Cdcm8RxImpl
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////



module Cdcm8RxImpl(
        dInFromPinP,
        dInFromPinN,
        
        rstIDelay,
        ceIDelay,
        incIDelay,
        EN_VTC,
        
        tapIn,
        tapOut,
        //tapOut_slave,
        CNTVALUEOUT,
        CNTVALUEOUT_slave,
        
        cdOutFromO,
        dOutToDevice,
        bitslip,
        
        clkIn,
        clkDivIn,
        ioReset
        
    );
    
    parameter kSysW = 1;
    parameter kDevW = 8;
    parameter kSelCount = 3;
    parameter kDiffTerm = "TRUE";
    parameter kRxPolarity = "FALSE";
    parameter kIoStandard = "LVDS";
    parameter kIoDelayGroup = "cdcm_rx";
    parameter kFreqRefClk = 500;
    parameter kIdelayCtrlclk = 500;
    parameter kCNTVALUEbit = 9;
    parameter kDELAY_VALUE = 1000.0;
    
    input dInFromPinP;
    input dInFromPinN;
    
    input   rstIDelay;
    input   ceIDelay;
    input   incIDelay;
    input   EN_VTC;
    input [4:0] tapIn;
    output [4:0] tapOut;
    //output [8:0] tapOut_slave;
    output [kCNTVALUEbit-1:0] CNTVALUEOUT;
    output [kCNTVALUEbit-1:0] CNTVALUEOUT_slave;    
    
    output cdOutFromO;
    output [kDevW-1:0] dOutToDevice;    
    input bitslip;
    
    input clkIn;
    input clkDivIn;
    input ioReset;
    
    wire [8:0] tapOut_slave;
    
    wire data_in_from_pin_P;
    wire data_in_from_pin_N;
    
    IBUFDS_DIFF_OUT
      #(
        .DIFF_TERM  (kDiffTerm),
        .IOSTANDARD (kIoStandard)
      )             // Differential termination
     ibufds_inst
       (.I          (dInFromPinP),
        .IB         (dInFromPinN),
        .O          (data_in_from_pin_P),
        .OB         (data_in_from_pin_N) 
       );
       
    wire idelay3_out;
    
    wire [8:0] CNTVALUEIN;
    wire [8:0] CNTVALUEIN_slave;
    wire [8:0] CNTVALUEOUT_REFCLK;          //sync to REFCLK
    wire [8:0] CNTVALUEOUT_slave_REFCLK;    //sync to REFCLK
    assign CNTVALUEIN[8:0] = {tapIn[4:0], 4'h0};
    assign tapOut[4:0] = CNTVALUEOUT[8:4];  //tmp
    assign CNTVALUEIN_slave = {tapIn[4:0], 4'h0};
    assign tapOut_slave[8:0] = CNTVALUEOUT_slave[8:0];    


    //slaveout refclk to clk_slow--------------------------
    reg [8:0] CNTVALUEOUT_level0[1:0];
    reg [8:0] CNTVALUEOUT_slave_level0[1:0];
    always@(posedge clkDivIn)begin
        CNTVALUEOUT_level0[0] <= CNTVALUEOUT_REFCLK;
        CNTVALUEOUT_level0[1] <=  CNTVALUEOUT_level0[0];
        CNTVALUEOUT_slave_level0[0] <= CNTVALUEOUT_slave_REFCLK;
        CNTVALUEOUT_slave_level0[1] <= CNTVALUEOUT_slave_level0[0];
    end
    
    assign CNTVALUEOUT = CNTVALUEOUT_level0[0];
    assign CNTVALUEOUT_slave = CNTVALUEOUT_slave_level0[0];
    //--------------------------------------------------------

    wire CASC_OUT;
    wire CASC_RETURN;   
    
    (* IODELAY_GROUP = kIoDelayGroup *)
     IDELAYE3
       # (
         .CASCADE("MASTER"),
         .DELAY_FORMAT("TIME"),
         .DELAY_SRC              ("IDATAIN"),                          // IDATAIN, DATAIN
         .DELAY_TYPE            ("VAR_LOAD"),              // FIXED, VARIABLE, or VAR_LOADABLE
         .DELAY_VALUE           (kDELAY_VALUE),
         .REFCLK_FREQUENCY       (kFreqRefClk),
         .SIM_DEVICE            ("ULTRASCALE_PLUS")
       )
       idelaye3_bus_master(
         .CASC_OUT(CASC_OUT), // 1-bit output: Cascade delay output to ODELAY input cascade
         .CNTVALUEOUT(CNTVALUEOUT_REFCLK[8:0]), // 9-bit output: Counter value output
         .DATAOUT(idelay3_out), // 1-bit output: Delayed data output
         .CASC_IN(1'b0), // 1-bit input: Cascade delay input from slave ODELAY CASCADE_OUT
         .CASC_RETURN(CASC_RETURN), // 1-bit input: Cascade delay returning from slave ODELAY DATAOUT
         .CE(ceIDelay), // 1-bit input: Active high enable increment/decrement input
         .CLK(clkDivIn), // 1-bit input: Clock input
         .CNTVALUEIN(CNTVALUEIN[8:0]), // 9-bit input: Counter value input
         .DATAIN(1'b0), // 1-bit input: Data input from the logic
         .EN_VTC(EN_VTC),
         .IDATAIN(data_in_from_pin_N), // 1-bit input: Data input from the IOBUF
         .INC(incIDelay), // 1-bit input: Increment / Decrement tap delay input
         .LOAD(rstIDelay), // 1-bit input: Load DELAY_VALUE input
         .RST(ioReset) // 1-bit input: Asynchronous Reset to the DELAY_VALUE
      );

    (* IODELAY_GROUP = kIoDelayGroup *)
     ODELAYE3
       # (
         .CASCADE("SLAVE_END"),
         .DELAY_FORMAT("TIME"),
         .DELAY_TYPE            ("VAR_LOAD"),              // FIXED, VARIABLE, or VAR_LOADABLE
         .DELAY_VALUE           (1000.0),                  // 0 to 31
         .REFCLK_FREQUENCY       (kFreqRefClk),
         .SIM_DEVICE            ("ULTRASCALE_PLUS")
       )
       idelaye3_bus_slave(
         .CASC_OUT(), // 1-bit output: Cascade delay output to ODELAY input cascade
         .CNTVALUEOUT(CNTVALUEOUT_slave_REFCLK[8:0]), // 9-bit output: Counter value output
         .DATAOUT(CASC_RETURN), // 1-bit output: Delayed data output
         .CASC_IN(CASC_OUT), // 1-bit input: Cascade delay input from slave ODELAY CASCADE_OUT
         .CASC_RETURN(1'b0), // 1-bit input: Cascade delay returning from slave ODELAY DATAOUT
         .CE(ceIDelay), // 1-bit input: Active high enable increment/decrement input
         .CLK(clkDivIn), // 1-bit input: Clock input
         .CNTVALUEIN(CNTVALUEIN_slave[8:0]), // 9-bit input: Counter value input
         .EN_VTC(EN_VTC),
         .ODATAIN(),
         .INC(incIDelay), // 1-bit input: Increment / Decrement tap delay input
         .LOAD(rstIDelay), // 1-bit input: Load DELAY_VALUE input
         .RST(ioReset) // 1-bit input: Asynchronous Reset to the DELAY_VALUE
      );

    assign cdOutFromO = data_in_from_pin_P;
    
    wire [kDevW-1:0] iserdes_out;
    
   ISERDESE3 #(
      .DATA_WIDTH(kDevW), // Parallel data width (4,8)
      .FIFO_ENABLE("FALSE"), // Enables the use of the FIFO
      .FIFO_SYNC_MODE("FALSE"), // Always set to FALSE. TRUE is reserved for later use.
      .IS_CLK_B_INVERTED(1'b0), // Optional inversion for CLK_B
      .IS_CLK_INVERTED(1'b0), // Optional inversion for CLK
      .IS_RST_INVERTED(1'b0), // Optional inversion for RST
      .SIM_DEVICE("ULTRASCALE_PLUS") // Set the device version (ULTRASCALE)
   )
   ISERDESE3_inst (
      .FIFO_EMPTY(), // 1-bit output: FIFO empty flag
      .INTERNAL_DIVCLK(), // 1-bit output: Internally divided down clock used when FIFO is
      // disabled (do not connect)
      .Q(iserdes_out[kDevW-1:0]), // 8-bit registered output
      .CLK(clkIn), // 1-bit input: High-speed clock
      .CLKDIV(clkDivIn), // 1-bit input: Divided Clock
      .CLK_B(~clkIn), // 1-bit input: Inversion of High-speed clock CLK
      .D(idelay3_out), // 1-bit input: Serial Data Input
      .FIFO_RD_CLK(1'b0), // 1-bit input: FIFO read clock
      .FIFO_RD_EN(1'b0), // 1-bit input: Enables reading the FIFO when asserted
      .RST(ioReset)
   );
   
   
    wire [kDevW-1:0] iserdes_out_level2;
    
    genvar j;
    generate
        for (j = 0; j < kDevW; j = j + 1) begin : j_loop   
            //IDATAIN of iserdese3 is negative signal.
            //Therefore, we need inveter for iserdes_out.
            //assign iserdes_out_level2[j] = ~iserdes_out[kDevW-1-j];
            if (kRxPolarity == "FALSE") begin
                assign iserdes_out_level2[j] = ~iserdes_out[j];
            end
            else begin
                assign iserdes_out_level2[j] = iserdes_out[j];
            end                
        end
    endgenerate
    

    
   
    reg [kDevW-1:0] iserdes_out_level2_old;
    reg [kDevW-1:0] iserdes_out_level2_old2;
    always@(posedge clkDivIn)begin
        iserdes_out_level2_old[kDevW-1:0]  <= iserdes_out_level2[kDevW-1:0] ;
        iserdes_out_level2_old2[kDevW-1:0]  <= iserdes_out_level2_old[kDevW-1:0] ;
    end
   
    reg [kSelCount-1:0] sel_MP;
    always@(posedge clkDivIn)begin
        if(ioReset)begin
            sel_MP[kSelCount-1:0] <= 0;
        end
        else if(bitslip)begin
            sel_MP[kSelCount-1:0] <= sel_MP[kSelCount-1:0] + 1'b1;
        end
    end
    
    wire [kDevW-1:0] iserdes_out_level3[kDevW-1:0];
   
    assign iserdes_out_level3[0][kDevW-1:0] = iserdes_out_level2_old[kDevW-1:0];
    genvar i; 
    generate
        for (i = 1; i < kDevW; i = i + 1) begin : MP_loop   
            //assign iserdes_out_level3[i][kDevW-1:0] = {iserdes_out_level2_old2[kDevW-i-1:0], iserdes_out_level2_old[kDevW-1:kDevW-i]};
            //assign iserdes_out_level3[i][kDevW-1:0] = {iserdes_out_level2_old2[i-1:0], iserdes_out_level2_old[kDevW-1:i]};
            //assign iserdes_out_level3[i][kDevW-1:0] = {iserdes_out_level2_old2[i-1:0], iserdes_out_level2_old[kDevW-1:i]};
            assign iserdes_out_level3[i][kDevW-1:0] = {iserdes_out_level2_old[kDevW-1-i:0],iserdes_out_level2_old2[kDevW-1:kDevW-i]};
            
        end
    endgenerate
   
    assign dOutToDevice[kDevW-1:0] = iserdes_out_level3[sel_MP][kDevW-1:0];
   
    
    ila_0 ila_0(
        .clk(clkDivIn),
        .probe0(iserdes_out_level2[kDevW-1:0]),
        .probe1(CNTVALUEOUT[8:0]),
        .probe2(CNTVALUEIN[8:0]),
        .probe3(iserdes_out_level3[0][kDevW-1:0]),
        .probe4(iserdes_out_level3[1][kDevW-1:0]),
        .probe5(iserdes_out_level3[2][kDevW-1:0]),
        .probe6(iserdes_out_level3[3][kDevW-1:0]),
        .probe7(iserdes_out_level3[4][kDevW-1:0]),
        .probe8(iserdes_out_level3[5][kDevW-1:0]),
        .probe9(iserdes_out_level3[6][kDevW-1:0]),
        .probe10(iserdes_out_level3[7][kDevW-1:0]),
        .probe11(dOutToDevice[kDevW-1:0] ),
        .probe12(bitslip),
        .probe13(EN_VTC),
        .probe14(rstIDelay)
    );
    
   
    
    
    
endmodule
