`timescale 1ns/1ps
// A synthesizable four-scene source. Pixel zero is bit zero of each 32-bit word.
// ROM_FILE is relative to the simulator/Vivado working directory.
module selftest_video_source #(
    parameter integer WIDTH=640, HEIGHT=480,
    parameter integer ROM_WIDTH=160, ROM_HEIGHT=120, SCALE=4,
    parameter integer HOLD_FRAMES=60, FRAME_GAP_CYCLES=3026133,
    parameter ROM_FILE="fixtures/selftest/scenes_160x120.hex"
) (
    input wire clk, rst_n, ce, enable, restart,
    input wire cfg_scene_auto,
    input wire [1:0] cfg_scene,
    output reg out_valid, out_sof, out_eol,
    output reg [23:0] out_rgb,
    output reg [1:0] out_scene,
    output reg [15:0] out_x, out_y,
    output reg frame_done, scene_change
);
    localparam integer WORDS_PER_SCENE=(ROM_WIDTH*ROM_HEIGHT+31)/32;
    localparam integer ROM_WORDS=4*WORDS_PER_SCENE;
    localparam integer ADDR_BITS=(ROM_WORDS<=2) ? 1 : $clog2(ROM_WORDS);
    reg [15:0] request_x, request_y;
    reg [31:0] gap_left, held_frames;
    reg [1:0] frame_scene, next_auto_scene;
    reg frame_auto;
    reg pending_valid, pending_sof, pending_eol;
    reg [15:0] pending_x, pending_y;
    reg [1:0] pending_scene;
    reg [4:0] pending_bit;
    reg displayed_once;
    reg [1:0] displayed_scene;
    wire first_request=(request_x==0 && request_y==0);
    wire last_request=(request_x==WIDTH-1 && request_y==HEIGHT-1);
    wire [1:0] selected_scene=first_request ?
        (cfg_scene_auto && frame_auto ? next_auto_scene : cfg_scene) : frame_scene;
    wire issue=ce && enable && !restart && gap_left==0;
    wire [31:0] local_pixel=(request_y/SCALE)*ROM_WIDTH+(request_x/SCALE);
    wire [ADDR_BITS-1:0] rom_address=selected_scene*WORDS_PER_SCENE+(local_pixel>>5);
    wire [31:0] rom_data;
    wire foreground=rom_data[pending_bit];
    selftest_packed_rom #(.DEPTH(ROM_WORDS),.ADDR_BITS(ADDR_BITS),.ROM_FILE(ROM_FILE)) rom (
        .clk(clk),.read_enable(issue),.read_address(rom_address),.read_data(rom_data));

    // Reset/disable takes precedence over ce, so a source switch discards the
    // pending ROM word immediately. Ordinary ce pauses preserve all video state.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            request_x<=0; request_y<=0; gap_left<=0; held_frames<=0;
            frame_scene<=0; next_auto_scene<=0; frame_auto<=0;
            pending_valid<=0; pending_sof<=0; pending_eol<=0;
            pending_x<=0; pending_y<=0; pending_scene<=0; pending_bit<=0;
            out_valid<=0; out_sof<=0; out_eol<=0; out_rgb<=0;
            out_scene<=0; out_x<=0; out_y<=0;
            frame_done<=0; scene_change<=0; displayed_once<=0; displayed_scene<=0;
        end else begin
            frame_done<=0; scene_change<=0;
            if(!enable || restart) begin
                request_x<=0; request_y<=0; gap_left<=0; held_frames<=0;
                frame_scene<=0; next_auto_scene<=0; frame_auto<=0;
                pending_valid<=0; pending_sof<=0; pending_eol<=0;
                pending_x<=0; pending_y<=0; pending_scene<=0; pending_bit<=0;
                out_valid<=0; out_sof<=0; out_eol<=0; out_rgb<=0;
                out_scene<=0; out_x<=0; out_y<=0;
                displayed_once<=0; displayed_scene<=0;
            end else if(ce) begin
                out_valid<=pending_valid;
                out_sof<=pending_valid && pending_sof;
                out_eol<=pending_valid && pending_eol;
                if(pending_valid) begin
                    out_rgb<=foreground ? 24'he0e0e0 : 24'h202020;
                    out_x<=pending_x; out_y<=pending_y; out_scene<=pending_scene;
                    if(pending_sof) begin
                        scene_change<=!displayed_once || displayed_scene!=pending_scene;
                        displayed_once<=1; displayed_scene<=pending_scene;
                    end
                    if(pending_x==WIDTH-1 && pending_y==HEIGHT-1) frame_done<=1;
                end
                pending_valid<=issue;
                if(issue) begin
                    pending_x<=request_x; pending_y<=request_y;
                    pending_sof<=first_request; pending_eol<=request_x==WIDTH-1;
                    pending_scene<=selected_scene; pending_bit<=local_pixel[4:0];
                    if(first_request) begin
                        frame_scene<=selected_scene; frame_auto<=cfg_scene_auto;
                        if(!cfg_scene_auto || !frame_auto) held_frames<=0;
                    end
                    if(last_request) begin
                        request_x<=0; request_y<=0; gap_left<=FRAME_GAP_CYCLES;
                        if(frame_auto) begin
                            if(held_frames+1>=HOLD_FRAMES) begin
                                held_frames<=0; next_auto_scene<=frame_scene+2'd1;
                            end else begin
                                held_frames<=held_frames+1; next_auto_scene<=frame_scene;
                            end
                        end else begin
                            held_frames<=0; next_auto_scene<=frame_scene;
                        end
                    end else if(request_x==WIDTH-1) begin
                        request_x<=0; request_y<=request_y+1;
                    end else request_x<=request_x+1;
                end else if(gap_left!=0) gap_left<=gap_left-1;
            end
        end
    end
`ifndef SYNTHESIS
    initial begin
        if(WIDTH!=ROM_WIDTH*SCALE || HEIGHT!=ROM_HEIGHT*SCALE || SCALE<1 ||
           WIDTH<2 || HEIGHT<2 || WIDTH>65535 || HEIGHT>65535 || HOLD_FRAMES<1 ||
           FRAME_GAP_CYCLES<0 || ROM_WIDTH<1 || ROM_HEIGHT<1)
            $fatal(1,"Invalid selftest source dimensions/hold/gap");
    end
`endif
endmodule

module selftest_packed_rom #(
    parameter integer DEPTH=2400, ADDR_BITS=12,
    parameter ROM_FILE="fixtures/selftest/scenes_160x120.hex"
) (
    input wire clk, read_enable,
    input wire [ADDR_BITS-1:0] read_address,
    output reg [31:0] read_data
);
    (* rom_style="block", ram_style="block" *) reg [31:0] memory [0:DEPTH-1];
    initial $readmemh(ROM_FILE,memory);
    always @(posedge clk) begin
        if(read_enable) read_data<=memory[read_address];
    end
endmodule
