`timescale 1ns/1ps
// One side threshold lane; grayscale/statistical policy are shared upstream.
module parallel_projection_lane #(
    parameter integer WIDTH=640,HEIGHT=480,MAX_OBJECTS=8,CONFIG_BITS=323,PIPELINED_SCAN=0,SCAN_TIMEOUT=4*WIDTH+32
)(
    input wire clk,rst_n,ce,flush,frame_start,
    input wire [CONFIG_BITS-1:0] cfg_word,
    input wire [31:0] cfg_epoch,
    input wire [7:0] cfg_threshold,
    input wire in_valid,in_sof,in_eol,in_binary,
    input wire [1:0] in_mode,
    output wire batch_valid,input wire batch_ready,
    output wire [63:0] batch_tag,
    output wire [7:0] batch_count,
    output wire [MAX_OBJECTS*16-1:0] batch_lefts,batch_rights,
    output wire busy,fault,fault_sticky,
    output wire result_update,
    output wire [31:0] result_frame_id,
    output wire [15:0] result_count,
    output wire [7:0] result_threshold
);
    reg [CONFIG_BITS-1:0] configs[0:3];reg [31:0] ids[0:3],epochs[0:3];
    reg [3:0] meta_valid;reg [31:0] sequence_id;
    reg [7:0] thresholds[0:3];
    wire [31:0] next_id=sequence_id+1'b1;
    integer i;
    always @(posedge clk) begin
        if(!rst_n) begin
            sequence_id<=0;meta_valid<=0;
            for(i=0;i<4;i=i+1) begin configs[i]<=0;ids[i]<=0;epochs[i]<=0;thresholds[i]<=0;end
        end else if(frame_start) begin
            sequence_id<=next_id;meta_valid[next_id[1:0]]<=1;
            configs[next_id[1:0]]<=cfg_word;ids[next_id[1:0]]<=next_id;epochs[next_id[1:0]]<=cfg_epoch;
            thresholds[next_id[1:0]]<=cfg_threshold;
        end
    end
    assign result_threshold=thresholds[result_frame_id[1:0]];
    wire pv,ps,pe,pa,pb;wire [15:0] px,py,source_x;
    wire [1:0] pm;
    morphology_filter #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) morphology(
        .clk(clk),.rst_n(rst_n),.ce(ce),.in_valid(in_valid),.in_sof(in_sof),.in_eol(in_eol),
        .in_binary(in_binary),.cfg_mode(in_mode),.out_valid(pv),.out_sof(ps),.out_eol(pe),
        .out_x(px),.out_y(py),.out_source_x(source_x),.out_source_y(),.analysis_valid(pa),.out_mode(pm),
        .out_binary(pb),.out_raw(),.out_eroded(),.out_dilated(),.out_opened());
    wire snap_valid,snap_update,proj_drop,proj_error,req,ready,rdvalid,rderror;
    wire [31:0] snap_id,rdid,aborts;wire [15:0] addr,resp_addr,data;
    wire [1:0] snap_mode;
    projection_accumulator #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) projection(
        .clk(clk),.rst_n(rst_n),.ce(ce),.in_valid(pv),.in_sof(ps),.in_eol(pe),
        .in_x(px),.in_y(py),.in_source_x(source_x),.in_analysis_valid(pa),.in_binary(pb),.in_mode(pm),
        .clear_busy(),.snapshot_valid(snap_valid),.snapshot_update(snap_update),.frame_done(),.frame_drop(proj_drop),
        .snapshot_frame_id(snap_id),.snapshot_white_pixels(),.snapshot_roi_pixels(),.snapshot_mode(snap_mode),
        .dropped_frames(),.done_frame_id(),.error_sticky(proj_error),
        .rd_req(req),.rd_addr(addr),.rd_ready(ready),.rd_valid(rdvalid),.rd_error(rderror),
        .rd_resp_addr(resp_addr),.rd_data(data),.rd_frame_id(rdid));
    wire meta_ok=meta_valid[snap_id[1:0]]&&ids[snap_id[1:0]]==snap_id;
    wire [CONFIG_BITS-1:0] c=configs[snap_id[1:0]];
    wire scan_busy,abort,rv,sv,cut;wire [2:0] abort_reason;
    wire [15:0] cuts,high_t,low_t,min_t,gap_t,sx,sp,cx;wire [31:0] sfid,cfid;
    projection_valley_scanner #(.WIDTH(WIDTH),.PIPELINED(PIPELINED_SCAN),.TIMEOUT_CYCLES(SCAN_TIMEOUT)) scanner(
        .clk(clk),.rst_n(rst_n),.snapshot_valid(snap_valid&&meta_ok),.snapshot_frame_id(snap_id),.snapshot_mode(snap_mode),
        .cfg_high(c[238+:16]),.cfg_low(c[222+:16]),.cfg_min_width(c[206+:16]),.cfg_gap(c[190+:16]),
        .cfg_valley_enable(c[189]),.cfg_valley_ratio(c[181+:8]),.cfg_valley_depth(c[165+:16]),
        .cfg_valley_width(c[149+:16]),.cfg_peak_distance(c[133+:16]),.cfg_peak_support(c[117+:16]),
        .rd_req(req),.rd_addr(addr),.rd_ready(ready),.rd_valid(rdvalid),.rd_error(rderror),
        .rd_resp_addr(resp_addr),.rd_data(data),.rd_frame_id(rdid),.busy(scan_busy),.result_valid(rv),
        .result_update(result_update),.scan_abort(abort),.abort_reason(abort_reason),.aborted_scans(aborts),
        .result_frame_id(result_frame_id),.result_count(result_count),.result_cut_count(cuts),.result_mode(),
        .result_high(high_t),.result_low(low_t),.result_min_width(min_t),.result_gap(gap_t),
        .result_valley_enable(),.result_valley_ratio(),.result_valley_depth(),.result_valley_width(),
        .result_peak_distance(),.result_peak_support(),.sample_valid(sv),.sample_x(sx),.sample_value(sp),
        .sample_frame_id(sfid),.cut_update(cut),.cut_x(cx),.cut_frame_id(cfid));
    reg armed;
    wire sample_enabled=meta_valid[sfid[1:0]]&&ids[sfid[1:0]]==sfid&&configs[sfid[1:0]][CONFIG_BITS-1];
    wire result_meta=meta_valid[result_frame_id[1:0]]&&ids[result_frame_id[1:0]]==result_frame_id;
    wire extract_busy,extract_fault,extract_sticky;
    always @(posedge clk) begin
        if(!rst_n||flush) armed<=0;
        else begin
            if(result_update) armed<=0;
            if(sv&&sx==0&&sample_enabled) armed<=1;
        end
    end
    projection_object_extractor #(.PIPELINED_FAULT_COUNTER(1),.WIDTH(WIDTH),.MAX_OBJECTS(MAX_OBJECTS),.TAG_WIDTH(64)) extractor(
        .clk(clk),.rst_n(rst_n),.flush(flush),.sample_valid(sv&&sample_enabled&&(armed||sx==0)&&!flush),
        .sample_x(sx),.sample_value(sp),.sample_frame_id(sfid),.cut_valid(cut&&armed&&!flush),
        .cut_x(cx),.cut_frame_id(cfid),.commit_valid(result_update&&rv&&armed&&result_meta&&!flush),
        .commit_frame_id(result_frame_id),.commit_tag({epochs[result_frame_id[1:0]],result_frame_id}),
        .commit_count(result_count),.commit_cut_count(cuts),.commit_high(high_t),.commit_low(low_t),
        .commit_min_width(min_t),.commit_gap(gap_t),.batch_valid(batch_valid),.batch_ready(batch_ready),
        .batch_tag(batch_tag),.batch_count(batch_count),.batch_lefts(batch_lefts),.batch_rights(batch_rights),
        .busy(extract_busy),.fault(extract_fault),.fault_sticky(extract_sticky),.fault_reason(),.fault_count());
    assign busy=scan_busy||extract_busy;
    assign fault=extract_fault||(abort&&c[CONFIG_BITS-1])||(proj_drop&&cfg_word[CONFIG_BITS-1]);
    assign fault_sticky=extract_sticky||((proj_error||aborts!=0)&&cfg_word[CONFIG_BITS-1]);
endmodule
