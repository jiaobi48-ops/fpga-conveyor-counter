`timescale 1ns/1ps
// 0=raw pass-through, 1=median5, 2=consecutive N, 3=invalid.
// ce is intentionally absent: a result_update is one physical-clock event.
module count_stabilizer (
    input wire clk,rst_n,flush,in_update,
    input wire [31:0] in_frame_id,in_epoch,
    input wire [31:0] in_history_epoch,
    input wire [15:0] in_count,
    input wire [1:0] cfg_mode,
    input wire [7:0] cfg_confirm,
    output reg stable_valid,stable_update,stable_changed,
    output reg [15:0] stable_count,
    output reg [31:0] stable_frame_id,stable_epoch,
    output reg [7:0] history_fill,
    output reg [31:0] duplicate_results,stale_results,gap_resets,
    output reg [31:0] stable_history_epoch,
    output reg stable_current_confirmed,
    output wire stable_pending
);
    reg seen;
    reg [31:0] previous_id,epoch,history_epoch;
    reg [1:0] mode;
    reg [7:0] confirm,fill;
    reg [15:0] h0,h1,h2,h3,candidate,latest_count;
    reg [7:0] streak;
    wire context_same=seen&&in_epoch==epoch&&in_history_epoch==history_epoch&&cfg_mode==mode&&cfg_confirm==confirm;
    wire duplicate=context_same&&in_frame_id==previous_id;
    wire [31:0] distance=in_frame_id-previous_id;
    wire stale=context_same&&distance[31];
    wire gap=context_same&&!duplicate&&!stale&&distance!=1;
    wire restart=!context_same||gap;
    wire legal=cfg_mode!=3&&(cfg_mode!=2||cfg_confirm!=0);
    wire take=in_update&&!flush&&!duplicate&&!stale&&legal;
    wire median_input=take&&cfg_mode==1&&!restart&&fill>=4;
    wire median_valid;
    wire [15:0] median_value;
    wire [95:0] median_tag;
    // A history break cancels all older pending median results.
    wire cancel=flush||(in_update&&!duplicate&&!stale&&(restart||!legal));
    median5_pipeline #(.TAG_WIDTH(96)) median_stage(.clk(clk),.rst_n(rst_n),.flush(cancel),
        .in_valid(median_input),.a(h0),.b(h1),.c(h2),.d(h3),.e(in_count),
        .in_tag({in_history_epoch,in_epoch,in_frame_id}),.out_valid(median_valid),
        .median(median_value),.out_tag(median_tag));
    wire [8:0] next_streak=(!restart&&candidate==in_count) ?
                           {1'b0,streak}+1'b1 : 9'd1;
    // valid means a held confirmed result exists. pending independently says
    // the latest accepted raw candidate has not yet been confirmed.
    assign stable_pending=seen&&!stable_current_confirmed;
    always @(posedge clk) begin
        if(!rst_n) begin
            seen<=0;previous_id<=0;epoch<=0;history_epoch<=0;mode<=0;confirm<=0;fill<=0;
            h0<=0;h1<=0;h2<=0;h3<=0;candidate<=0;streak<=0;
            stable_valid<=0;stable_update<=0;stable_changed<=0;stable_count<=0;
            stable_frame_id<=0;stable_epoch<=0;history_fill<=0;
            duplicate_results<=0;stale_results<=0;gap_resets<=0;
            stable_history_epoch<=0;stable_current_confirmed<=0;latest_count<=0;
        end else begin
            stable_update<=0;stable_changed<=0;
            if(flush) begin seen<=0;fill<=0;streak<=0;history_fill<=0;stable_valid<=0;stable_current_confirmed<=0;end
            else begin
                if(median_valid&&!cancel) begin
                    stable_update<=1;stable_changed<=!stable_valid||stable_count!=median_value;
                    stable_valid<=1;stable_count<=median_value;
                    stable_epoch<=median_tag[63:32];stable_frame_id<=median_tag[31:0];
                    stable_history_epoch<=median_tag[95:64];
                    stable_current_confirmed<=median_tag[31:0]==previous_id&&median_tag[63:32]==epoch&&
                        median_tag[95:64]==history_epoch&&median_value==latest_count;
                end
                if(in_update) begin
                    if(duplicate) duplicate_results<=duplicate_results+1'b1;
                    else if(stale) stale_results<=stale_results+1'b1;
                    else if(!legal) begin seen<=0;fill<=0;streak<=0;history_fill<=0;stable_valid<=0;stable_current_confirmed<=0;end
                    else begin
                        seen<=1;previous_id<=in_frame_id;epoch<=in_epoch;history_epoch<=in_history_epoch;
                        mode<=cfg_mode;confirm<=cfg_confirm;latest_count<=in_count;stable_current_confirmed<=0;
                        if(restart) begin
                            fill<=1;h0<=in_count;h1<=0;h2<=0;h3<=0;stable_valid<=0;
                            if(gap) gap_resets<=gap_resets+1'b1;
                        end else begin
                            if(fill<5) fill<=fill+1'b1;
                            h3<=h2;h2<=h1;h1<=h0;h0<=in_count;
                        end
                        if(cfg_mode==0) begin
                            history_fill<=1;stable_valid<=1;stable_update<=1;
                            stable_changed<=restart||!stable_valid||stable_count!=in_count;
                            stable_count<=in_count;stable_frame_id<=in_frame_id;stable_epoch<=in_epoch;
                            stable_history_epoch<=in_history_epoch;stable_current_confirmed<=1;
                        end else if(cfg_mode==1) history_fill<=restart ? 1 : (fill<5 ? fill+1'b1 : fill);
                        else begin
                            candidate<=in_count;
                            streak<=next_streak>255 ? 8'd255 : next_streak[7:0];
                            history_fill<=next_streak>255 ? 8'd255 : next_streak[7:0];
                            if(next_streak>=cfg_confirm) begin
                                stable_valid<=1;stable_update<=1;
                                stable_changed<=restart||!stable_valid||stable_count!=in_count;
                                stable_count<=in_count;stable_frame_id<=in_frame_id;stable_epoch<=in_epoch;
                                stable_history_epoch<=in_history_epoch;stable_current_confirmed<=1;
                            end
                        end
                    end
                end
            end
        end
    end
endmodule
