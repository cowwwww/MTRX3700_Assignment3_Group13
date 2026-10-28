// Divide unsigned numbers by shifting and subtracting, one bit per clock.
// Accept start only when busy is low. The result takes WIDTH clock cycles.
// If the denominator is zero, return zero and set divide_by_zero.
module unsigned_divider #(parameter integer WIDTH=18)(
 input logic clk, reset, start,
 input logic [WIDTH-1:0] numerator, denominator,
 output logic busy, done, divide_by_zero,
 output logic [WIDTH-1:0] quotient
);
 localparam integer CW=$clog2(WIDTH+1);
 logic [WIDTH-1:0] dividend, divisor, work_q;
 logic [WIDTH:0] remainder, trial;
 logic [CW-1:0] remaining;
 always_comb trial={remainder[WIDTH-1:0],dividend[WIDTH-1]};
 always_ff @(posedge clk) begin
  done<=0;
  if(reset) begin
   busy<=0; done<=0; quotient<=0; divide_by_zero<=0;
   dividend<=0; divisor<=0; work_q<=0; remainder<=0; remaining<=0;
  end else if(start && !busy) begin
   dividend<=numerator; divisor<=denominator; work_q<=0; remainder<=0;
   remaining<=CW'(WIDTH); divide_by_zero<=denominator==0;
   busy<=1;
  end else if(busy) begin
   dividend<=dividend<<1;
   if(trial>={1'b0,divisor}) begin
    remainder<=trial-{1'b0,divisor}; work_q<={work_q[WIDTH-2:0],1'b1};
   end else begin
    remainder<=trial; work_q<={work_q[WIDTH-2:0],1'b0};
   end
   remaining<=remaining-1'b1;
   if(remaining==1) begin
    quotient<=divide_by_zero ? '0 : {work_q[WIDTH-2:0],trial>={1'b0,divisor}};
    busy<=0; done<=1;
   end
  end
 end
endmodule
