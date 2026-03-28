// Copyright 2026 Vyges Inc.
// SPDX-License-Identifier: Apache-2.0
//
// vyges-gpio-lite: Lightweight GPIO peripheral with TL-UL slave interface.
// Configurable pin count, per-pin direction, per-pin edge interrupts.

`ifndef GPIO_LITE_SV
`define GPIO_LITE_SV

module gpio_lite
  import tlul_pkg::*;
#(
  parameter int unsigned NUM_PINS = 32
) (
  input  logic                 clk_i,
  input  logic                 rst_ni,

  // TL-UL device port
  input  tlul_pkg::tl_h2d_t   tl_i,
  output tlul_pkg::tl_d2h_t   tl_o,

  // GPIO pins
  input  logic [NUM_PINS-1:0]  gpio_i,
  output logic [NUM_PINS-1:0]  gpio_o,
  output logic [NUM_PINS-1:0]  gpio_oe_o,

  // Interrupt output (active high)
  output logic                 intr_gpio_o
);

  // ---------------------------------------------------------------------------
  // Register offsets
  // ---------------------------------------------------------------------------
  localparam logic [7:0] ADDR_DATA_OUT  = 8'h00;
  localparam logic [7:0] ADDR_DATA_IN   = 8'h04;
  localparam logic [7:0] ADDR_DIR       = 8'h08;
  localparam logic [7:0] ADDR_INTR_EN   = 8'h0C;
  localparam logic [7:0] ADDR_INTR_RISE = 8'h10;
  localparam logic [7:0] ADDR_INTR_FALL = 8'h14;
  localparam logic [7:0] ADDR_INTR_ST   = 8'h18;
  localparam logic [7:0] ADDR_OUT_SET   = 8'h1C;
  localparam logic [7:0] ADDR_OUT_CLR   = 8'h20;

  // ---------------------------------------------------------------------------
  // Registers
  // ---------------------------------------------------------------------------
  logic [NUM_PINS-1:0] reg_data_out;
  logic [NUM_PINS-1:0] reg_dir;
  logic [NUM_PINS-1:0] reg_intr_en;
  logic [NUM_PINS-1:0] reg_intr_rise;
  logic [NUM_PINS-1:0] reg_intr_fall;
  logic [NUM_PINS-1:0] reg_intr_st;

  // ---------------------------------------------------------------------------
  // 2-FF input synchronizer
  // ---------------------------------------------------------------------------
  logic [NUM_PINS-1:0] gpio_sync_q1, gpio_sync_q2;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gpio_sync_q1 <= '0;
      gpio_sync_q2 <= '0;
    end else begin
      gpio_sync_q1 <= gpio_i;
      gpio_sync_q2 <= gpio_sync_q1;
    end
  end

  // ---------------------------------------------------------------------------
  // Edge detection
  // ---------------------------------------------------------------------------
  logic [NUM_PINS-1:0] gpio_prev;
  logic [NUM_PINS-1:0] rise_detect, fall_detect;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gpio_prev <= '0;
    end else begin
      gpio_prev <= gpio_sync_q2;
    end
  end

  assign rise_detect = gpio_sync_q2 & ~gpio_prev;
  assign fall_detect = ~gpio_sync_q2 & gpio_prev;

  // ---------------------------------------------------------------------------
  // TL-UL bus decode
  // ---------------------------------------------------------------------------
  logic        tl_req;
  logic        tl_we;
  logic [31:0] tl_addr;
  logic [31:0] tl_wdata;
  logic [3:0]  tl_be;

  assign tl_req   = tl_i.a_valid;
  assign tl_we    = (tl_i.a_opcode == PutFullData) || (tl_i.a_opcode == PutPartialData);
  assign tl_addr  = tl_i.a_address;
  assign tl_wdata = tl_i.a_data;
  assign tl_be    = tl_i.a_mask;

  // Address byte-select (lower 8 bits, word-aligned)
  logic [7:0] addr_sel;
  assign addr_sel = tl_addr[7:0];

  // ---------------------------------------------------------------------------
  // Register read
  // ---------------------------------------------------------------------------
  logic [31:0] rdata;

  always_comb begin
    rdata = 32'h0;
    unique case (addr_sel)
      ADDR_DATA_OUT:  rdata = {{(32-NUM_PINS){1'b0}}, reg_data_out};
      ADDR_DATA_IN:   rdata = {{(32-NUM_PINS){1'b0}}, gpio_sync_q2};
      ADDR_DIR:       rdata = {{(32-NUM_PINS){1'b0}}, reg_dir};
      ADDR_INTR_EN:   rdata = {{(32-NUM_PINS){1'b0}}, reg_intr_en};
      ADDR_INTR_RISE: rdata = {{(32-NUM_PINS){1'b0}}, reg_intr_rise};
      ADDR_INTR_FALL: rdata = {{(32-NUM_PINS){1'b0}}, reg_intr_fall};
      ADDR_INTR_ST:   rdata = {{(32-NUM_PINS){1'b0}}, reg_intr_st};
      ADDR_OUT_SET:   rdata = 32'h0; // write-only
      ADDR_OUT_CLR:   rdata = 32'h0; // write-only
      default:        rdata = 32'h0;
    endcase
  end

  // ---------------------------------------------------------------------------
  // Register write
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      reg_data_out <= '0;
      reg_dir      <= '0;
      reg_intr_en  <= '0;
      reg_intr_rise<= '0;
      reg_intr_fall<= '0;
      reg_intr_st  <= '0;
    end else begin
      // Set interrupt status from edge detection (always, regardless of bus)
      reg_intr_st <= reg_intr_st
                   | (rise_detect & reg_intr_rise)
                   | (fall_detect & reg_intr_fall);

      if (tl_req && tl_we) begin
        unique case (addr_sel)
          ADDR_DATA_OUT:  reg_data_out <= tl_wdata[NUM_PINS-1:0];
          // DATA_IN is read-only
          ADDR_DIR:       reg_dir      <= tl_wdata[NUM_PINS-1:0];
          ADDR_INTR_EN:   reg_intr_en  <= tl_wdata[NUM_PINS-1:0];
          ADDR_INTR_RISE: reg_intr_rise<= tl_wdata[NUM_PINS-1:0];
          ADDR_INTR_FALL: reg_intr_fall<= tl_wdata[NUM_PINS-1:0];
          ADDR_INTR_ST: begin
            // Write-1-to-clear: clear bits where wdata is 1, preserve new edges
            reg_intr_st <= (reg_intr_st & ~tl_wdata[NUM_PINS-1:0])
                         | (rise_detect & reg_intr_rise)
                         | (fall_detect & reg_intr_fall);
          end
          ADDR_OUT_SET:   reg_data_out <= reg_data_out | tl_wdata[NUM_PINS-1:0];
          ADDR_OUT_CLR:   reg_data_out <= reg_data_out & ~tl_wdata[NUM_PINS-1:0];
          default: ;
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Interrupt output
  // ---------------------------------------------------------------------------
  assign intr_gpio_o = |(reg_intr_st & reg_intr_en);

  // ---------------------------------------------------------------------------
  // GPIO output / output-enable
  // ---------------------------------------------------------------------------
  assign gpio_o    = reg_data_out;
  assign gpio_oe_o = reg_dir;

  // ---------------------------------------------------------------------------
  // TL-UL response (single-cycle, always ready)
  // ---------------------------------------------------------------------------
  logic rsp_valid_q;
  logic rsp_we_q;
  logic [31:0] rsp_data_q;
  logic [7:0]  rsp_source_q;
  logic [1:0]  rsp_size_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rsp_valid_q  <= 1'b0;
      rsp_we_q     <= 1'b0;
      rsp_data_q   <= 32'h0;
      rsp_source_q <= 8'h0;
      rsp_size_q   <= 2'h0;
    end else begin
      rsp_valid_q  <= tl_req;
      rsp_we_q     <= tl_we;
      rsp_data_q   <= rdata;
      rsp_source_q <= tl_i.a_source;
      rsp_size_q   <= tl_i.a_size;
    end
  end

  assign tl_o.d_valid  = rsp_valid_q;
  assign tl_o.d_opcode = rsp_we_q ? AccessAck : AccessAckData;
  assign tl_o.d_param  = '0;
  assign tl_o.d_size   = rsp_size_q;
  assign tl_o.d_source = rsp_source_q;
  assign tl_o.d_sink   = '0;
  assign tl_o.d_data   = rsp_data_q;
  assign tl_o.d_user   = '0;
  assign tl_o.d_error  = 1'b0;
  assign tl_o.a_ready  = 1'b1; // always accept

endmodule

`endif // GPIO_LITE_SV
