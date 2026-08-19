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
    output logic                    obi_rerr_o
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
            ADDR: if (obi_a_fire) state_next = RESP;
            RESP: if (obi_r_fire) state_next = ADDR;
        endcase
    end

    // OBI ERROR
    logic rerr_reg, rerr_next;
    assign obi_rerr_o = rerr_reg;

    always_ff @(posedge clk_i, negedge rstn_i) begin
        if (~rstn_i)
            rerr_reg <= 1'b0;
        else
            rerr_reg <= rerr_next;
    end

    always_comb begin
        rerr_next = rerr_reg;

        if (state_reg == ADDR) begin
            case (addr_reg_target)
                I2C_STATUS_REG, I2C_DATA_REG, I2C_SPEED_REG: rerr_next = 1'b0;
                default: rerr_next = 1'b1;
            endcase
        end
    end

    // OBI ADDR PHASE
    logic [DATA_WIDTH-1:0] data_mask;
    logic [DATA_WIDTH-1:0] addr_reg_target;

    assign data_mask = { {8{obi_abe_i[3]}}, {8{obi_abe_i[2]}}, {8{obi_abe_i[1]}}, {8{obi_abe_i[0]}} };

    assign addr_reg_target = {28'b0, obi_aaddr_i[3:0]};

    always_ff @(posedge clk_i) begin
        if (~rstn_i) begin
            i2c_data_reg  <= 0;
            //i2c_speed_reg <= DEFAULT I2C SPEED, SET THIS WHEN TESTING IS COMPLETED
            state_reg <= ADDR;
        end
        else begin
            if (obi_a_fire) begin
                case (addr_reg_target)

                    I2C_STATUS_REG:
                        if (~obi_awe_i)
                            obi_rdata_o <= i2c_status_reg;

                    I2C_DATA_REG:
                        if (obi_awe_i)
                            i2c_data_reg <= obi_awdata_i & data_mask;
                        else
                            obi_rdata_o <= i2c_data_reg;

                    I2C_SPEED_REG:
                        if (obi_awe_i)
                            i2c_speed_reg <= obi_awdata_i & data_mask;
                        else
                            obi_rdata_o <= i2c_speed_reg;

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

    tri1 scl, sda; // to avoid warnings

    logic wr_i2c_reg;

    always_ff @(posedge clk_i)
        if (state_reg == ADDR)
            wr_i2c_reg <= obi_a_fire & obi_awe_i & (addr_reg_target == I2C_DATA_REG);

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
        .rstn (rstn_i),
        .ce   (i2c_done_tick),
        .in   ({i2c_ack, i2c_dout}),
        .out  (i2c_status_reg[8:0])
    );

endmodule
