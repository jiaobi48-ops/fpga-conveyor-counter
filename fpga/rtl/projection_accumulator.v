`timescale 1ns/1ps

// Two-bank synchronous-BRAM column projection, 1 accepted pixel/ce cycle.
// The first WIDTH enabled clocks from SOF clear the new accumulation bank.
// No analysis pixel may arrive during that clear. Morphology leaves four rows.
// Snapshot read port is independent of ce; read responses are frame-tagged.
// A repeated-address forwarding path covers read/write latency hazards.
module projection_accumulator #(
    parameter integer WIDTH=640,
    parameter integer HEIGHT=480,
    parameter integer COUNT_WIDTH=16
) (
    input wire clk,rst_n,ce,
    input wire in_valid,in_sof,in_eol,
    input wire [15:0] in_x,in_y,in_source_x,
    input wire in_analysis_valid,in_binary,
    input wire [1:0] in_mode,
    output reg clear_busy,
    output reg snapshot_valid,snapshot_update,frame_done,frame_drop,
    output reg [31:0] snapshot_frame_id,snapshot_white_pixels,snapshot_roi_pixels,
    output reg [1:0] snapshot_mode,
    output reg [31:0] dropped_frames,
    output reg [31:0] done_frame_id,
    output reg error_sticky,
    input wire rd_req,
    input wire [15:0] rd_addr,
    output wire rd_ready,
    output reg rd_valid,rd_error,
    output reg [15:0] rd_resp_addr,
    output reg [COUNT_WIDTH-1:0] rd_data,
    output reg [31:0] rd_frame_id
);
    (* ram_style="block" *) reg [COUNT_WIDTH-1:0] bank0[0:WIDTH-1];
    (* ram_style="block" *) reg [COUNT_WIDTH-1:0] bank1[0:WIDTH-1];
    reg [COUNT_WIDTH-1:0] q0,q1;
    reg active_bank,frame_active,snapshot_bank;
    reg [15:0] clear_addr,expect_x,expect_y;
    reg [1:0] bank_fault,frame_mode;
    reg [31:0] sequence_id,frame_id,white_pixels,roi_pixels;
    wire start=ce&&in_valid&&in_sof;
    wire sample_bank=in_sof ? ~active_bank : active_bank;
    wire in_frame=in_sof||frame_active;
    wire [15:0] expected_x=in_sof ? 16'd0 : expect_x;
    wire [15:0] expected_y=in_sof ? 16'd0 : expect_y;
    wire coordinate_fault=(in_x!=expected_x)||(in_y!=expected_y)||
                          (in_eol!=(expected_x==WIDTH-1));
    wire clear_en=ce&&(start||clear_busy);
    wire clear_bank=start ? ~active_bank : active_bank;
    wire [15:0] clear_index=start ? 16'd0 : clear_addr;
    wire analysis_fault=in_analysis_valid&&((in_source_x>=WIDTH)||clear_en);
    wire sample_fault=!in_frame||coordinate_fault||analysis_fault||
                      (in_sof&&frame_active);
    wire analysis_accept=in_valid&&in_frame&&in_analysis_valid&&!sample_fault;
    wire pixel_read=ce&&analysis_accept&&in_binary;
    // Coordinate EOF allows even a malformed EOL frame to be reported/dropped.
    wire finish=in_valid&&in_frame&&(in_x==WIDTH-1)&&(in_y==HEIGHT-1);
    wire [31:0] current_id=in_sof ? sequence_id+1'b1 : frame_id;
    wire [1:0] current_mode=in_sof ? in_mode : frame_mode;

    reg s1_valid,s1_bank,s1_eof,s1_bad;
    reg [15:0] s1_addr;
    reg [31:0] s1_id,s1_white,s1_roi;
    reg [1:0] s1_mode;
    reg s2_valid,s2_bank,s2_eof,s2_bad;
    reg [15:0] s2_addr;
    reg [COUNT_WIDTH-1:0] s2_sum;
    reg [31:0] s2_id,s2_white,s2_roi;
    reg [1:0] s2_mode;
    reg last_valid,last_bank;
    reg [15:0] last_addr;
    reg [COUNT_WIDTH-1:0] last_sum;

    wire [COUNT_WIDTH-1:0] ram_sum=s1_bank ? q1 : q0;
    wire [COUNT_WIDTH-1:0] forwarded_sum=
        (s2_valid && s2_bank==s1_bank && s2_addr==s1_addr) ? s2_sum :
        (last_valid && last_bank==s1_bank && last_addr==s1_addr) ? last_sum : ram_sum;
    wire overflow=s1_valid&&(&forwarded_sum);

    wire write0_clear=clear_en&&!clear_bank;
    wire write1_clear=clear_en&&clear_bank;
    wire write0_acc=ce&&s2_valid&&!s2_bank;
    wire write1_acc=ce&&s2_valid&&s2_bank;
    wire reuse_snapshot=start&&(sample_bank==snapshot_bank);
    assign rd_ready=snapshot_valid&&!reuse_snapshot;
    wire read_accept=rd_req&&rd_ready;
    wire read_in_range=rd_addr<WIDTH;
    wire read0_debug=read_accept&&read_in_range&&!snapshot_bank;
    wire read1_debug=read_accept&&read_in_range&&snapshot_bank;

    // Select addresses BEFORE indexing RAM. Multiple array indices inside
    // separate branches can infer additional ports and defeat block RAM.
    wire we0=rst_n&&(write0_clear||write0_acc);
    wire we1=rst_n&&(write1_clear||write1_acc);
    wire [15:0] wa0=write0_clear ? clear_index : s2_addr;
    wire [15:0] wa1=write1_clear ? clear_index : s2_addr;
    wire [COUNT_WIDTH-1:0] wd0=write0_clear ? {COUNT_WIDTH{1'b0}} : s2_sum;
    wire [COUNT_WIDTH-1:0] wd1=write1_clear ? {COUNT_WIDTH{1'b0}} : s2_sum;
    wire acc_read0=pixel_read&&!sample_bank;
    wire acc_read1=pixel_read&&sample_bank;
    wire re0=rst_n&&(acc_read0||read0_debug);
    wire re1=rst_n&&(acc_read1||read1_debug);
    wire [15:0] ra0=acc_read0 ? in_source_x : rd_addr;
    wire [15:0] ra1=acc_read1 ? in_source_x : rd_addr;
    // Canonical simple-dual-port template: exactly one index per port.
    always @(posedge clk) begin
        if(we0) bank0[wa0]<=wd0;
        if(re0) q0<=bank0[ra0];
        if(we1) bank1[wa1]<=wd1;
        if(re1) q1<=bank1[ra1];
    end

    // Request at edge N -> registered response visible after edge N+1.
    // No read request is accepted while a snapshot bank is being reused.
    reg read_pending,read_bank_pending,read_error_pending;
    reg [15:0] read_addr_pending;
    reg [31:0] read_id_pending;
    always @(posedge clk) begin
        if(!rst_n) begin
            read_pending<=0;read_bank_pending<=0;read_error_pending<=0;
            read_addr_pending<=0;read_id_pending<=0;
            rd_valid<=0;rd_error<=0;rd_resp_addr<=0;rd_data<=0;rd_frame_id<=0;
        end else begin
            read_pending<=read_accept;
            if(read_accept) begin
                read_bank_pending<=snapshot_bank;
                read_error_pending<=!read_in_range;
                read_addr_pending<=rd_addr;
                read_id_pending<=snapshot_frame_id;
            end
            rd_valid<=read_pending;
            rd_error<=read_pending&&read_error_pending;
            if(read_pending) begin
                rd_resp_addr<=read_addr_pending;
                rd_frame_id<=read_id_pending;
                rd_data<=read_error_pending ? {COUNT_WIDTH{1'b0}} :
                         (read_bank_pending ? q1 : q0);
            end
        end
    end

    always @(posedge clk) begin
        if(!rst_n) begin
            active_bank<=1;frame_active<=0;snapshot_bank<=0;
            clear_busy<=0;clear_addr<=0;expect_x<=0;expect_y<=0;bank_fault<=0;
            sequence_id<=0;frame_id<=0;frame_mode<=0;white_pixels<=0;roi_pixels<=0;
            snapshot_valid<=0;snapshot_update<=0;frame_done<=0;frame_drop<=0;
            snapshot_frame_id<=0;snapshot_white_pixels<=0;snapshot_roi_pixels<=0;
            snapshot_mode<=0;dropped_frames<=0;done_frame_id<=0;error_sticky<=0;
            s1_valid<=0;s1_bank<=0;s1_addr<=0;s1_eof<=0;s1_bad<=0;
            s1_id<=0;s1_white<=0;s1_roi<=0;s1_mode<=0;
            s2_valid<=0;s2_bank<=0;s2_addr<=0;s2_sum<=0;s2_eof<=0;s2_bad<=0;
            s2_id<=0;s2_white<=0;s2_roi<=0;s2_mode<=0;
            last_valid<=0;last_bank<=0;last_addr<=0;last_sum<=0;
        end else begin
            // Event pulses are one physical clock, even when video ce pauses.
            snapshot_update<=0;frame_done<=0;frame_drop<=0;
            if(ce) begin
                s1_valid<=pixel_read;s1_eof<=finish;
                if(in_valid) begin
                    s1_bank<=sample_bank;s1_addr<=in_source_x;
                    s1_bad<=sample_fault||
                            (!in_sof&&bank_fault[sample_bank]);
                    s1_id<=current_id;s1_mode<=current_mode;
                    s1_white<=(in_sof ? 32'd0 : white_pixels)+(analysis_accept&&in_binary);
                    s1_roi<=(in_sof ? 32'd0 : roi_pixels)+analysis_accept;
                end
                s2_valid<=s1_valid;s2_eof<=s1_eof;
                s2_bank<=s1_bank;s2_addr<=s1_addr;
                s2_bad<=s1_bad||bank_fault[s1_bank]||overflow;
                s2_id<=s1_id;s2_white<=s1_white;s2_roi<=s1_roi;s2_mode<=s1_mode;
                if(s1_valid) s2_sum<=overflow ? forwarded_sum : forwarded_sum+1'b1;
                last_valid<=s2_valid;
                if(s2_valid) begin
                    last_bank<=s2_bank;last_addr<=s2_addr;last_sum<=s2_sum;
                end
                if(start) begin
                    active_bank<=sample_bank;frame_active<=1;
                    sequence_id<=current_id;frame_id<=current_id;frame_mode<=in_mode;
                    bank_fault[sample_bank]<=sample_fault;
                    clear_busy<=WIDTH>1;clear_addr<=16'd1;
                    if(reuse_snapshot) snapshot_valid<=0;
                end else if(clear_busy) begin
                    if(clear_addr==WIDTH-1) begin clear_busy<=0;clear_addr<=0;end
                    else clear_addr<=clear_addr+1'b1;
                end
                if(in_valid) begin
                    if(sample_fault) begin bank_fault[sample_bank]<=1;error_sticky<=1;end
                    white_pixels<=(in_sof ? 32'd0 : white_pixels)+(analysis_accept&&in_binary);
                    roi_pixels<=(in_sof ? 32'd0 : roi_pixels)+analysis_accept;
                    if(in_eol) begin expect_x<=0;expect_y<=expected_y+1'b1;end
                    else begin expect_x<=expected_x+1'b1;expect_y<=expected_y;end
                    if(finish) frame_active<=0;
                end
                if(overflow) begin bank_fault[s1_bank]<=1;error_sticky<=1;end
                // The s2 write and publication happen at the same edge.
                // A reader sees snapshot_valid only after that final write.
                if(s2_eof) begin
                    frame_done<=1;done_frame_id<=s2_id;
                    if(s2_bad||bank_fault[s2_bank]) begin
                        frame_drop<=1;dropped_frames<=dropped_frames+1'b1;
                        error_sticky<=1;
                    end else begin
                        snapshot_bank<=s2_bank;snapshot_valid<=1;snapshot_update<=1;
                        snapshot_frame_id<=s2_id;snapshot_white_pixels<=s2_white;
                        snapshot_roi_pixels<=s2_roi;snapshot_mode<=s2_mode;
                    end
                end
            end
        end
    end
endmodule
