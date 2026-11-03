`timescale 1ns/1ps
// Frame-batched 2-of-3 interval consensus, never a vote on scalar counts.
// Every supporting object is consumed once; ambiguous/overlapping output is rejected.
module interval_consensus3 #(
    parameter integer MAX_OBJECTS=8,TAG_WIDTH=258,WAIT_CYCLES=8192,LOCAL_PAYLOAD=0
)(
    input wire clk,rst_n,flush,cfg_enable,
    input wire [15:0] cfg_tolerance,
    input wire c_valid,output wire c_ready,input wire [TAG_WIDTH-1:0] c_tag,
    input wire [7:0] c_count,input wire [MAX_OBJECTS*16-1:0] c_lefts,c_rights,
    input wire l_valid,output wire l_ready,input wire [63:0] l_tag,
    input wire [7:0] l_count,input wire [MAX_OBJECTS*16-1:0] l_lefts,l_rights,
    input wire h_valid,output wire h_ready,input wire [63:0] h_tag,
    input wire [7:0] h_count,input wire [MAX_OBJECTS*16-1:0] h_lefts,h_rights,
    output reg out_valid,input wire out_ready,output reg [TAG_WIDTH-1:0] out_tag,
    output reg [7:0] out_count,output reg [MAX_OBJECTS*16-1:0] out_lefts,out_rights,
    output reg [MAX_OBJECTS*3-1:0] out_support,
    output wire busy,output reg fault,fault_sticky,output reg [7:0] fault_reason,
    output reg [31:0] rejected_frames,disagreement_frames,dropped_objects
);
    localparam IDLE=0,CHECK=1,ANCHOR=2,SEARCH=3,BUILD=4,SORT=5,VERIFY=6,PUBLISH=7,REJECT=8,GATHER=9,RESOLVE=10,BOUNDS=11,SUPPORT_BOUNDS=12;
    localparam integer INDEX_BITS=$clog2(3*MAX_OBJECTS+2)+1;
    reg [3:0] state;reg [31:0] wait_age;
    wire [63:0] center_side_tag={c_tag[95:64],c_tag[31:0]};
    (* KEEP="TRUE" *) wire [3:0] center_low_diff,high_low_diff;
    generate for(genvar tp=0;tp<4;tp=tp+1)begin:tag_compare
        assign center_low_diff[tp]=center_side_tag[16*tp+:16]!=l_tag[16*tp+:16];
        assign high_low_diff[tp]=h_tag[16*tp+:16]!=l_tag[16*tp+:16];
    end endgenerate
    wire all_valid=c_valid&&l_valid&&h_valid;
    wire capture_payload=state==IDLE&&!out_valid&&c_valid&&(!cfg_enable||all_valid);
    wire take=capture_payload&&!flush;
    assign c_ready=state==IDLE&&!out_valid&&!flush&&(!cfg_enable||(l_valid&&h_valid));
    assign l_ready=!flush&&(!cfg_enable||take);
    assign h_ready=!flush&&(!cfg_enable||take);
    assign busy=state!=IDLE||out_valid;
    reg [15:0] lefts[0:3*MAX_OBJECTS-1],rights[0:3*MAX_OBJECTS-1];
    reg used[0:3*MAX_OBJECTS-1];reg [7:0] counts[0:2];
    reg [15:0] tolerance;reg [TAG_WIDTH-1:0] tag;
    reg [1:0] load_lane;
    reg [15:0] member_left[0:2],member_right[0:2];
    reg [15:0] anchor_left,anchor_right,previous_right;
    reg [15:0] lower_left,upper_left,lower_right,upper_right;
    reg [15:0] wl[0:MAX_OBJECTS-1],wr[0:MAX_OBJECTS-1];reg [2:0] ws[0:MAX_OBJECTS-1];
    // Include the terminal index and the -1 sentinel without 32-bit mux addresses.
    reg signed [INDEX_BITS-1:0] anchor,index,lane,slot,found[0:2],match_totals[0:2],n,sort_i,sort_j,verify_i;
    // One time-shared interval RAM read pair for validation, search and fusion.
    wire [INDEX_BITS-1:0] source_address=state==ANCHOR?anchor:state==GATHER?found[load_lane]:index;
    wire [15:0] source_left=lefts[source_address],source_right=rights[source_address];
    integer i,j,k;
    reg signed [INDEX_BITS-1:0] member_count,a,b,dropped;
    reg disagreement;reg [7:0] reject_code;
    reg [15:0] vl,vr,tmp_l,tmp_r;reg [2:0] mask,tmp_s;
    // abs(a-b)<=t is exactly equivalent to the saturated interval test.
    // Bounds are calculated once per anchor, then all endpoint comparisons run in parallel.
    function [15:0] lower_bound;
        input [15:0] value,tol;
        begin lower_bound=value>tol?value-tol:16'd0;end
    endfunction
    function [15:0] upper_bound;
        input [15:0] value,tol;reg [16:0] sum;
        begin sum={1'b0,value}+{1'b0,tol};upper_bound=sum[16]?16'hffff:sum[15:0];end
    endfunction
    wire candidate_close=source_left>=lower_left&&source_left<=upper_left&&
        source_right>=lower_right&&source_right<=upper_right;
    wire triple_close=member_left[0]>=lower_left&&member_left[0]<=upper_left&&
        member_right[0]>=lower_right&&member_right[0]<=upper_right&&
        member_left[2]>=lower_left&&member_left[2]<=upper_left&&
        member_right[2]>=lower_right&&member_right[2]<=upper_right;
    function [15:0] median3;
        input [15:0] a,b,c;
        begin median3=a>b ? (b>c?b:(a>c?c:a)) : (a>c?a:(b>c?c:b));end
    endfunction
    always @(posedge clk) begin
        fault<=0;
        if(!rst_n) begin
            state<=IDLE;out_valid<=0;out_tag<=0;out_count<=0;out_lefts<=0;out_rights<=0;out_support<=0;
            wait_age<=0;fault<=0;fault_sticky<=0;fault_reason<=0;rejected_frames<=0;disagreement_frames<=0;dropped_objects<=0;
        end else begin
            // Private payload can change on a cancelled transfer. Only the
            // flush-qualified valid/state branch can publish or consume it.
            if(LOCAL_PAYLOAD&&capture_payload)begin
                if(cfg_enable)begin
                        tag<=c_tag;tolerance<=cfg_tolerance;
                        counts[0]<=l_count;counts[1]<=c_count;counts[2]<=h_count;
                        for(i=0;i<MAX_OBJECTS;i=i+1) begin
                            lefts[i]<=l_lefts[16*i+:16];rights[i]<=l_rights[16*i+:16];
                            lefts[MAX_OBJECTS+i]<=c_lefts[16*i+:16];rights[MAX_OBJECTS+i]<=c_rights[16*i+:16];
                            lefts[2*MAX_OBJECTS+i]<=h_lefts[16*i+:16];rights[2*MAX_OBJECTS+i]<=h_rights[16*i+:16];
                            used[i]<=0;used[MAX_OBJECTS+i]<=0;used[2*MAX_OBJECTS+i]<=0;
                        end
                end else begin
                        out_tag<=c_tag;out_count<=c_count;out_lefts<=c_lefts;out_rights<=c_rights;
                        out_support<={MAX_OBJECTS{3'b010}};
                end
            end
            if(LOCAL_PAYLOAD&&state==PUBLISH)begin
                out_tag<=tag;out_count<=n;out_lefts<=0;out_rights<=0;out_support<=0;
                for(i=0;i<MAX_OBJECTS;i=i+1) if(i<n) begin out_lefts[16*i+:16]<=wl[i];out_rights[16*i+:16]<=wr[i];out_support[3*i+:3]<=ws[i];end
            end
            if(flush) begin state<=IDLE;out_valid<=0;wait_age<=0;end
            else begin
            if(out_valid&&out_ready) out_valid<=0;
            case(state)
            IDLE: begin
                if(take) begin
                    wait_age<=0;
                    if(!cfg_enable) begin
                        out_valid<=1;
                        if(!LOCAL_PAYLOAD)begin
                        out_tag<=c_tag;out_count<=c_count;out_lefts<=c_lefts;out_rights<=c_rights;
                        out_support<={MAX_OBJECTS{3'b010}};
                        end
                    end else begin
                        n=0;dropped=0;disagreement=0;
                        if(!LOCAL_PAYLOAD)begin
                        tag<=c_tag;tolerance<=cfg_tolerance;
                        counts[0]<=l_count;counts[1]<=c_count;counts[2]<=h_count;
                        for(i=0;i<MAX_OBJECTS;i=i+1) begin
                            lefts[i]<=l_lefts[16*i+:16];rights[i]<=l_rights[16*i+:16];
                            lefts[MAX_OBJECTS+i]<=c_lefts[16*i+:16];rights[MAX_OBJECTS+i]<=c_rights[16*i+:16];
                            lefts[2*MAX_OBJECTS+i]<=h_lefts[16*i+:16];rights[2*MAX_OBJECTS+i]<=h_rights[16*i+:16];
                            used[i]<=0;used[MAX_OBJECTS+i]<=0;used[2*MAX_OBJECTS+i]<=0;
                        end
                        end
                        if((|center_low_diff)||(|high_low_diff)) begin reject_code<=1;state<=REJECT;end
                        else if(l_count>MAX_OBJECTS||c_count>MAX_OBJECTS||h_count>MAX_OBJECTS) begin reject_code<=2;state<=REJECT;end
                        else begin index<=0;state<=CHECK;end
                    end
                end else if(cfg_enable&&(c_valid||l_valid||h_valid)&&!out_valid) begin
                    if(wait_age>=WAIT_CYCLES-1) begin wait_age<=0;reject_code<=3;state<=REJECT;end
                    else wait_age<=wait_age+1'b1;
                end else wait_age<=0;
            end
            CHECK: begin
                lane=index/MAX_OBJECTS;slot=index%MAX_OBJECTS;
                previous_right<=source_right;
                if(slot<counts[lane]&&(source_left>source_right||(slot>0&&source_left<=previous_right))) begin reject_code<=4;state<=REJECT;end
                else if(index==3*MAX_OBJECTS-1) begin anchor<=0;state<=ANCHOR;end
                else index<=index+1;
            end
            ANCHOR: begin
                lane=anchor/MAX_OBJECTS;slot=anchor%MAX_OBJECTS;
                if(anchor>=3*MAX_OBJECTS) begin sort_i<=0;sort_j<=0;state<=SORT;end
                else if(slot>=counts[lane]||used[anchor]) anchor<=anchor+1;
                else begin
                    anchor_left<=source_left;anchor_right<=source_right;
                    for(i=0;i<3;i=i+1) begin found[i]<=-1;match_totals[i]<=0;end
                    found[lane]<=anchor;match_totals[lane]<=1;index<=0;state<=BOUNDS;
                end
            end
            BOUNDS: begin
                lower_left<=lower_bound(anchor_left,tolerance);upper_left<=upper_bound(anchor_left,tolerance);
                lower_right<=lower_bound(anchor_right,tolerance);upper_right<=upper_bound(anchor_right,tolerance);
                state<=SEARCH;
            end
            SEARCH: begin
                lane=index/MAX_OBJECTS;slot=index%MAX_OBJECTS;
                if(lane!=anchor/MAX_OBJECTS&&slot<counts[lane]&&candidate_close) begin
                    if(used[index]) begin reject_code<=5;state<=REJECT;end
                    else begin found[lane]<=index;match_totals[lane]<=match_totals[lane]+1;end
                end
                if(!(lane!=anchor/MAX_OBJECTS&&slot<counts[lane]&&used[index]&&candidate_close)) begin
                    if(index==3*MAX_OBJECTS-1) state<=BUILD;else index<=index+1;
                end
            end
            BUILD: begin
                member_count=0;mask=0;a=-1;b=-1;
                for(i=0;i<3;i=i+1) if(match_totals[i]!=0) begin
                    member_count=member_count+1;mask[i]=1;if(a<0)a=found[i];else b=found[i];
                end
                if(match_totals[0]>1||match_totals[1]>1||match_totals[2]>1) begin reject_code<=5;state<=REJECT;end
                else if(member_count==1) begin used[anchor]<=1;dropped=dropped+1;disagreement=1;anchor<=anchor+1;state<=ANCHOR;end
                else if(n>=MAX_OBJECTS) begin reject_code<=2;state<=REJECT;end
                else begin load_lane<=0;state<=GATHER;end
            end
            GATHER: begin
                if(found[load_lane]>=0)begin member_left[load_lane]<=source_left;member_right[load_lane]<=source_right;end
                else begin member_left[load_lane]<=0;member_right[load_lane]<=0;end
                if(load_lane==2)state<=SUPPORT_BOUNDS;else load_lane<=load_lane+1'b1;
            end
            SUPPORT_BOUNDS: begin
                lower_left<=lower_bound(member_left[1],tolerance);upper_left<=upper_bound(member_left[1],tolerance);
                lower_right<=lower_bound(member_right[1],tolerance);upper_right<=upper_bound(member_right[1],tolerance);
                state<=RESOLVE;
            end
            RESOLVE: begin
                if(member_count==3&&!triple_close) begin reject_code<=5;state<=REJECT;end
                else begin
                    if(member_count==3) begin
                        vl=median3(member_left[0],member_left[1],member_left[2]);
                        vr=median3(member_right[0],member_right[1],member_right[2]);
                    end else begin
                        a=mask[0]?0:1;b=mask[2]?2:1;
                        vl=({1'b0,member_left[a]}+{1'b0,member_left[b]})>>1;
                        vr=({1'b0,member_right[a]}+{1'b0,member_right[b]})>>1;disagreement=1;
                    end
                    wl[n]<=vl;wr[n]<=vr;ws[n]<=mask;n=n+1;
                    for(i=0;i<3;i=i+1) if(found[i]>=0)used[found[i]]<=1;
                    anchor<=anchor+1;state<=ANCHOR;
                end
            end
            SORT: begin
                if(n<2||sort_i>=n) begin verify_i<=0;state<=VERIFY;end
                else if(sort_j+1<n) begin
                    if(wl[sort_j]>wl[sort_j+1]) begin
                        tmp_l=wl[sort_j];tmp_r=wr[sort_j];tmp_s=ws[sort_j];
                        wl[sort_j]<=wl[sort_j+1];wr[sort_j]<=wr[sort_j+1];ws[sort_j]<=ws[sort_j+1];
                        wl[sort_j+1]<=tmp_l;wr[sort_j+1]<=tmp_r;ws[sort_j+1]<=tmp_s;
                    end
                    sort_j<=sort_j+1;
                end else begin sort_i<=sort_i+1;sort_j<=0;end
            end
            VERIFY: begin
                if(verify_i>=n) state<=PUBLISH;
                else if(wl[verify_i]>wr[verify_i]||(verify_i>0&&wl[verify_i]<=wr[verify_i-1])) begin reject_code<=6;state<=REJECT;end
                else verify_i<=verify_i+1;
            end
            PUBLISH: begin
                out_valid<=1;
                if(!LOCAL_PAYLOAD)begin
                out_tag<=tag;out_count<=n;out_lefts<=0;out_rights<=0;out_support<=0;
                for(i=0;i<MAX_OBJECTS;i=i+1) if(i<n) begin out_lefts[16*i+:16]<=wl[i];out_rights[16*i+:16]<=wr[i];out_support[3*i+:3]<=ws[i];end
                end
                if(disagreement)disagreement_frames<=disagreement_frames+1'b1;
                dropped_objects<=dropped_objects+dropped;state<=IDLE;
            end
            REJECT: begin fault<=1;fault_sticky<=1;fault_reason<=reject_code;rejected_frames<=rejected_frames+1'b1;state<=IDLE;end
            default:state<=IDLE;
            endcase
            end
        end
    end
endmodule
