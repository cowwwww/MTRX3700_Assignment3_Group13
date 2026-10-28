// Estimate image movement in pixels. This does not measure robot travel in mm.
// Compare an N*N reference block with each N*N window in a (N+2R)*(N+2R) area.
// Load each array in address order. Address 0 starts or restarts a load.
// Write only when load_ready is high. Start a calculation only when ready is high.
// dx and dy give the current image shift from the centred reference position.
// The match-quality limits are starting values and still need hardware testing.
module image_translation_sad #(
 parameter integer N=16,R=4,S=N+2*R,RA=$clog2(N*N),SA=$clog2(S*S),
 parameter integer DW=$clog2(2*R+1)+1,SW=$clog2(N*N*255+1),
 parameter integer MAX_MEAN_ERROR=20,MIN_MARGIN=512,MIN_CONTRAST=32
)(
 input logic clk,reset,
 input logic reference_write,search_write,
 input logic [RA-1:0] reference_address,
 input logic [SA-1:0] search_address,
 input logic [7:0] reference_gray,search_gray,
 input logic start,
 input logic [15:0] reference_frame_id,current_frame_id,
 output logic load_ready,ready,busy,result_valid,motion_valid,at_search_boundary,
 output logic signed [DW-1:0] dx,dy,
 output logic [SW-1:0] best_sad,second_sad,
 output logic [7:0] reference_contrast,
 output logic [15:0] result_reference_id,result_current_id
);
 localparam integer NP=N*N,SP=S*S,OW=$clog2(2*R+1);
 localparam logic [1:0] IDLE=0,ISSUE=1,ACCUMULATE=2,FINISH=3;
 (* ramstyle="M10K" *) logic [7:0] reference_memory[0:NP-1];
 (* ramstyle="M10K" *) logic [7:0] search_memory[0:SP-1];
 logic [1:0] state;
 logic reference_loaded,search_loaded,reference_loading,search_loading;
 logic [RA-1:0] next_reference,pixel_index;
 logic [SA-1:0] next_search,search_read_address;
 logic [OW-1:0] offset_x,offset_y,best_x,best_y;
 logic [7:0] reference_read,search_read,minimum_gray,maximum_gray,difference;
 logic [SW-1:0] sum,trial_sum;
 wire reference_ordered=reference_address==0 ||
                       (reference_loading && reference_address==next_reference);
 wire search_ordered=search_address==0 || (search_loading && search_address==next_search);
 always_comb begin
  load_ready=state==IDLE && !reset;
  ready=load_ready && reference_loaded && search_loaded && !reference_write && !search_write;
  busy=state!=IDLE;
  search_read_address=SA'((int'(pixel_index)/N+int'(offset_y))*S+
                         int'(pixel_index)%N+int'(offset_x));
  difference=reference_read>=search_read ? reference_read-search_read:search_read-reference_read;
  trial_sum=sum+SW'(difference);
 end
 // Leave RAM unchanged on reset. Wait for a complete block loaded in order.
 always_ff @(posedge clk) begin
  if(load_ready && reference_write && reference_ordered && int'(reference_address)<NP)
   reference_memory[reference_address]<=reference_gray;
  if(load_ready && search_write && search_ordered && int'(search_address)<SP)
   search_memory[search_address]<=search_gray;
  if(state==ISSUE) begin
   reference_read<=reference_memory[pixel_index];search_read<=search_memory[search_read_address];
  end
 end
 always_ff @(posedge clk) begin
  result_valid<=0;
  if(reset) begin
   state<=IDLE;reference_loaded<=0;search_loaded<=0;reference_loading<=0;search_loading<=0;
   next_reference<=0;next_search<=0;pixel_index<=0;offset_x<=0;offset_y<=0;best_x<=0;best_y<=0;
   sum<=0;best_sad<='1;second_sad<='1;minimum_gray<=255;maximum_gray<=0;
   result_valid<=0;motion_valid<=0;at_search_boundary<=0;dx<=0;dy<=0;reference_contrast<=0;
   result_reference_id<=0;result_current_id<=0;
  end else begin
   if(load_ready && reference_write) begin
    reference_loaded<=0;
    if(reference_ordered && int'(reference_address)<NP) begin
     reference_loading<=reference_address!=RA'(NP-1);
     reference_loaded<=reference_address==RA'(NP-1);next_reference<=reference_address+1'b1;
    end else reference_loading<=0;
   end
   if(load_ready && search_write) begin
    search_loaded<=0;
    if(search_ordered && int'(search_address)<SP) begin
     search_loading<=search_address!=SA'(SP-1);
     search_loaded<=search_address==SA'(SP-1);next_search<=search_address+1'b1;
    end else search_loading<=0;
   end
   case(state)
    IDLE: if(start && ready) begin
     state<=ISSUE;pixel_index<=0;offset_x<=0;offset_y<=0;sum<=0;
     best_sad<='1;second_sad<='1;best_x<=0;best_y<=0;minimum_gray<=255;maximum_gray<=0;
     motion_valid<=0;result_reference_id<=reference_frame_id;result_current_id<=current_frame_id;
    end
    ISSUE: state<=ACCUMULATE;
    ACCUMULATE: begin
     if(offset_x==0 && offset_y==0) begin
      if(reference_read<minimum_gray) minimum_gray<=reference_read;
      if(reference_read>maximum_gray) maximum_gray<=reference_read;
     end
     if(pixel_index==RA'(NP-1)) begin
      if(trial_sum<best_sad) begin
       second_sad<=best_sad;best_sad<=trial_sum;best_x<=offset_x;best_y<=offset_y;
      end else if(trial_sum<second_sad) second_sad<=trial_sum;
      sum<=0;pixel_index<=0;
      if(offset_x==OW'(2*R) && offset_y==OW'(2*R)) state<=FINISH;
      else begin
       if(offset_x==OW'(2*R)) begin offset_x<=0;offset_y<=offset_y+1'b1;end
       else offset_x<=offset_x+1'b1;
       state<=ISSUE;
      end
     end else begin sum<=trial_sum;pixel_index<=pixel_index+1'b1;state<=ISSUE;end
    end
    FINISH: begin
     dx<=DW'(int'(best_x)-R);dy<=DW'(int'(best_y)-R);
     reference_contrast<=maximum_gray-minimum_gray;
     at_search_boundary<=best_x==0 || best_y==0 || best_x==OW'(2*R) || best_y==OW'(2*R);
     motion_valid<=int'(best_sad)<=NP*MAX_MEAN_ERROR &&
                   int'(second_sad)-int'(best_sad)>=MIN_MARGIN &&
                   int'(maximum_gray)-int'(minimum_gray)>=MIN_CONTRAST &&
                   result_reference_id!=result_current_id;
     result_valid<=1;state<=IDLE;
    end
    default: state<=IDLE;
   endcase
  end
 end
endmodule
