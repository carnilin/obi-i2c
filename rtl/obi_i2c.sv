`timescale 1ns/1ns

module obi_i2c (
    input  logic clk_i,
    input  logic rstn_i,

    input  logic                    obi_areq_i,
    output logic                    obi_agnt_o,
    input  logic [ADDR_WIDTH-1:0]   obi_aaddr_i,
    input  logic [DATA_WIDTH-1:0]   obi_awdata_i,

    input  logic                    obi_awe_i,
    input  logic [DATA_WIDTH/8-1:0] obi_abe_i,

    output logic                    obi_rvalid_o,
    input  logic                    obi_rready_i,
    output logic [DATA_WIDTH-1:0]   obi_rdata_o,
    output logic                    obi_rerr_o    // TIED OFF
    );

    // NOT A GLOBAL PARAMETER FOR SAFETY REASONS
    localparam integer DATA_WIDTH = 32;
    localparam integer ADDR_WIDTH = 32;

    // REGISTER OFFSETS
    localparam integer I2C_STATUS_REG = 0;
    localparam integer I2C_DATA_REG   = 4;
    localparam integer I2C_SPEED_REG  = 8;

    // WRAPPER REGISTERS 
    logic [DATA_WIDTH-1:0] i2c_status_reg; // read-only
    logic [DATA_WIDTH-1:0] i2c_data_reg;
    logic [DATA_WIDTH-1:0] i2c_speed_reg;

    // OBI STATE FSM
    typedef enum logic {
        ADDR,
        RESP
    } obi_state_t;
    obi_state_t state_reg, state_next;

    always_ff @(posedge clk_i)
        state_reg <= state_next;

    logic obi_a_fire;
    logic obi_r_fire;

    assign obi_a_fire = obi_agnt_o   && obi_areq_i;
    assign obi_r_fire = obi_rvalid_o && obi_rready_i;

    always_comb begin
        state_next = state_reg;
        case (state_reg)
            ADDR: begin
                if (obi_a_fire)
                    state_next = RESP;
            end
            RESP: begin
                if (obi_r_fire)
                    state_next = ADDR;
            end
        endcase
    end

    // OBI ERROR
    assign obi_rerr_o = 1'b0;

    // OBI ADDR PHASE
    logic [DATA_WIDTH-1:0] data_mask;
    assign data_mask = {{8{obi_abe_i[3]}}, {8{obi_abe_i[2]}}, {8{obi_abe_i[1]}}, {8{obi_abe_i[0]}}};

    logic [DATA_WIDTH-1:0] addr_reg_target;
    assign addr_reg_target = {28'b0, obi_aaddr_i[3:2], 2'b0};

    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            i2c_data_reg  <= 0;
            //i2c_speed_reg <= SET THIS WHEN TESTING IS COMPLETED 
            state_reg <= ADDR;
        end
        else begin
            if (obi_a_fire) begin
                case (addr_reg_target)
                    I2C_STATUS_REG: begin
                        if (~obi_awe_i)
                            obi_rdata_o <= i2c_status_reg;
                    end
                    I2C_DATA_REG: begin
                        if (obi_awe_i)
                            i2c_data_reg <= obi_awdata_i & data_mask;
                        else
                            obi_rdata_o <= i2c_data_reg;
                    end
                    I2C_SPEED_REG: begin
                        if (obi_awe_i)
                            i2c_speed_reg <= obi_awdata_i & data_mask;
                        else
                            obi_rdata_o <= i2c_speed_reg;
                    end
                    default: ; // do nothing for unknown addresses
                endcase
            end
        end
    end

    // OBI HANDSHAKE SIGNALS
    assign obi_agnt_o   = (state_reg == ADDR);
    assign obi_rvalid_o = (state_reg == RESP);

    // I2C MASTER
    logic       i2c_done_tick;
    logic [7:0] i2c_dout;
    logic       i2c_ack;

    logic       wr_i2c_reg;

    tri scl, sda; // to avoid warnings

    always_ff @(posedge clk_i) begin
        if (state_reg == ADDR)
            wr_i2c_reg <= obi_a_fire & obi_awe_i & (addr_reg_target == I2C_DATA_REG);
    end

    i2c_master i2c(
        // clk, reset
        .clk    (clk_i),
        .reset  (~rstn_i),

        // inputs
        .wr_i2c (wr_i2c_reg),
        .cmd    (i2c_data_reg[10:8]),
        .din    (i2c_data_reg[7:0]),
        .dvsr   (i2c_speed_reg[15:0]),

        // outputs
        .dout   (i2c_dout),
        .ack    (i2c_ack),
        .ready  (i2c_status_reg[9]),
        .done_tick (i2c_done_tick),

        // scl, sda
        .sda(sda),
        .scl(scl)
    );

    // I2C RX BUFFER
    register #(
        .DTYPE (logic [8:0]),
        .RESET_VALUE (9'b0)
    ) i2c_rx_buffer (
        .clk  (clk_i),
        .rstn (~rstn_i),
        .ce   (i2c_done_tick),
        .in   ({i2c_ack, i2c_dout}),
        .out  (i2c_status_reg[8:0])
    );

endmodule
