module i2c_master(
    input logic clk, reset,

    input logic wr_i2c,
    input logic [2:0] cmd,
    input logic [7:0] din,
    input logic [15:0] dvsr,

    output logic [7:0] dout,
    output logic ack,
    output logic ready,
    output logic done_tick,

    output tri1 scl,
    inout tri1 sda
    );

    // COMMAND ENCODINGS
    localparam START_CMD   = 3'b000;
    localparam WR_CMD      = 3'b001;
    localparam RD_CMD      = 3'b010;
    localparam STOP_CMD    = 3'b011;
    localparam RESTART_CMD = 3'b100;

    // FSM STATES
    typedef enum logic [3:0] {
        idle,
        start1,
        start2,
        hold,
        data1,
        data2,
        data3,
        data4,
        data_end,
        stop1,
        stop2,
        restart
    } state_t;

    // STATES AND REGISTERS
    state_t state_reg, state_next;
    logic [15:0] c_reg, c_next;
    logic [15:0] qutr, half;
    logic [8:0] tx_reg, tx_next;
    logic [8:0] rx_reg, rx_next;
    logic [2:0] cmd_reg, cmd_next;
    logic [3:0] bit_reg, bit_next;
    logic sda_out, scl_out, sda_reg, scl_reg, data_phase;
    logic done_tick_i, ready_i;
    logic into, nack;

    // SDA, SCL BUFFER
    always_ff @(posedge clk, posedge reset)
        if (reset) begin
            sda_reg <= 1'b1;
            scl_reg <= 1'b1;
        end
        else begin
            sda_reg <= sda_out;
            scl_reg <= scl_out;
        end

    // SCL IS HIGH WHEN NOT DRIVEN
    // DUE TO PULL-UP RESISTOR
    assign scl = (scl_reg) ? 1'bz : 1'b0;

    // "INTO" SIGNAL HIGH WHEN DATA BEING
    // WRITTEN INTO MASTER
    assign into = (data_phase && cmd_reg == RD_CMD && bit_reg < 8) || (data_phase && cmd_reg == WR_CMD && bit_reg == 8);

    // HIGH WHEN NOT DRIVEN, RELEASE WHEN SLAVE
    // WRITING INTO MASTER
    assign sda = (into || sda_reg) ? 1'bz : 1'b0;

    assign dout = rx_reg[8:1];
    assign ack  = rx_reg[0];

    // MASTER ALWAYS SIGNALS
    // ACKNOWLEDGEMENT OF READ OP
    assign nack = 1'b0;

    always_ff @(posedge clk, posedge reset)
        if (reset) begin
            state_reg <= idle;
            c_reg     <= 0;
            bit_reg   <= 0;
            cmd_reg   <= 0;
            tx_reg    <= 0;
            rx_reg    <= 0;
        end
        else begin
            state_reg <= state_next;
            c_reg     <= c_next;
            bit_reg   <= bit_next;
            cmd_reg   <= cmd_next;
            tx_reg    <= tx_next;
            rx_reg    <= rx_next;
        end

    // QUARTER AND HALF I2C CLK CYCLES
    assign qutr = dvsr;
    assign half = {qutr[14:0], 1'b0};

    always_comb begin
        state_next  = state_reg;
        c_next      = c_reg + 1;
        bit_next    = bit_reg;
        tx_next     = tx_reg;
        rx_next     = rx_reg;
        cmd_next    = cmd_reg;
        done_tick_i = 1'b0;
        ready_i     = 1'b0;
            
        // HIGH IF NOT SPECIFIED BELOW
        scl_out     = 1'b1;
        sda_out     = 1'b1;

        data_phase  = 1'b0;

        case (state_reg)
            idle: begin
                ready_i = 1'b1;
                if (wr_i2c && cmd == START_CMD) begin
                    state_next = start1;
                    c_next = 0;
                end
            end

            // ======================================

            start1: begin
                sda_out = 1'b0;
                if (c_reg == half) begin
                    c_next = 0;
                    state_next = start2;
                end
            end

            // ======================================

            start2: begin
                scl_out = 1'b0;
                sda_out = 1'b0;
                if (c_reg == half) begin
                    c_next = 0;
                    state_next = hold;
                end
            end

            // ======================================

            hold: begin
                ready_i = 1'b1;
                sda_out = 1'b0;
                scl_out = 1'b0;
                if (wr_i2c) begin
                    cmd_next = cmd;
                    c_next = 0;
                    case (cmd)
                        RESTART_CMD, START_CMD: begin
                            state_next = restart;
                        end
                        STOP_CMD: begin
                            state_next = stop1;
                        end
                        default: begin
                            bit_next = 0;
                            state_next = data1;
                            tx_next = {din, nack};
                        end
                    endcase
                end
            end

            // ======================================

            data1: begin
               scl_out = 1'b0; 
               sda_out = tx_reg[8];
               data_phase = 1'b1;
               if (c_reg == qutr) begin
                   c_next = 0;
                   state_next = data2;
               end
            end

            // ======================================

            data2: begin
                sda_out = tx_reg[8];
                data_phase = 1'b1;
                if (c_reg == qutr) begin
                    c_next = 0;
                    state_next = data3;
                    rx_next = {rx_reg[7:0], sda};
                end
            end

            // ======================================

            data3: begin
                sda_out = tx_reg[8];
                data_phase = 1'b1;
                if (c_reg == qutr) begin
                    c_next = 0;
                    state_next = data4;
                end
            end

            // ======================================

            data4: begin
                scl_out = 1'b0;
                sda_out = tx_reg[8];
                data_phase = 1'b1;
                if (c_reg == qutr) begin
                    c_next = 0;
                    if (bit_reg == 8) begin
                        state_next = data_end;
                        done_tick_i = 1'b1;
                    end
                    else begin
                        tx_next = {tx_reg[7:0], 1'b0};
                        bit_next = bit_reg + 1;
                        state_next = data1;
                    end
                end
            end

            // ======================================

            data_end: begin
                sda_out = 1'b0;
                scl_out = 1'b0;
                if (c_reg == qutr) begin
                    c_next = 0;
                    state_next = hold;
                end
            end

            // ======================================

            restart: begin
                if (c_reg == half) begin
                    c_next = 0;
                    state_next = start1;
                end
            end

            // ======================================

            stop1: begin
                sda_out = 1'b0;
                if (c_reg == half) begin
                    c_next = 0;
                    state_next = stop2;
                end
            end

            // ======================================

            // STOP2
            default: begin 
                if (c_reg == half) begin
                    state_next = idle;
                end
            end
        endcase

        assign done_tick = done_tick_i;
        assign ready = ready_i;
    end

endmodule
