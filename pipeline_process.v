// 4-Stage Pipelined Processor supporting ADD, SUB, and LOAD
module pipelined_processor (
    input wire clk,
    input wire rst
);

    // =========================================================================
    // STAGE 1: INSTRUCTION FETCH (IF)
    // =========================================================================
    reg [7:0] pc;
    wire [15:0] if_instruction;
    
    // Instruction Memory (Simplified ROM)
    // Format: [15:12] Opcode | [11:8] Rd | [7:4] Rs1 | [3:0] Rs2 or Offset
    assign if_instruction = (pc == 8'd0) ? 16'h1123 : // ADD  R1, R2, R3  (R1 = R2 + R3)
                            (pc == 8'd1) ? 16'h2451 : // SUB  R4, R5, R1  (R4 = R5 - R1)
                            (pc == 8'd2) ? 16'h3624 : // LOAD R6, R2(4)   (R6 = Mem[R2 + 4])
                                           16'h0000;  // NOP

    // IF/ID-EX Pipeline Registers
    reg [15:0] idex_instruction;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc <= 8'd0;
            idex_instruction <= 16'h0000;
        end else begin
            pc <= pc + 1'b1;
            idex_instruction <= if_instruction;
        end
    end

    // =========================================================================
    // STAGE 2: INSTRUCTION DECODE & EXECUTE (ID/EX)
    // =========================================================================
    wire [3:0] idex_opcode = idex_instruction[15:12];
    wire [3:0] idex_rd     = idex_instruction[11:8];
    wire [3:0] idex_rs1    = idex_instruction[7:4];
    wire [3:0] idex_rs2    = idex_instruction[3:0]; // Also acts as immediate offset for LOAD

    // Register File (Pre-loaded with sample values for simulation)
    reg [15:0] register_file [0:15];
    wire [15:0] reg_data1 = register_file[idex_rs1];
    wire [15:0] reg_data2 = register_file[idex_rs2];

    // ALU Logic
    reg [15:0] idex_alu_result;
    always @(*) begin
        case (idex_opcode)
            4'h1:    idex_alu_result = reg_data1 + reg_data2;         // ADD
            4'h2:    idex_alu_result = reg_data1 - reg_data2;         // SUB
            4'h3:    idex_alu_result = reg_data1 + {12'b0, idex_rs2}; // LOAD Address calc
            default: idex_alu_result = 16'h0000;
        endcase
    end

    // EX/MEM Pipeline Registers
    reg [3:0]  mem_opcode;
    reg [3:0]  mem_rd;
    reg [15:0] mem_alu_result;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_opcode     <= 4'h0;
            mem_rd         <= 4'h0;
            mem_alu_result <= 16'h0000;
            
            // Initializing Register File with sample variables
            register_file[0] <= 16'h0000;
            register_file[1] <= 16'h0000;
            register_file[2] <= 16'h000A; // R2 = 10
            register_file[3] <= 16'h0005; // R3 = 5
            register_file[4] <= 16'h0000;
            register_file[5] <= 16'h0020; // R5 = 32
            register_file[6] <= 16'h0000;
        end else begin
            mem_opcode     <= idex_opcode;
            mem_rd         <= idex_rd;
            mem_alu_result <= idex_alu_result;
        end
    end

    // =========================================================================
    // STAGE 3: DATA MEMORY ACCESS (MEM)
    // =========================================================================
    reg [15:0] data_memory [0:31];
    reg [15:0] mem_read_data;

    // Async memory read for LOAD instruction
    always @(*) begin
        if (mem_opcode == 4'h3)
            mem_read_data = data_memory[mem_alu_result[4:0]];
        else
            mem_read_data = 16'h0000;
    end

    // MEM/WB Pipeline Registers
    reg [3:0]  wb_opcode;
    reg [3:0]  wb_rd;
    reg [15:0] wb_alu_result;
    reg [15:0] wb_read_data;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wb_opcode     <= 4'h0;
            wb_rd         <= 4'h0;
            wb_alu_result <= 16'h0000;
            wb_read_data  <= 16'h0000;
            
            // Pre-load data memory address 14 (10 + 4) with a sample value
            data_memory[14] <= 16'hBEEF; 
        end else begin
            wb_opcode     <= mem_opcode;
            wb_rd         <= mem_rd;
            wb_alu_result <= mem_alu_result;
            wb_read_data  <= mem_read_data;
        end
    end

    // =========================================================================
    // STAGE 4: WRITE BACK (WB)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst && wb_opcode != 4'h0) begin
            if (wb_opcode == 4'h3)
                register_file[wb_rd] <= wb_read_data;  // Write LOAD data
            else
                register_file[wb_rd] <= wb_alu_result; // Write ADD/SUB data
        end
    end

endmodule

module tb_pipelined_processor;
    reg clk;
    reg rst;

    // Instantiate Unit Under Test (UUT)
    pipelined_processor uut (
        .clk(clk),
        .rst(rst)
    );

    // Clock generator (50MHz)
    always #10 clk = ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_pipelined_processor);

        clk = 0;
        rst = 1;
        #25;
        rst = 0; // Release reset
        
        // Monitor pipeline propagation over 6 clock cycles
        $display("Time\tPC\tIF_Inst\tIDEX_Op\tMEM_Op\tWB_Op\tR1\tR4\tR6");
        $monitor("%0t\t%h\t%h\t%h\t%h\t%h\t%h\t%h\t%h", 
                 $time, uut.pc, uut.if_instruction, uut.idex_opcode, 
                 uut.mem_opcode, uut.wb_opcode, uut.register_file[1], 
                 uut.register_file[4], uut.register_file[6]);
                 
        #140;
        $finish;
    end
endmodule
