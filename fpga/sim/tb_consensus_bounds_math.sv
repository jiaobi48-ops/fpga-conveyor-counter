`timescale 1ns/1ps
module tb_consensus_bounds_math;
 interval_consensus3 dut(.clk(1'b0),.rst_n(1'b0),.flush(1'b0),.cfg_enable(1'b0),.cfg_tolerance(16'd0));
 integer checks=0,i,j,k;reg [15:0] edge_value[0:5];reg [15:0] a,b,t,lo,hi;integer distance;reg actual;
 task check(input reg [15:0] probe,base,tolerance);
  begin
   lo=dut.lower_bound(base,tolerance);hi=dut.upper_bound(base,tolerance);
   if(probe>=base)distance=int'(probe)-int'(base);else distance=int'(base)-int'(probe);
   actual=probe>=lo&&probe<=hi;
   if(actual!==(distance<=tolerance))$fatal(1,"FAIL CONSENSUS BOUNDS a=%0d b=%0d t=%0d lo=%0d hi=%0d",probe,base,tolerance,lo,hi);
   checks++;
  end
 endtask
 initial begin
  edge_value[0]=0;edge_value[1]=1;edge_value[2]=32767;edge_value[3]=32768;edge_value[4]=65534;edge_value[5]=65535;
  for(i=0;i<6;i++)for(j=0;j<6;j++)for(k=0;k<6;k++)check(edge_value[i],edge_value[j],edge_value[k]);
  for(i=0;i<50000;i++)begin a=$urandom;b=$urandom;t=$urandom;check(a,b,t);end
  $display("PASS CONSENSUS BOUNDS checks=%0d uint16_edges/saturation/random_absolute_distance_reference",checks);$finish;
 end
endmodule
