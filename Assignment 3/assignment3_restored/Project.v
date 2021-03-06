module Project(
	input        CLOCK_50,
	input        RESET_N,
	input  [3:0] KEY,
	input  [9:0] SW,
	output [6:0] HEX0,
	output [6:0] HEX1,
	output [6:0] HEX2,
	output [6:0] HEX3,
	output [6:0] HEX4,
	output [6:0] HEX5,
	output [9:0] LEDR
);

  parameter DBITS    =32;
  parameter INSTSIZE =32'd4;
  parameter INSTBITS =32;
  parameter REGNOBITS =4;
  parameter REGWORDS=(1<<REGNOBITS);
  parameter IMMBITS  =16;
  parameter STARTPC  =32'h100;
  parameter ADDRHEX  =32'hFFFFF000;
  parameter ADDRLEDR =32'hFFFFF020;
  parameter ADDRKEY  =32'hFFFFF080;
  parameter ADDRSW   =32'hFFFFF090;
    // Change this to fmedian2.mif before submitting
  parameter IMEMINITFILE="fmedian2.mif";
  
  parameter IMEMADDRBITS=16;
  parameter IMEMWORDBITS=2;
  parameter IMEMWORDS=(1<<(IMEMADDRBITS-IMEMWORDBITS));
  parameter DMEMADDRBITS=16;
  parameter DMEMWORDBITS=2;
  parameter DMEMWORDS=(1<<(DMEMADDRBITS-DMEMWORDBITS));
  
 
  parameter OP1BITS  =6;
  parameter OP1_ALUR =6'b000000;
  parameter OP1_BEQ  =6'b001000;
  parameter OP1_BLT  =6'b001001;
  parameter OP1_BLE  =6'b001010;
  parameter OP1_BNE  =6'b001011;
  parameter OP1_JAL  =6'b001100;
  parameter OP1_LW   =6'b010010;
  parameter OP1_SW   =6'b011010;
  parameter OP1_ADDI =6'b100000;
  parameter OP1_ANDI =6'b100100;
  parameter OP1_ORI  =6'b100101;
  parameter OP1_XORI =6'b100110;
  
  // Add parameters for secondary opcode values
    
  /* OP2 */
  parameter OP2BITS  = 8;
  parameter OP2_EQ   = 8'b00001000;
  parameter OP2_LT   = 8'b00001001;
  parameter OP2_LE   = 8'b00001010;
  parameter OP2_NE   = 8'b00001011;

  parameter OP2_ADD  = 8'b00100000;
  parameter OP2_AND  = 8'b00100100;
  parameter OP2_OR   = 8'b00100101;
  parameter OP2_XOR  = 8'b00100110;
  parameter OP2_SUB  = 8'b00101000;
  parameter OP2_NAND = 8'b00101100;
  parameter OP2_NOR  = 8'b00101101;
  parameter OP2_NXOR = 8'b00101110;
  parameter OP2_RSHF = 8'b00110000;
  parameter OP2_LSHF = 8'b00110001;
  
  parameter HEXBITS  = 24;
  parameter LEDRBITS = 10;
  


  
	// The reset signal comes from the reset button on the DE0-CV board
	// RESET_N is active-low, so we flip its value ("reset" is active-high)
	wire clk,locked;
	// The PLL is wired to produce clk and locked signals for our logic
	Pll myPll(
		.refclk(CLOCK_50),
		.rst      (!RESET_N),
		.outclk_0 (clk),
		.locked   (locked)
	);
	//assign clk=CLOCK_50;

	wire reset=!locked;
	//wire reset=!RESET_N;
  
   
  	/**** FETCH STAGE ****/ 
  
	// The PC register and update logic
	reg [(DBITS-1):0] PC;
	
	reg stall_F;
	reg isnop_F;
	wire [(DBITS-1):0] pcgood_B;
	wire mispred_B;
	wire [(DBITS-1):0] pcpred_F;
	
	// This is the value of "incremented PC", computed in stage 1
	wire [(DBITS-1):0] pcplus_F=PC+INSTSIZE;
	// This is the predicted value of the PC
	// that we used to fetch the next instruction
	assign pcpred_F=pcplus_F;
	
	always @(posedge clk) begin
		if(reset)
			PC<=STARTPC;
		else if(mispred_B)
			PC<=pcgood_B;
		else if (stall_F)
			PC<=PC;
		else
			PC<=pcpred_F;
	end


	// Instruction-fetch
	(* ram_init_file = IMEMINITFILE *)
	reg [(DBITS-1):0] imem[(IMEMWORDS-1):0];
	/*
	initial 
	begin 
		$readmemh("Test.hex", imem);
	end 
   */
	wire [(DBITS-1):0] inst_F=imem[PC[(IMEMADDRBITS-1):IMEMWORDBITS]];
		
	// Fetch latches
	reg [(DBITS-1):0] inst_FL;
	reg [(DBITS-1):0] pcplus_FL;
	reg [(DBITS-1):0] pcpred_FL;
	reg isnop_FL;
	
	always @(posedge clk) begin	
		if (reset || isnop_F) begin
			isnop_FL <= 1;
			inst_FL <= 0;
			pcplus_FL <= 0;
			pcpred_FL <= 0;
		end
		else if (!stall_F) begin
			inst_FL <= inst_F;
			pcplus_FL <= pcplus_F;
			pcpred_FL <= pcpred_F;
			isnop_FL <= isnop_F;
		end
	end
	
	
	/*** DECODE STAGE ***/ 

	// If fetch and decoding stages are the same stage,
	// just connect signals from fetch to decode
	// Getting from latch
	wire [(DBITS-1):0] inst_D=inst_FL;
	wire [(DBITS-1):0] pcplus_D=pcplus_FL;
	wire [(DBITS-1):0] pcpred_D=pcpred_FL;
	// Instruction decoding
	// These have zero delay from inst_D
	// because they are just new names for those signals
	wire [(OP1BITS-1):0]    op1_D = inst_D[31:26];
	wire [(REGNOBITS-1):0]  rd_D, rs_D, rt_D;
	
	assign 	{rd_D        ,rs_D       ,rt_D       } = 
				{inst_D[11:8],inst_D[7:4],inst_D[3:0]};
	
	wire [(OP2BITS-1):0] op2_D = inst_D[25:18];
	
	wire [(IMMBITS-1):0] rawimm_D = inst_D[23:8];
	wire [(DBITS-1):0] sxtimm_D;
	SXT sxt(rawimm_D, sxtimm_D);
	defparam sxt.IBITS = IMMBITS;
	defparam sxt.OBITS = DBITS;
	
	// Register-read
	reg [(DBITS-1):0] regs[(REGWORDS-1):0];

	// Two read ports, always using rs and rt for register numbers
	wire [(REGNOBITS-1):0] rregno1_D=rs_D, rregno2_D=rt_D;
	reg [(DBITS-1):0] regval1_D;
	reg [(DBITS-1):0] regval2_D;
	
	// Register scoreboard
	reg [(REGWORDS-1):0] regBusy_D = 0;
	reg wrreg_WL;
	reg [REGNOBITS-1:0] wregno_WL;
	
	// initialize regs and scoreboard
	reg [7:0] i;
	initial begin
		for (i = 0; i < REGWORDS; i = i + 1) begin
			regs[i] = 0;
		end
	end

	// MEM/WB latch registers
	reg wrreg_ML;
	reg [REGNOBITS-1:0] wregno_ML;
	reg [DBITS-1:0] wregval_ML;
	
	reg stall_D = 0;

	// Control signals 
	reg aluimm_D, isbranch_D, isjump_D, isnop_D, wrmem_D;
	reg selaluout_D, selmemout_D, selpcplus_D, wrreg_D;
	reg [OP2BITS-1:0] alufunc_D;
	reg [REGNOBITS-1:0] wregno_D;
	
	wire flush_D;
	
	always @* begin
		{aluimm_D,      alufunc_D}=
		{    1'bX,{OP2BITS{1'bX}}};
		{isbranch_D,isjump_D,wrmem_D}=
		{      1'b0,    1'b0,   1'b0};
		{selaluout_D,selmemout_D,selpcplus_D,wregno_D,          wrreg_D}=
		{       1'bX,       1'bX,       1'bX,{REGNOBITS{1'bX}},   1'b0};

		case(op1_D)
			OP1_ALUR: begin
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,wregno_D,wrreg_D}=
				{    1'b0,    op2_D,       1'b1,       1'b0,       1'b0,    rd_D,   1'b1};
			end
		// TODO: Write the rest of the decoding code
			OP1_BEQ: begin
				isbranch_D = 1'b1;
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,         wrreg_D}=
				{    1'b0,   OP2_EQ,       1'b0,       1'b0,       1'b0,            1'b0};
			end
			OP1_BLT: begin
				isbranch_D = 1'b1;
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,         wrreg_D}=
				{    1'b0,   OP2_LT,       1'b0,       1'b0,       1'b0,            1'b0};
			end
			OP1_BLE: begin
				isbranch_D = 1'b1;
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,         wrreg_D}=
				{    1'b0,   OP2_LE,       1'b0,       1'b0,       1'b0,            1'b0};
			end
			OP1_BNE: begin
				isbranch_D = 1'b1;
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,         wrreg_D}=
				{    1'b0,   OP2_NE,       1'b0,       1'b0,       1'b0,            1'b0};
			end
			OP1_JAL: begin
				isjump_D = 1'b1;
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,wregno_D,wrreg_D}=
				{    1'b0,  OP2_ADD,       1'b0,       1'b0,       1'b1,    rt_D,   1'b1};
			end
			OP1_LW: begin
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,wregno_D,wrreg_D}=
				{    1'b1,  OP2_ADD,       1'b0,       1'b1,       1'b0,    rt_D,   1'b1};
			end
			OP1_SW: begin
				wrmem_D = 1'b1;
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,         wrreg_D}=
				{    1'b1,  OP2_ADD,       1'b0,       1'b0,       1'b0,            1'b0};
			end
			OP1_ADDI: begin
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,wregno_D,wrreg_D}=
				{    1'b1,  OP2_ADD,       1'b1,       1'b0,       1'b0,    rt_D,   1'b1};
			end
			OP1_ANDI: begin
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,wregno_D,wrreg_D}=
				{    1'b1,  OP2_AND,       1'b1,       1'b0,       1'b0,    rt_D,   1'b1};
			end
			OP1_ORI: begin
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,wregno_D,wrreg_D}=
				{    1'b1,   OP2_OR,       1'b1,       1'b0,       1'b0,    rt_D,   1'b1};
			end
			OP1_XORI: begin
				{aluimm_D,alufunc_D,selaluout_D,selmemout_D,selpcplus_D,wregno_D,wrreg_D}=
				{    1'b1,  OP2_XOR,       1'b1,       1'b0,       1'b0,    rt_D,   1'b1};
			end
			default:  ;
		endcase
	end
	
	wire isbranch_A, isjump_A;
	
	always @* begin
		if (regBusy_D[rregno1_D] || (regBusy_D[rregno2_D] && (!aluimm_D || wrmem_D)) || (regBusy_D[wregno_D] && wrreg_D)) begin
			stall_F = 1'b1;
			isnop_F = 1'b0;
			isnop_D = 1'b1;
			stall_D = 1'b1;
			regval1_D = 0;
			regval2_D = 0;
		end
		else if (isbranch_D || isjump_D) begin
			stall_F = 1'b1;
			isnop_F = 1'b1;
			stall_D = 1'b0;
			isnop_D = isnop_FL;
			regval1_D = regs[rregno1_D];
			regval2_D = regs[rregno2_D];
		end
		else if (isbranch_A || isjump_A) begin
			stall_F = 1'b1;
			isnop_F = 1'b1;
			stall_D = 1'b0;
			isnop_D = isnop_FL;
			regval1_D = 0;
			regval2_D = 0;
		end
		else begin
			stall_F = 1'b0;
			isnop_F = 1'b0;
			isnop_D = isnop_FL;
			stall_D = 1'b0;
			regval1_D = regs[rregno1_D];
			regval2_D = regs[rregno2_D];
		end
		
	end
	
	
		
	// Decode latches
	reg wrmem_DL;
	reg selaluout_DL;
	reg selmemout_DL;
	reg selpcplus_DL;
	reg [REGNOBITS-1:0] wregno_DL;
	reg wrreg_DL;
	reg [DBITS-1:0] sxtimm_DL;
	reg [OP2BITS-1:0] alufunc_DL;
	reg [DBITS-1:0] regval1_DL;
	reg [DBITS-1:0] regval2_DL;
	reg aluimm_DL;
	reg [(DBITS-1):0] pcplus_DL;
	reg [(DBITS-1):0] pcpred_DL;
	reg isjump_DL;
	reg isbranch_DL;
	reg isnop_DL;
	
	always @(posedge clk) begin
		if (reset || isnop_D) begin
			isnop_DL <= 1;
			wrmem_DL <= 0;
			selaluout_DL <= 0;
			selmemout_DL <= 0;
			selpcplus_DL <= 0;
			wregno_DL <= 0;
			wrreg_DL <= 0;
			sxtimm_DL <= 0;
			alufunc_DL <= 0;
			regval1_DL <= 0;
			regval2_DL <= 0;
			aluimm_DL <= 0;
			pcplus_DL <= 0;
			pcpred_DL <= 0;
			isbranch_DL <= 0;
			isjump_DL <= 0;
		end
		else if (!stall_D) begin
			wrmem_DL <= wrmem_D;
			selaluout_DL <= selaluout_D;
			selmemout_DL <= selmemout_D;
			selpcplus_DL <= selpcplus_D;
			wregno_DL <= wregno_D;
			wrreg_DL <= wrreg_D;
			sxtimm_DL <= sxtimm_D;
			alufunc_DL <= alufunc_D;
			regval1_DL <= regval1_D;
			regval2_DL <= regval2_D;
			aluimm_DL <= aluimm_D;
			pcplus_DL <= pcplus_D;
			pcpred_DL <= pcpred_D;
			isbranch_DL <= isbranch_D;
			isjump_DL <= isjump_D;
			isnop_DL <= isnop_D;
		end
	end
	
	
	/**** AGEN/EXEC STAGE ****/
	wire wrmem_A = wrmem_DL;
	wire selaluout_A = selaluout_DL;
	wire selmemout_A = selmemout_DL;
	wire selpcplus_A = selpcplus_DL;
	wire [REGNOBITS-1:0] wregno_A = wregno_DL;
	wire wrreg_A = wrreg_DL;
	assign isbranch_A = isbranch_DL;
	
	wire [DBITS-1:0] sxtimm_A = sxtimm_DL;
	wire [OP2BITS-1:0] alufunc_A = alufunc_DL;
	wire signed [DBITS-1:0] aluin1_A = regval1_DL;
	wire signed [DBITS-1:0] aluin2_A = aluimm_DL ? sxtimm_A : regval2_DL;
	wire [DBITS-1:0] regval2_A = regval2_DL;

	reg signed [(DBITS-1):0] aluout_A;
	always @(alufunc_A or aluin1_A or aluin2_A)
	case(alufunc_A)
		OP2_EQ:		aluout_A = {31'b0,aluin1_A==aluin2_A};
		OP2_LT:		aluout_A = {31'b0,aluin1_A< aluin2_A};
		OP2_LE:		aluout_A = {31'b0,aluin1_A<=aluin2_A};
		OP2_NE:		aluout_A = {31'b0,aluin1_A!=aluin2_A};
		OP2_ADD:		aluout_A = aluin1_A+aluin2_A;
		OP2_AND:		aluout_A = aluin1_A&aluin2_A;
		OP2_OR:		aluout_A = aluin1_A|aluin2_A;
		OP2_XOR:		aluout_A = aluin1_A^aluin2_A;
		OP2_SUB:		aluout_A = aluin1_A-aluin2_A;
		OP2_NAND:	aluout_A = ~(aluin1_A&aluin2_A);
		OP2_NOR:		aluout_A = ~(aluin1_A|aluin2_A);
		OP2_NXOR:	aluout_A = ~(aluin1_A^aluin2_A);
		OP2_RSHF:	aluout_A = (aluin1_A >>> aluin2_A);
		OP2_LSHF:	aluout_A = (aluin1_A << aluin2_A);
		default:		aluout_A = {DBITS{1'bX}};
	endcase

		
	// TODO: Generate the dobranch, brtarg, isjump, and jmptarg signals somehow...
	wire [(DBITS-1):0] pcplus_A = pcplus_DL;
	wire [(DBITS-1):0] pcpred_A = pcpred_DL;
	wire dobranch_A = isbranch_A && aluout_A[0];
	wire [DBITS-1:0] brtarg_A = pcplus_A + (sxtimm_A << 2);
	assign isjump_A = isjump_DL;
	wire [DBITS-1:0] jmptarg_A = aluin1_A + (sxtimm_A << 2);
	wire isnop_A = isnop_DL;
	
	wire [(DBITS-1):0] pcgood_A=
		dobranch_A?brtarg_A:
		isjump_A?jmptarg_A:
		pcplus_A;
	wire mispred_A=(pcgood_A!=pcpred_A);
	assign mispred_B=mispred_A&&!isnop_A;
	assign pcgood_B=pcgood_A;
	// TODO: This is a good place to generate the flush_? signals

	
	//EXEC latches
	reg wrmem_AL;
	reg selaluout_AL;
	reg selmemout_AL;
	reg selpcplus_AL;
	reg [REGNOBITS-1:0] wregno_AL;
	reg wrreg_AL;
	reg [DBITS-1:0] regval2_AL;
	reg [DBITS-1:0] pcplus_AL;
	reg [DBITS-1:0] aluout_AL;
	reg isnop_AL;
	
	always @(posedge clk) begin
		if (reset || isnop_A) begin
			isnop_AL <= 1;
			wrmem_AL <= 0;
			selaluout_AL <= 0;
			selmemout_AL <= 0;
			selpcplus_AL <= 0;
			wregno_AL <= 0;
			wrreg_AL <= 0;
			regval2_AL <= 0;
			pcplus_AL <= 0;
			aluout_AL <= 0;
		end
		else begin
			wrmem_AL <= wrmem_A;
			selaluout_AL <= selaluout_A;
			selmemout_AL <= selmemout_A;
			selpcplus_AL <= selpcplus_A;
			wregno_AL <= wregno_A;
			wrreg_AL <= wrreg_A;
			regval2_AL <= regval2_A;
			pcplus_AL <= pcplus_A;
			aluout_AL <= aluout_A;
			isnop_AL <= isnop_A;
		end
	end
	
	
	/*** MEM STAGE ****/ 

	// TODO: Write code that produces wmemval_M, wrmem_M, wrreg_M, etc.
	wire isnop_M = isnop_AL;
	wire wrmem_M = wrmem_AL & !isnop_M;
	wire selaluout_M = selaluout_AL;
	wire selmemout_M = selmemout_AL;
	wire selpcplus_M = selpcplus_AL;
	wire [REGNOBITS-1:0] wregno_M = wregno_AL;
	wire wrreg_M = wrreg_AL;
	wire [DBITS-1:0] aluout_M = aluout_AL;
	
	wire [DBITS-1:0] memaddr_M, wmemval_M, pcplus_M;

	assign memaddr_M = aluout_M;
	assign wmemval_M = regval2_AL;
	assign pcplus_M = pcplus_AL;


   // Create and connect HEX register
	reg [23:0] HexOut;
	SevenSeg ss5(.OUT(HEX5),.IN(HexOut[23:20]));
	SevenSeg ss4(.OUT(HEX4),.IN(HexOut[19:16]));
	SevenSeg ss3(.OUT(HEX3),.IN(HexOut[15:12]));
	SevenSeg ss2(.OUT(HEX2),.IN(HexOut[11:8]));
	SevenSeg ss1(.OUT(HEX1),.IN(HexOut[7:4]));
	SevenSeg ss0(.OUT(HEX0),.IN(HexOut[3:0]));
	always @(posedge clk or posedge reset)
		if(reset)
			HexOut<=24'hFEDEAD;
		else if(wrmem_M&&(memaddr_M==ADDRHEX))
			HexOut <= wmemval_M[23:0];
	/*SevenSeg ss5(.OUT(HEX5),.IN(PC[7:4]));
	SevenSeg ss4(.OUT(HEX4),.IN(PC[3:0]));
	SevenSeg ss3(.OUT(HEX3),.IN(regs[3]));
	SevenSeg ss2(.OUT(HEX2),.IN(regs[13]));
	SevenSeg ss1(.OUT(HEX1),.IN(regs[5]));
	SevenSeg ss0(.OUT(HEX0),.IN(regs[6]));*/

	// TODO: Write the code for LEDR here
	reg [9:0] LedrOut;
	always @(posedge clk or posedge reset)
		if(reset)
			LedrOut<=10'b1010101010;
		else if(wrmem_M&&(memaddr_M==ADDRLEDR))
			LedrOut <= wmemval_M[9:0];
	assign LEDR = LedrOut;

	// Now the real data memory
	wire MemEnable=!(memaddr_M[(DBITS-1):DMEMADDRBITS]);
	wire MemWE=(!reset)&wrmem_M&MemEnable;
	(* ram_init_file = IMEMINITFILE, ramstyle="no_rw_check" *)
	reg [(DBITS-1):0] dmem[(DMEMWORDS-1):0];
	always @(posedge clk)
		if(MemWE)
			dmem[memaddr_M[(DMEMADDRBITS-1):DMEMWORDBITS]]<=wmemval_M;

	wire [(DBITS-1):0] MemVal=MemWE?{DBITS{1'bX}}:dmem[memaddr_M[(DMEMADDRBITS-1):DMEMWORDBITS]];

	// Connect memory and input devices to the bus
	// you might need to change the following statement. 
	wire [(DBITS-1):0] memout_M=
		MemEnable?MemVal:
		(memaddr_M==ADDRKEY)?{28'b0,~KEY}:
		(memaddr_M==ADDRSW)? { 20'b0,SW}:
		32'hDEADDEAD;
			
	// TODO: Decide what gets written into the destination register (wregval_M),
	// when it gets written (wrreg_M) and to which register it gets written (wregno_M)
	wire [DBITS-1:0] wregval_M = 	selaluout_M ? aluout_M :
							selmemout_M ? memout_M :
							selpcplus_M ? pcplus_M :
							{DBITS{1'bX}};
	
	
	// MEM latches
	// declared earlier at decode for scoreboard
	reg isnop_ML;
	
	always @(posedge clk) begin
		if (reset || isnop_M) begin
			isnop_ML <= 1;
			wrreg_ML <= 0;
			wregno_ML <= 0;
			wregval_ML <= 0;
		end
		else begin
			wrreg_ML <= wrreg_M;
			wregno_ML <= wregno_M;
			wregval_ML <= wregval_M;
			isnop_ML <= isnop_M;
		end
	end
				
	/*** Write Back Stage *****/ 
	
	reg testbusy_1, testbusy_2, testbusy_3;
	
	always @(posedge clk) begin
		if(wrreg_ML && !isnop_ML && !reset) begin
			regs[wregno_ML]<=wregval_ML;
			regBusy_D[wregno_ML] <= 1'b0;
		end
		
		if (reset) begin
			regBusy_D[wregno_D] <= 1'b0;
		end
		else if (wrreg_D && !isnop_D) begin
			regBusy_D[wregno_D] <= 1'b1;
		end
		
		testbusy_1 <= regBusy_D[rregno1_D];
		testbusy_2 <= regBusy_D[rregno2_D];
		testbusy_3 <= regBusy_D[wregno_ML];
	end
	
endmodule




module SXT(IN,OUT);
  parameter IBITS;
  parameter OBITS;
  input  [(IBITS-1):0] IN;
  output [(OBITS-1):0] OUT;
  assign OUT={{(OBITS-IBITS){IN[IBITS-1]}},IN};
endmodule
