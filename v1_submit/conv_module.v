/*
* conv_module.v
*/

module conv_module 
  #(
    parameter integer C_S00_AXIS_TDATA_WIDTH = 32
    // parameters
  )
  (
    input wire clk,
    input wire rstn,

    output wire S_AXIS_TREADY,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] S_AXIS_TDATA,
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] S_AXIS_TKEEP, 
    input wire S_AXIS_TUSER, 
    input wire S_AXIS_TLAST, 
    input wire S_AXIS_TVALID, 

    input wire M_AXIS_TREADY, 
    output wire M_AXIS_TUSER, 
    output wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] M_AXIS_TDATA, 
    output wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] M_AXIS_TKEEP, 
    output wire M_AXIS_TLAST, 
    output wire M_AXIS_TVALID, 

    input conv_start, 
    output reg conv_done,

    //////////////////////////////////////////////////////////////////////////
    // TODO : Add ports if you need them
    
    input wire [2:0] COMMAND, // 0:IDLE, 1:Feature, 2:Bias, 3:Calc, 4:Transmit
    input wire [8:0] InCh,    // #input channels
    input wire [8:0] OutCh,   // #output channels
    input wire [5:0] FHeight, // feature map height
    input wire [5:0] FWidth,  // feature map width
    
    output reg  F_writedone,
    output reg  B_writedone,
    output reg  rdy_to_transmit
  );
  
  //reg                                           m_axis_tuser;
  wire [C_S00_AXIS_TDATA_WIDTH-1 : 0]            m_axis_tdata;
  //reg [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0]        m_axis_tkeep;
  reg                                           m_axis_tlast;
  reg                                           m_axis_tvalid;
  wire                                          s_axis_tready;
  
  assign S_AXIS_TREADY = s_axis_tready;
  assign M_AXIS_TDATA = m_axis_tdata;
  assign M_AXIS_TLAST = m_axis_tlast;
  assign M_AXIS_TVALID = m_axis_tvalid;
  assign M_AXIS_TUSER = 1'b0;
  assign M_AXIS_TKEEP = {(C_S00_AXIS_TDATA_WIDTH/8) {1'b1}};

  ////////////////////////////////////////////////////////////////////////////
  // TODO : Write your code here
  ////////////////////////////////////////////////////////////////////////////

  // Team 
  // Digital System Design (2025-2)
  reg [C_S00_AXIS_TDATA_WIDTH-1 : 0] m_axis_tdata_reg; // tdata 제어용
  reg s_axis_tready_reg;                               // tready 제어용
  wire s_is_handshake;
  wire m_is_handshake;
  
  assign m_axis_tdata   = m_axis_tdata_reg;
  assign s_axis_tready  = s_axis_tready_reg;
  assign s_is_handshake = S_AXIS_TREADY && S_AXIS_TVALID;
  assign m_is_handshake = M_AXIS_TREADY && M_AXIS_TVALID;
  
  // Feature BRAM (shuffled input)
  // sram 32x256 (byte-wise write enable)
  wire [3:0] we_ee, we_eo, we_oe, we_oo;
  wire [8:0] addr_ee, addr_eo, addr_oe, addr_oo;
  wire [31:0] din_ee, din_eo, din_oe, din_oo;
  wire [31:0] dout_ee, dout_eo, dout_oe, dout_oo;
  sram_32x512_i feature_ee (.clka(clk), .ena(1'b1), .wea(we_ee), .addra(addr_ee), .dina(din_ee), .douta(dout_ee));
  sram_32x512_i feature_eo (.clka(clk), .ena(1'b1), .wea(we_eo), .addra(addr_eo), .dina(din_eo), .douta(dout_eo));
  sram_32x512_i feature_oe (.clka(clk), .ena(1'b1), .wea(we_oe), .addra(addr_oe), .dina(din_oe), .douta(dout_oe));
  sram_32x512_i feature_oo (.clka(clk), .ena(1'b1), .wea(we_oo), .addra(addr_oo), .dina(din_oo), .douta(dout_oo));
  
  // Bias BRAM
  // sram 32x256
  wire we_bias;
  wire [7:0] addr_bias;
  wire [31:0] din_bias;
  wire [31:0] dout_bias;
  sram_32x256 bias_ram (.clka(clk), .ena(1'b1), .wea(we_bias), .addra(addr_bias), .dina(din_bias), .douta(dout_bias));
    
  // Weight BRAM (interleaved weight)
  // sram 32x256 (byte-wise write enable)
  wire [3:0] we_w0r0, we_w0r1, we_w0r2;
  wire [7:0] addr_w0r0, addr_w0r1, addr_w0r2;
  wire [31:0] din_w0r0, din_w0r1, din_w0r2;
  wire [31:0] dout_w0r0, dout_w0r1, dout_w0r2;
  sram_32x256_i weight_0_row_0 (.clka(clk), .ena(1'b1), .wea(we_w0r0), .addra(addr_w0r0), .dina(din_w0r0), .douta(dout_w0r0));
  sram_32x256_i weight_0_row_1 (.clka(clk), .ena(1'b1), .wea(we_w0r1), .addra(addr_w0r1), .dina(din_w0r1), .douta(dout_w0r1));
  sram_32x256_i weight_0_row_2 (.clka(clk), .ena(1'b1), .wea(we_w0r2), .addra(addr_w0r2), .dina(din_w0r2), .douta(dout_w0r2));
  
  // Accumulator BRAM
  wire wea_a_ee, wea_a_eo, wea_a_oe, wea_a_oo;
  wire [8:0] addra_a_ee, addra_a_eo, addra_a_oe, addra_a_oo;
  wire [8:0] addrb_a_ee, addrb_a_eo, addrb_a_oe, addrb_a_oo;
  wire [63:0] dina_a_ee, dina_a_eo, dina_a_oe, dina_a_oo;
  wire [63:0] doutb_a_ee, doutb_a_eo, doutb_a_oe, doutb_a_oo;
  sram_64x512_d accumulator_ee (.clka(clk), .clkb(clk), .ena(1'b1), .enb(1'b1),
  .addra(addra_a_ee), .addrb(addrb_a_ee), .wea(wea_a_ee), .dina(dina_a_ee), .doutb(doutb_a_ee));
  sram_64x512_d accumulator_eo (.clka(clk), .clkb(clk), .ena(1'b1), .enb(1'b1),
  .addra(addra_a_eo), .addrb(addrb_a_eo), .wea(wea_a_eo), .dina(dina_a_eo), .doutb(doutb_a_eo));
  sram_64x512_d accumulator_oe (.clka(clk), .clkb(clk), .ena(1'b1), .enb(1'b1),
  .addra(addra_a_oe), .addrb(addrb_a_oe), .wea(wea_a_oe), .dina(dina_a_oe), .doutb(doutb_a_oe));
  sram_64x512_d accumulator_oo (.clka(clk), .clkb(clk), .ena(1'b1), .enb(1'b1),
  .addra(addra_a_oo), .addrb(addrb_a_oo), .wea(wea_a_oo), .dina(dina_a_oo), .doutb(doutb_a_oo));

  // Result BRAM
  wire wea_o_e, wea_o_o;
  wire [11:0] addra_o_e, addra_o_o;
  wire [11:0] addrb_o_e, addrb_o_o;
  wire [31:0] dina_o_e, dina_o_o;
  wire [31:0] doutb_o_e, doutb_o_o;
  sram_32x4096_d result_e (.clka(clk), .clkb(clk), .ena(1'b1), .enb(1'b1),
  .addra(addra_o_e), .addrb(addrb_o_e), .wea(wea_o_e), .dina(dina_o_e), .doutb(doutb_o_e));
  sram_32x4096_d result_o (.clka(clk), .clkb(clk), .ena(1'b1), .enb(1'b1),
  .addra(addra_o_o), .addrb(addrb_o_o), .wea(wea_o_o), .dina(dina_o_o), .doutb(doutb_o_o));

  ////////////////////////////////////////////////////////////////////////////
  // parameters
  ////////////////////////////////////////////////////////////////////////////
  // FSM state declaration
  localparam [3:0] IDLE           = 4'd0,
                   WAIT_CMD       = 4'd1,
                   S_FEATURE_RECV = 4'd2,
                   S_BIAS_RECV    = 4'd3,
                   S_WEIGHT_RECV  = 4'd4,
                   COMPUTE        = 4'd5,
                   QUANTIZE       = 4'd6,
                   M_RESULT_SEND  = 4'd7,
                   DONE           = 4'd8;
  
  reg [3:0] state, next_state;
  reg [7:0] feature_ch, output_ch;
  (* max_fanout = 8 *) reg [5:0] feature_row, feature_col;
      
  // RAM 주소 및 AXI 데이터 카운터
  
  // 연산 완료 신호 (내부용)
  wire computation_finished;
  wire channel_finished;
  wire quantize_finished;
  
  // 마지막으로 수행한 명령을 기억하는 변수
  reg [2:0] last_command;
  
  // 마지막 완료된 명령 기록 (중복 실행 방지용)
  always @(posedge clk) begin
    if (!rstn) begin
      last_command <= 3'd0;
    end else begin
      // Feature 수신 완료 시 기록
      if (state == S_FEATURE_RECV && s_axis_tready_reg && S_AXIS_TVALID && S_AXIS_TLAST)
        last_command <= 3'd1;
      // Bias, Weight 수신 완료 시 기록
      else if (state == S_BIAS_RECV && s_axis_tready_reg && S_AXIS_TVALID && S_AXIS_TLAST)
        last_command <= 3'd2;
      // 연산 완료 시 기록
      else if (computation_finished)
        last_command <= 3'd3;
      // APB 초기화 시 초기화
      else if (!conv_start)
        last_command <= 3'd0;
    end
  end
  
  ////////////////////////////////////////////////////////////////////////////
  // FSM Logic
  ////////////////////////////////////////////////////////////////////////////
  reg is_last_feature_recv;
  reg [3:0] recv_mod_9;

  // FSM process 1 : state Transition
  always @(posedge clk or negedge rstn) begin
    if (!rstn) begin
      state <= IDLE;
    end
    else begin
      state <= next_state;
    end
  end
  
  // FSM process 2 : Next state logic
  always @(*) begin
    next_state = state;
    
    case (state)
      IDLE: begin
        next_state = WAIT_CMD;
      end
      
      WAIT_CMD: begin
        // 현재 명령이 0이 아니고, 방금 끝낸 명령과 다를 때만 실행
        if (COMMAND != 3'd0 && COMMAND != last_command) begin
          case (COMMAND)
            3'd1: next_state = S_FEATURE_RECV;
            3'd2: next_state = S_BIAS_RECV;
            3'd3: next_state = S_WEIGHT_RECV;
            3'd4: next_state = M_RESULT_SEND;
            default: next_state = WAIT_CMD;
          endcase
        end
        else begin
          next_state = WAIT_CMD; // 이미 한 명령이면 대기
        end
      end
      
      S_FEATURE_RECV: begin
        // AXI Slave 핸드셰이킹 && 마지막 데이터 수신
        if (is_last_feature_recv) begin
          next_state = WAIT_CMD; // 수신 완료, 다시 명령 대기
        end
      end
      
      S_BIAS_RECV: begin
        if (s_is_handshake && S_AXIS_TLAST) begin
          next_state = WAIT_CMD; // 수신 완료, 다시 명령 대기
        end
      end
      
      S_WEIGHT_RECV: begin
        if (s_is_handshake && (feature_ch == InCh - 1) && recv_mod_9 >= 5) begin
          next_state = COMPUTE; // 수신 완료, 다시 명령 대기
        end
      end
      
      COMPUTE: begin
        if (channel_finished) begin
          next_state = QUANTIZE;
        end
      end

      QUANTIZE: begin
        if (computation_finished) begin // 연산 모듈이 완료 신호를 보낼 때까지 대기
          next_state = M_RESULT_SEND; // 연산 완료, 다시 명령 대기
        end
        else if (quantize_finished) begin
          next_state = S_WEIGHT_RECV;
        end
      end
      
      M_RESULT_SEND: begin
        // AXI Master 핸드셰이킹 && 마지막 데이터 전송
        if (m_axis_tvalid && M_AXIS_TREADY && m_axis_tlast) begin
          next_state = DONE; // 전송 완료
        end
      end
      
      DONE: begin
        if (!conv_start) begin // tb.v가 완료를 인지함
          next_state = IDLE;
        end
      end
      
      default: begin
        next_state = IDLE;
      end
    endcase
  end
  
  // FSM process 3 : Output Logic
  reg feature_recv_delay;
  
  always @(*) begin
    // default
    conv_done   = 1'b0;
    
    s_axis_tready_reg = 1'b0;
    
    case (state)
      IDLE: begin
        // 모든 출력 0
      end
      
      WAIT_CMD: begin
        // 모든 출력 0
      end
      
      S_FEATURE_RECV: begin
        s_axis_tready_reg = !feature_recv_delay; // 데이터 받을 준비 완료
      end
      
      S_BIAS_RECV: begin
        s_axis_tready_reg = 1'b1;
      end
      
      S_WEIGHT_RECV: begin
        s_axis_tready_reg = 1'b1;
      end
      
      DONE: begin
        conv_done = 1'b1; // 모든 작업 완료
      end
    endcase
  end

  ////////////////////////////////////////////////////////////////////////////
  // Common Index Logic
  ////////////////////////////////////////////////////////////////////////////
  reg [8:0] C_InCh, C_OutCh;
  (* max_fanout = 32 *) reg [5:0] C_FHeight;
  (* max_fanout = 32 *) reg [5:0] C_FWidth;
  reg [5:0] C_FHeight_m1, C_FHeight_m2;
  reg [10:0] C_FArea;
  reg [11:0] addr_result_base;
  reg [7:0] addr_result_row;

  wire is_last_col_recv = (feature_col[5:2] == (C_FWidth[5:2] - 1));
  wire is_last_row_recv = (feature_row == C_FHeight_m1);
  wire is_queue_full;

  always @(posedge clk) begin
    if (!rstn) begin
      output_ch <= 0;
      feature_ch <= 0;
      feature_row <= 0;
      feature_col <= 0;
      feature_recv_delay <= 0;
      is_last_feature_recv <= 0;
      F_writedone <= 1'b0;
      B_writedone <= 1'b0;
      rdy_to_transmit <= 1'b0;
      C_InCh <= 0;
      C_OutCh <= 0;
      C_FWidth <= 0;
      C_FHeight <= 0;
      C_FHeight_m1 <= 0;
      C_FHeight_m2 <= 0;
      C_FArea <= 0;
      addr_result_base <= 0;
      addr_result_row <= 0;
    end
    else begin
      // Feature RAM Write
      if (state == S_FEATURE_RECV) begin
        if (s_is_handshake && !is_last_col_recv) begin
          feature_col <= feature_col + 4;
        end
        else if (feature_recv_delay) begin
          feature_col <= 0;
          if (is_last_row_recv) begin
            feature_row <= 0;
            feature_ch <= feature_ch + 1;
          end
          else begin
            feature_row <= feature_row + 1;
          end
        end
        if (s_is_handshake && is_last_col_recv) begin
          feature_recv_delay <= 1'b1;
          if (feature_ch == InCh - 1 && is_last_row_recv) begin
            is_last_feature_recv <= 1'b1;
            F_writedone <= 1'b1;
          end
        end
        else begin
          feature_recv_delay <= 1'b0;
          is_last_feature_recv <= 1'b0;
        end
      end
      else if (state == S_BIAS_RECV) begin
        if (s_is_handshake)
          if (!S_AXIS_TLAST)
            output_ch <= output_ch + 4;
          else begin
            output_ch <= 0;
            B_writedone <= 1'b1;
          end
        feature_ch <= 0;
        feature_row <= 0;
        feature_col <= 0;
      end
      else if (state == S_WEIGHT_RECV) begin
        if (s_is_handshake && recv_mod_9 >= 5) begin
          if (feature_ch == InCh - 1)
            feature_ch <= 0;
          else
            feature_ch <= feature_ch + 1;
        end
        feature_row <= 0;
        feature_col <= 0;
      end
      else if (state == COMPUTE) begin
        if (feature_col != C_FWidth - 2) begin
          feature_col <= feature_col + 2;
        end
        else if (feature_row != C_FHeight_m2) begin
          feature_col <= 0;
          feature_row <= feature_row + 2;
        end
        else if (feature_ch != InCh - 1) begin
          feature_col <= 0;
          feature_row <= 0;
          feature_ch <= feature_ch + 1;
        end
        else begin
          feature_col <= 0;
          feature_row <= 0;
          feature_ch <= 0;
        end
      end
      else if (state == QUANTIZE) begin
        if (feature_col != C_FWidth - 4) begin
          feature_col <= feature_col + 4;
        end
        else if (feature_row != C_FHeight_m2) begin
          feature_col <= 0;
          feature_row <= feature_row + 2;
          addr_result_row <= addr_result_row + C_FWidth[5:2];
        end
        else if (!computation_finished) begin
          feature_col <= 0;
          feature_row <= 0;
          addr_result_base <= addr_result_base + C_FArea[10:3];
          addr_result_row <= 0;
          output_ch <= output_ch + 1;
        end
        else begin
          feature_col <= 0;
          feature_row <= 0;
          addr_result_base <= 0;
          addr_result_row <= 0;
          output_ch <= 0;
          rdy_to_transmit <= 1'b1;
        end
      end
      else if (state == M_RESULT_SEND) begin
        F_writedone <= 1'b0;
        B_writedone <= 1'b0;
        rdy_to_transmit <= 1'b0;
        if (!is_queue_full) begin
          if (feature_col != C_FWidth - 4) begin
            feature_col <= feature_col + 4;
          end
          else if (feature_row != C_FHeight_m1) begin
            feature_col <= 0;
            feature_row <= feature_row + 1;
            if (feature_row[0])
              addr_result_row <= addr_result_row + C_FWidth[5:2];
          end
          else if (output_ch != OutCh - 1) begin
            feature_col <= 0;
            feature_row <= 0;
            output_ch <= output_ch + 1;
            addr_result_base <= addr_result_base + C_FArea[10:3];
            addr_result_row <= 0;
          end
        end
      end
      else if (state == WAIT_CMD) begin
        if (next_state == S_FEATURE_RECV) begin
          C_InCh <= InCh;
          C_OutCh <= OutCh;
          C_FHeight <= FHeight;
          C_FHeight_m1 <= FHeight - 1;
          C_FHeight_m2 <= FHeight - 2;
          C_FWidth <= FWidth;
          C_FArea <= FHeight * FWidth;
        end
        output_ch <= 0;
        feature_ch <= 0;
        feature_row <= 0;
        feature_col <= 0;
        addr_result_base <= 0;
        addr_result_row <= 0;
      end
      else if (state == IDLE) begin // IDLE 상태에서 주소 초기화
        output_ch <= 0;
        feature_ch <= 0;
        feature_row <= 0;
        feature_col <= 0;
        C_InCh <= 0;
        C_OutCh <= 0;
        C_FHeight <= 0;
        C_FWidth <= 0;
        addr_result_base <= 0;
        addr_result_row <= 0;
      end
    end
  end
  
  ////////////////////////////////////////////////////////////////////////////
  // Feature RAM Logic
  ////////////////////////////////////////////////////////////////////////////
  wire [3:0] row_e, row_o, col_e, col_o;
  wire [7:0] pass_byte;
  reg [7:0] pass_byte_reg;
  
  assign addr_ee = feature_ch * C_FArea[10:4] + row_e * C_FWidth[5:2] + col_e;
  assign addr_eo = feature_ch * C_FArea[10:4] + row_e * C_FWidth[5:2] + col_o;
  assign addr_oe = feature_ch * C_FArea[10:4] + row_o * C_FWidth[5:2] + col_e;
  assign addr_oo = feature_ch * C_FArea[10:4] + row_o * C_FWidth[5:2] + col_o;
  
  // Conv 연산시 stride (0, 2) / (2, 0)로 간단하게 읽어올 수 있도록 신경써서 구성
  assign row_e = (feature_row[5:1] == C_FHeight_m2[5:1]) ? 0 : (feature_row[5:1] + 1) / 2;
  assign row_o = feature_row[5:2];
  assign col_e = (feature_col[5:1] == C_FWidth[5:1] - 1) || feature_recv_delay ? 0 : col_o;
  assign col_o = (feature_col[5:1] + 1) / 2;
  
  // 251127 - 가장 간단한 버전
  // TODO: Recv time overhead 1 + 4 / Width => 1 + (2 / Width) * (1 + 2 / Height)
  // TODO: Width = 4 일 때 Recv time overhead 2 => 1로 줄이기
  assign we_ee[3] = (state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd0) && s_is_handshake;
  assign we_ee[2] = (state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd0) && (s_is_handshake && feature_col != 0) ^ feature_recv_delay;
  assign we_ee[1] = (state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd3) && s_is_handshake;
  assign we_ee[0] = (state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd3) && (s_is_handshake && feature_col != 0) ^ feature_recv_delay;
  assign we_oe[3] = (state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd2) && s_is_handshake;
  assign we_oe[2] = (state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd2) && (s_is_handshake && feature_col != 0) ^ feature_recv_delay;
  assign we_oe[1] = (state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd1) && s_is_handshake;
  assign we_oe[0] = (state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd1) && (s_is_handshake && feature_col != 0) ^ feature_recv_delay;
  assign we_eo[3:2] = {2{(state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd0) && s_is_handshake}};
  assign we_eo[1:0] = {2{(state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd3) && s_is_handshake}};
  assign we_oo[3:2] = {2{(state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd2) && s_is_handshake}};
  assign we_oo[1:0] = {2{(state == S_FEATURE_RECV) && (feature_row[1:0] == 2'd1) && s_is_handshake}};

  assign din_ee = {2{S_AXIS_TDATA[7:0], pass_byte}};
  assign din_eo = {2{S_AXIS_TDATA[23:8]}};
  assign din_oe = {2{S_AXIS_TDATA[7:0], pass_byte}};
  assign din_oo = {2{S_AXIS_TDATA[23:8]}};
  
  assign pass_byte = pass_byte_reg;
  
  // latching
  always @(posedge clk) begin
    if (s_is_handshake)
      pass_byte_reg <= S_AXIS_TDATA[31:24];
  end
  
  ////////////////////////////////////////////////////////////////////////////
  // Bias RAM Logic
  ////////////////////////////////////////////////////////////////////////////
  assign addr_bias = output_ch[7:2];
  assign we_bias = (state == S_BIAS_RECV) && s_is_handshake;
  assign din_bias = S_AXIS_TDATA;
  
  ////////////////////////////////////////////////////////////////////////////
  // Weight RAM Logic
  ////////////////////////////////////////////////////////////////////////////

  // Modulo 9 Counter
  always @(posedge clk) begin
    if (!rstn) begin
      recv_mod_9 <= 4'd0;
    end
    else begin
      if (state == S_WEIGHT_RECV) begin
        if (s_is_handshake) begin
          case (recv_mod_9)
          4'd0: recv_mod_9 <= 4;
          4'd1: recv_mod_9 <= 5;
          4'd2: recv_mod_9 <= 6;
          4'd3: recv_mod_9 <= 7;
          4'd4: recv_mod_9 <= 8;
          4'd5: recv_mod_9 <= 0;
          4'd6: recv_mod_9 <= 1;
          4'd7: recv_mod_9 <= 2;
          4'd8: recv_mod_9 <= 3;
          default: recv_mod_9 <= 0;
          endcase
        end
      end
      else if (state == IDLE) begin
        recv_mod_9 <= 4'd0;
      end
    end
  end

  // interleave me
  assign addr_w0r0 = feature_ch + ((state == S_WEIGHT_RECV && recv_mod_9 >= 6)? 1 : 0);
  assign addr_w0r1 = feature_ch;
  assign addr_w0r2 = feature_ch;

  reg [71:0] din_interleaved;
  reg [23:0] pass_row;

  // prevent potential overflow
  assign we_w0r0[3] = 0;
  assign we_w0r0[2] = (state == S_WEIGHT_RECV) && s_is_handshake && (recv_mod_9 <= 2 || recv_mod_9 >= 8 || (recv_mod_9 <= 3 && feature_ch == 0)); // && !S_AXIS_TLAST;
  assign we_w0r0[1] = (state == S_WEIGHT_RECV) && s_is_handshake && (recv_mod_9 <= 1 || recv_mod_9 >= 7 || (recv_mod_9 <= 3 && feature_ch == 0)); // && !S_AXIS_TLAST;
  assign we_w0r0[0] = (state == S_WEIGHT_RECV) && s_is_handshake && (recv_mod_9 <= 0 || recv_mod_9 >= 6 || (recv_mod_9 <= 3 && feature_ch == 0)); // && !S_AXIS_TLAST;

  assign we_w0r1[3] = 0;
  assign we_w0r1[2] = (state == S_WEIGHT_RECV) && s_is_handshake && (recv_mod_9 <= 5) && (recv_mod_9 >= 2);
  assign we_w0r1[1] = (state == S_WEIGHT_RECV) && s_is_handshake && (recv_mod_9 <= 4) && (recv_mod_9 >= 1);
  assign we_w0r1[0] = (state == S_WEIGHT_RECV) && s_is_handshake && (recv_mod_9 <= 3);

  assign we_w0r2[3] = 0;
  assign we_w0r2[2] = (state == S_WEIGHT_RECV) && s_is_handshake && (recv_mod_9 <= 8) && (recv_mod_9 >= 5);
  assign we_w0r2[1] = (state == S_WEIGHT_RECV) && s_is_handshake && (recv_mod_9 <= 7) && (recv_mod_9 >= 4);
  assign we_w0r2[0] = (state == S_WEIGHT_RECV) && s_is_handshake && (recv_mod_9 <= 6) && (recv_mod_9 >= 3);

  // Weight Interleaving
  always @(*) begin
    case (recv_mod_9)
    4'd0: din_interleaved = {{40{1'bx}}, S_AXIS_TDATA[31:0]};
    4'd1: din_interleaved = {{32{1'bx}}, S_AXIS_TDATA[31:0], pass_row[23:16]};
    4'd2: din_interleaved = {{24{1'bx}}, S_AXIS_TDATA[31:0], pass_row[23:8]};
    4'd3: din_interleaved = {{16{1'bx}}, S_AXIS_TDATA[31:0], pass_row[23:0]};
    4'd4: din_interleaved = {{8{1'bx}}, S_AXIS_TDATA[31:0], {32{1'bx}}};
    4'd5: din_interleaved = {S_AXIS_TDATA[31:0], {40{1'bx}}};
    4'd6: din_interleaved = {S_AXIS_TDATA[23:0], {40{1'bx}}, S_AXIS_TDATA[31:24]};
    4'd7: din_interleaved = {S_AXIS_TDATA[15:0], {40{1'bx}}, S_AXIS_TDATA[31:16]};
    4'd8: din_interleaved = {S_AXIS_TDATA[7:0], {40{1'bx}}, S_AXIS_TDATA[31:8]};
    default: din_interleaved = {72{1'bx}};
    endcase
  end

  assign din_w0r0 = {8'b0, din_interleaved[23:0]};
  assign din_w0r1 = {8'b0, din_interleaved[47:24]};
  assign din_w0r2 = {8'b0, din_interleaved[71:48]};

  always @(posedge clk) begin
    if (s_is_handshake)
      pass_row <= S_AXIS_TDATA[31:8];
  end
  
  ////////////////////////////////////////////////////////////////////////////
  // Compute Control
  ////////////////////////////////////////////////////////////////////////////
  wire cycle0;
  // read RAM => fill buffer => dot product => accumulate / write RAM
  reg cycle1, cycle2, cycle3;

  assign cycle0 = (state == COMPUTE);

  always @(posedge clk) begin
    if (!rstn) begin
      cycle1 <= 1'b0;
      cycle2 <= 1'b0;
      cycle3 <= 1'b0;
    end
    else begin
      cycle1 <= cycle0;
      cycle2 <= cycle1;
      cycle3 <= cycle2;
    end
  end

  assign channel_finished = (feature_ch == InCh - 1) && (feature_row == C_FHeight_m2) && (feature_col == C_FWidth - 2);
  
  ////////////////////////////////////////////////////////////////////////////
  // Data Load & Store Logic
  ////////////////////////////////////////////////////////////////////////////
  reg [7:0] ch_cycle1, ch_cycle2, ch_cycle3;
  reg [4:0] row_cycle1, row_cycle2, row_cycle3;
  reg [4:0] col_cycle1, col_cycle2, col_cycle3;

  always @(posedge clk) begin
    if (!rstn) begin
      ch_cycle3 <= 1'b0; ch_cycle2 <= 1'b0; ch_cycle1 <= 1'b0;
      row_cycle3 <= 1'b0; row_cycle2 <= 1'b0; row_cycle1 <= 1'b0;
      col_cycle3 <= 1'b0; col_cycle2 <= 1'b0; col_cycle1 <= 1'b0;
    end
    else begin
      ch_cycle3 <= ch_cycle2; ch_cycle2 <= ch_cycle1; ch_cycle1 <= feature_ch;
      row_cycle3 <= row_cycle2; row_cycle2 <= row_cycle1; row_cycle1 <= feature_row;
      col_cycle3 <= col_cycle2; col_cycle2 <= col_cycle1; col_cycle1 <= feature_col;
    end
  end

  reg signed [7:0] feature_buffer [0:3] [0:3];
  reg signed [7:0] weight_buffer [0:2] [0:2];

  always @(posedge clk) begin
    if (cycle1) begin
      {weight_buffer[0][2], weight_buffer[0][1], weight_buffer[0][0]} <= dout_w0r0[23:0];
      {weight_buffer[1][2], weight_buffer[1][1], weight_buffer[1][0]} <= dout_w0r1[23:0];
      {weight_buffer[2][2], weight_buffer[2][1], weight_buffer[2][0]} <= dout_w0r2[23:0];

      // set left half of feature buffers
      if (col_cycle1 == 0) begin
        feature_buffer[0][0] <= 8'b0;
        feature_buffer[1][0] <= 8'b0;
        feature_buffer[2][0] <= 8'b0;
        feature_buffer[3][0] <= 8'b0;

        case (row_cycle1[1])
        1'b0: begin
          feature_buffer[0][1] <= (row_cycle1 == 0) ? 8'b0 : dout_ee[15:8];
          feature_buffer[1][1] <= dout_ee[31:24];
          feature_buffer[2][1] <= dout_oe[15:8];
          feature_buffer[3][1] <= dout_oe[31:24];
        end
        1'b1: begin
          feature_buffer[0][1] <= dout_oe[15:8];
          feature_buffer[1][1] <= dout_oe[31:24];
          feature_buffer[2][1] <= dout_ee[15:8];
          feature_buffer[3][1] <= (row_cycle1 == C_FHeight_m2) ? 8'b0 : dout_ee[31:24];
        end
        endcase
      end
      else begin
        {feature_buffer[0][1], feature_buffer[0][0]} <= {feature_buffer[0][3], feature_buffer[0][2]};
        {feature_buffer[1][1], feature_buffer[1][0]} <= {feature_buffer[1][3], feature_buffer[1][2]};
        {feature_buffer[2][1], feature_buffer[2][0]} <= {feature_buffer[2][3], feature_buffer[2][2]};
        {feature_buffer[3][1], feature_buffer[3][0]} <= {feature_buffer[3][3], feature_buffer[3][2]};
      end

      // set right half of feature buffers
      case ({row_cycle1[1], col_cycle1[1]})
      2'b00: begin // <eo, oo>
        {feature_buffer[0][3], feature_buffer[0][2]} <= (row_cycle1 == 0) ? 16'b0 : dout_eo[15:0];
        {feature_buffer[1][3], feature_buffer[1][2]} <= dout_eo[31:16];
        {feature_buffer[2][3], feature_buffer[2][2]} <= dout_oo[15:0];
        {feature_buffer[3][3], feature_buffer[3][2]} <= dout_oo[31:16];
      end
      2'b01: begin // <ee, oe>
        feature_buffer[0][3] <= (col_cycle1 == C_FWidth - 2) || (row_cycle1 == 0) ? 8'b0 : dout_ee[15:8];
        feature_buffer[1][3] <= (col_cycle1 == C_FWidth - 2) ? 8'b0 : dout_ee[31:24];
        feature_buffer[2][3] <= (col_cycle1 == C_FWidth - 2) ? 8'b0 : dout_oe[15:8];
        feature_buffer[3][3] <= (col_cycle1 == C_FWidth - 2) ? 8'b0 : dout_oe[31:24];
        feature_buffer[0][2] <= (row_cycle1 == 0) ? 8'b0 : dout_ee[7:0];
        feature_buffer[1][2] <= dout_ee[23:16];
        feature_buffer[2][2] <= dout_oe[7:0];
        feature_buffer[3][2] <= dout_oe[23:16];
      end
      2'b10: begin // <oo, eo>
        {feature_buffer[0][3], feature_buffer[0][2]} <= dout_oo[15:0];
        {feature_buffer[1][3], feature_buffer[1][2]} <= dout_oo[31:16];
        {feature_buffer[2][3], feature_buffer[2][2]} <= dout_eo[15:0];
        {feature_buffer[3][3], feature_buffer[3][2]} <= (row_cycle1 == C_FHeight_m2) ? 16'b0 : dout_eo[31:16];
      end
      2'b11: begin // <oe, ee>
        feature_buffer[0][2] <= dout_oe[7:0];
        feature_buffer[1][2] <= dout_oe[23:16];
        feature_buffer[2][2] <= dout_ee[7:0];
        feature_buffer[3][2] <= (row_cycle1 == C_FHeight_m2) ? 8'b0 : dout_ee[23:16];
        feature_buffer[0][3] <= (col_cycle1 == C_FWidth - 2) ? 8'b0 : dout_oe[15:8];
        feature_buffer[1][3] <= (col_cycle1 == C_FWidth - 2) ? 8'b0 : dout_oe[31:24];
        feature_buffer[2][3] <= (col_cycle1 == C_FWidth - 2) ? 8'b0 : dout_ee[15:8];
        feature_buffer[3][3] <= (col_cycle1 == C_FWidth - 2) || (row_cycle1 == C_FHeight_m2) ? 8'b0 : dout_ee[31:24];
      end
      endcase
    end
  end

  reg signed [31:0] accumulator [0:3]; // latching
  reg signed [17:0] conv_result [0:11]; // latching
  reg [7:0] bias_data;

  wire signed [31:0] bias_ext;
  (* use_dsp = "yes" *) wire [8:0] acc_addr;
  
  assign bias_ext = {{19{bias_data[7]}}, bias_data[6:0], {6{1'b0}}};

  always @(*) begin
    case (output_ch[1:0])
    2'd0: bias_data = dout_bias[7:0];
    2'd1: bias_data = dout_bias[15:8];
    2'd2: bias_data = dout_bias[23:16];
    2'd3: bias_data = dout_bias[31:24];
    endcase
  end

  assign acc_addr = row_cycle1[4:1] * C_FWidth[5:2] + col_cycle1[4:2];

  assign addrb_a_ee = acc_addr;
  assign addrb_a_eo = acc_addr;
  assign addrb_a_oe = acc_addr;
  assign addrb_a_oo = acc_addr;

  reg fwd_ee, fwd_eo, fwd_oe, fwd_oo;
  reg [63:0] latch_a_ee, latch_a_eo, latch_a_oe, latch_a_oo;

  always @(posedge clk) begin
    fwd_ee <= wea_a_ee && (addra_a_ee == addrb_a_ee);
    fwd_eo <= wea_a_eo && (addra_a_eo == addrb_a_eo);
    fwd_oe <= wea_a_oe && (addra_a_oe == addrb_a_oe);
    fwd_oo <= wea_a_oo && (addra_a_oo == addrb_a_oo);
    latch_a_ee <= dina_a_ee;
    latch_a_eo <= dina_a_eo;
    latch_a_oe <= dina_a_oe;
    latch_a_oo <= dina_a_oo;
  end

  // Forwarding MUXWires
  wire [63:0] sum_data_ee, sum_data_eo, sum_data_oe, sum_data_oo;

  // Logic: (Write Enable) && (Write Addr == Read Addr) ? Bypass : BRAM Read
  // 생각해 보니까 write first 쓰면 될 거 굳이 MUX로 구현한 것 같네요 - 영민, 25/12/06 21:55
  // 하지만 이미 짜버렸으니 어쩔 수 없죠
  // 덕분에 BRAM collision에 대해 공부하게 되었습니다.
  assign sum_data_ee = fwd_ee ? latch_a_ee : doutb_a_ee;
  assign sum_data_eo = fwd_eo ? latch_a_eo : doutb_a_eo;
  assign sum_data_oe = fwd_oe ? latch_a_oe : doutb_a_oe;
  assign sum_data_oo = fwd_oo ? latch_a_oo : doutb_a_oo;

  always @(posedge clk) begin
    if (cycle2) begin
      if (ch_cycle2 == 0) begin
        accumulator[0] <= bias_ext;
        accumulator[1] <= bias_ext;
        accumulator[2] <= bias_ext;
        accumulator[3] <= bias_ext;
      end
      else begin
        {accumulator[1], accumulator[0]} <= col_cycle2[1] ? sum_data_eo : sum_data_ee;
        {accumulator[3], accumulator[2]} <= col_cycle2[1] ? sum_data_oo : sum_data_oe;
      end
    end
  end

  wire [31:0] final_sum [0:3];

  assign final_sum[0] = conv_result[0] + conv_result[1] + conv_result[2] + accumulator[0];
  assign final_sum[1] = conv_result[3] + conv_result[4] + conv_result[5] + accumulator[1];
  assign final_sum[2] = conv_result[6] + conv_result[7] + conv_result[8] + accumulator[2];
  assign final_sum[3] = conv_result[9] + conv_result[10] + conv_result[11] + accumulator[3];

  (* use_dsp = "yes" *) wire [8:0] sum_addr;

  assign sum_addr = row_cycle3[4:1] * C_FWidth[5:2] + col_cycle3[4:2];

  assign addra_a_ee = sum_addr;
  assign addra_a_eo = sum_addr;
  assign addra_a_oe = sum_addr;
  assign addra_a_oo = sum_addr;

  assign wea_a_ee = cycle3 && !col_cycle3[1];
  assign wea_a_eo = cycle3 && col_cycle3[1];
  assign wea_a_oe = cycle3 && !col_cycle3[1];
  assign wea_a_oo = cycle3 && col_cycle3[1];

  assign dina_a_ee = {final_sum[1], final_sum[0]};
  assign dina_a_eo = {final_sum[1], final_sum[0]};
  assign dina_a_oe = {final_sum[3], final_sum[2]};
  assign dina_a_oo = {final_sum[3], final_sum[2]};

  ////////////////////////////////////////////////////////////////////////////
  // Compute Logic
  ////////////////////////////////////////////////////////////////////////////
  (* use_dsp = "yes" *) wire signed [17:0] conv_product [0:11];
  assign conv_product[0] =  feature_buffer[0][0] * weight_buffer[0][0] + feature_buffer[0][1] * weight_buffer[0][1] + feature_buffer[0][2] * weight_buffer[0][2];
  assign conv_product[1] =  feature_buffer[1][0] * weight_buffer[1][0] + feature_buffer[1][1] * weight_buffer[1][1] + feature_buffer[1][2] * weight_buffer[1][2];
  assign conv_product[2] =  feature_buffer[2][0] * weight_buffer[2][0] + feature_buffer[2][1] * weight_buffer[2][1] + feature_buffer[2][2] * weight_buffer[2][2];
  assign conv_product[3] =  feature_buffer[0][1] * weight_buffer[0][0] + feature_buffer[0][2] * weight_buffer[0][1] + feature_buffer[0][3] * weight_buffer[0][2];
  assign conv_product[4] =  feature_buffer[1][1] * weight_buffer[1][0] + feature_buffer[1][2] * weight_buffer[1][1] + feature_buffer[1][3] * weight_buffer[1][2];
  assign conv_product[5] =  feature_buffer[2][1] * weight_buffer[2][0] + feature_buffer[2][2] * weight_buffer[2][1] + feature_buffer[2][3] * weight_buffer[2][2];
  assign conv_product[6] =  feature_buffer[1][0] * weight_buffer[0][0] + feature_buffer[1][1] * weight_buffer[0][1] + feature_buffer[1][2] * weight_buffer[0][2];
  assign conv_product[7] =  feature_buffer[2][0] * weight_buffer[1][0] + feature_buffer[2][1] * weight_buffer[1][1] + feature_buffer[2][2] * weight_buffer[1][2];
  assign conv_product[8] =  feature_buffer[3][0] * weight_buffer[2][0] + feature_buffer[3][1] * weight_buffer[2][1] + feature_buffer[3][2] * weight_buffer[2][2];
  assign conv_product[9] =  feature_buffer[1][1] * weight_buffer[0][0] + feature_buffer[1][2] * weight_buffer[0][1] + feature_buffer[1][3] * weight_buffer[0][2];
  assign conv_product[10] = feature_buffer[2][1] * weight_buffer[1][0] + feature_buffer[2][2] * weight_buffer[1][1] + feature_buffer[2][3] * weight_buffer[1][2];
  assign conv_product[11] = feature_buffer[3][1] * weight_buffer[2][0] + feature_buffer[3][2] * weight_buffer[2][1] + feature_buffer[3][3] * weight_buffer[2][2];
  
  always @(posedge clk) begin
    if (cycle2) begin
      conv_result[0] <= conv_product[0];
      conv_result[1] <= conv_product[1];
      conv_result[2] <= conv_product[2];
      conv_result[3] <= conv_product[3];
      conv_result[4] <= conv_product[4];
      conv_result[5] <= conv_product[5];
      conv_result[6] <= conv_product[6];
      conv_result[7] <= conv_product[7];
      conv_result[8] <= conv_product[8];
      conv_result[9] <= conv_product[9];
      conv_result[10] <= conv_product[10];
      conv_result[11] <= conv_product[11];
    end
  end
  
  ////////////////////////////////////////////////////////////////////////////
  // Quantize Control
  ////////////////////////////////////////////////////////////////////////////
  wire quant0;
  // read RAM => fill buffer => dot product => accumulate / write RAM
  reg quant1, quant2;

  assign quant0 = (state == QUANTIZE);

  always @(posedge clk) begin
    if (!rstn) begin
      quant1 <= 1'b0;
      quant2 <= 1'b0;
    end
    else begin
      quant1 <= quant0;
      quant2 <= quant1;
    end
  end

  wire [11:0] result_addr;
  reg [11:0] dest_d1, dest_d2;

  assign result_addr = addr_result_base + addr_result_row + feature_col[5:2];

  always @(posedge clk) begin
    if (!rstn) begin
      dest_d1 <= 1'b0;
      dest_d2 <= 1'b0;
    end
    else begin
      dest_d1 <= result_addr;
      dest_d2 <= dest_d1;
    end
  end

  assign addra_o_e = dest_d2;
  assign addra_o_o = dest_d2;

  assign wea_o_e = quant2;
  assign wea_o_o = quant2;

  assign quantize_finished = (feature_row == C_FHeight_m2) && (feature_col == C_FWidth - 4) && (state == QUANTIZE);
  assign computation_finished = quantize_finished && (output_ch == OutCh - 1);  

  ////////////////////////////////////////////////////////////////////////////
  // Quantize Logic
  ////////////////////////////////////////////////////////////////////////////
  wire [31:0] sum_internal [0:7];
  reg [7:0] quantize_relu [0:7];

  assign {sum_internal[1], sum_internal[0]} = sum_data_ee;
  assign {sum_internal[3], sum_internal[2]} = sum_data_eo;
  assign {sum_internal[5], sum_internal[4]} = sum_data_oe;
  assign {sum_internal[7], sum_internal[6]} = sum_data_oo;

  genvar i;
  generate
    for (i = 0; i < 8; i = i + 1) begin
      always @(*) begin
        if (sum_internal[i][31])
          quantize_relu[i] = 8'h00;
        else if (sum_internal[i][30:13] != {18{1'b0}})
          quantize_relu[i] = 8'h7f;
        else
          quantize_relu[i] = {1'b0, sum_internal[i][12:6]};
      end
    end
  endgenerate

  assign dina_o_e = {quantize_relu[3], quantize_relu[2], quantize_relu[1], quantize_relu[0]};
  assign dina_o_o = {quantize_relu[7], quantize_relu[6], quantize_relu[5], quantize_relu[4]};

  ////////////////////////////////////////////////////////////////////////////
  // Output Logic 
  ////////////////////////////////////////////////////////////////////////////

  // TODO: Handshake 완성하기 (BRAM latency 고려)
  // (중요!!!)

  wire send0, last0, is_odd0;
  reg  send1, last1, is_odd1;
  reg  queue_last;

  reg [1:0] load_factor_reg, load_factor_next;
  reg [C_S00_AXIS_TDATA_WIDTH-1:0] output_queue;

  // queue occupancy flag (1-word skid buffer)
  reg queue_valid;

  // BRAM read 요청 (send0): is_queue_full이 false면 BRAM addr next로 넘어감
  assign send0 = (state == M_RESULT_SEND) && !is_queue_full;
  assign last0 = send0 && (output_ch == OutCh - 1) && 
                (feature_row == C_FHeight_m1) && (feature_col == C_FWidth - 4);

  assign is_odd0   = feature_row[0];

  wire [C_S00_AXIS_TDATA_WIDTH-1:0] bram_data;
  assign bram_data = is_odd1 ? doutb_o_o : doutb_o_e;

  // 현재 outstanding word 개수가 2이고, 이번 cycle에 handshake가 없으면 "더 못 받는다"
  // → 이때 is_queue_full = 1 -> send0 = 0 -> BRAM address 증가 차단
  assign is_queue_full = (load_factor_reg == 2'd2) && !m_is_handshake;

  always @(posedge clk) begin
    if (!rstn) begin
      load_factor_reg <= 2'd0;
    end
    else begin
      load_factor_reg <= load_factor_next;
    end
  end

  // load_factor_reg 의미: front + queue + "BRAM in-flight" word 개수 (0~2)
  // - send0 = 1 → +1
  // - handshake = 1 → -1
  // - 둘 다 1이면 변화 없음
  always @(*) begin
    load_factor_next = load_factor_reg;

    case ({send0, m_is_handshake})
      2'b10: begin
        // 새 BRAM read만 발생
        if (load_factor_reg < 2'd2)
          load_factor_next = load_factor_reg + 2'd1;
      end
      2'b01: begin
        // sink에서만 word 소비
        if (load_factor_reg > 2'd0)
          load_factor_next = load_factor_reg - 2'd1;
      end
      default: begin
        // 00 또는 11 -> 변화 없음
        load_factor_next = load_factor_reg;
      end
    endcase
  end

  always @(posedge clk) begin
    if (!rstn) begin
      send1   <= 1'b0;
      last1   <= 1'b0;
      is_odd1 <= 1'b0;
    end
    else begin
      send1 <= send0;
      last1 <= last0;
      if (send0)
        is_odd1 <= is_odd0;
    end
  end

  assign addrb_o_e = result_addr;
  assign addrb_o_o = result_addr;

    // next state 변수
  reg [C_S00_AXIS_TDATA_WIDTH-1:0] m_axis_tdata_next;
  reg                              m_axis_tvalid_next;
  reg                              m_axis_tlast_next;

  reg [C_S00_AXIS_TDATA_WIDTH-1:0] output_queue_next;
  reg                              queue_last_next;
  reg                              queue_valid_next;

  always @(posedge clk) begin
    if (!rstn) begin
      m_axis_tdata_reg <= {C_S00_AXIS_TDATA_WIDTH{1'b0}};
      m_axis_tvalid    <= 1'b0;
      m_axis_tlast     <= 1'b0;

      output_queue     <= {C_S00_AXIS_TDATA_WIDTH{1'b0}};
      queue_last       <= 1'b0;
      queue_valid      <= 1'b0;
    end
    else begin
      // 기본값: 유지
      m_axis_tdata_next  = m_axis_tdata_reg;
      m_axis_tvalid_next = m_axis_tvalid;
      m_axis_tlast_next  = m_axis_tlast;

      output_queue_next  = output_queue;
      queue_last_next    = queue_last;
      queue_valid_next   = queue_valid;

      // 1) handshake 발생 시: front pop + queue shift
      if (m_is_handshake) begin
        if (queue_valid) begin
          // queue -> front로 당김
          m_axis_tdata_next  = output_queue;
          m_axis_tlast_next  = queue_last;
          m_axis_tvalid_next = 1'b1;

          queue_valid_next   = 1'b0;
        end
        else begin
          // queue 비어 있으면 front 비움
          m_axis_tvalid_next = 1'b0;
        end
      end

      // 2) BRAM에서 새 word 도착 (send1=1) 시: push
      if (send1) begin
        if (!m_axis_tvalid_next) begin
          // front 비어 있으면 바로 front로
          m_axis_tdata_next  = bram_data;
          m_axis_tlast_next  = last1;
          m_axis_tvalid_next = 1'b1;
        end
        else if (!queue_valid_next) begin
          // front는 차 있고, queue가 비었으면 queue로
          output_queue_next  = bram_data;
          queue_last_next    = last1;
          queue_valid_next   = 1'b1;
        end
      end

      // 실제 레지스터 업데이트
      m_axis_tdata_reg <= m_axis_tdata_next;
      m_axis_tvalid    <= m_axis_tvalid_next;
      m_axis_tlast     <= m_axis_tlast_next;

      output_queue     <= output_queue_next;
      queue_last       <= queue_last_next;
      queue_valid      <= queue_valid_next;
    end
  end

  assign debug_state = state;

endmodule
