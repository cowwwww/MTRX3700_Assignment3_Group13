// Read camera bytes and turn them into grayscale pixels.
// Camera register setup (SCCB), XCLK and board pins must be connected separately.
// Check the byte order and signal polarity against the supplied camera setup.
// Formats: 0=gray8, 1=RGB565, 2=YUV422 (one Y byte per two bytes), 3=unsupported.
// Save the settings when VSYNC becomes active. Wait for VSYNC after reset.
// Each HREF line must contain exactly W pixels. Hold the last pixel until HREF
// falls so an extra pixel or incomplete byte pair cannot mark the frame as valid.
module camera_byte_capture #(
 parameter integer W=320,H=240,XW=$clog2(W),YW=$clog2(H),VSYNC_ACTIVE_HIGH=1
)(
 input logic cam_clk,reset,href,vsync,
 input logic [7:0] data,
 input logic [1:0] pixel_format,
 input logic rgb_msb_first,y_first,
 output logic pixel_valid,sof,eof,frame_abort,
 output logic [7:0] gray,
 output logic [XW-1:0] x,
 output logic [YW-1:0] y
);
 logic prev_vsync,prev_href,accept_frame,started,phase,pending_last;
 logic [1:0] format_q;
 logic msb_q,y_first_q;
 logic [7:0] first_byte,last_gray;
 logic [XW:0] line_pixels;
 logic [YW-1:0] line_y;
 logic [15:0] rgb;
 logic [7:0] r8,g8,b8,converted;
 logic [9:0] luminance;
 wire active_vsync=(VSYNC_ACTIVE_HIGH!=0) ? vsync : !vsync;
 wire complete_byte=format_q==0 || phase;
 always_comb begin
  rgb=msb_q ? {first_byte,data} : {data,first_byte};
  r8={rgb[15:11],rgb[15:13]};g8={rgb[10:5],rgb[10:9]};b8={rgb[4:0],rgb[4:2]};
  luminance={2'b0,r8}+{1'b0,g8,1'b0}+{2'b0,b8};
  case(format_q)
   0: converted=data;
   1: converted=luminance[9:2];
   2: converted=y_first_q ? first_byte : data;
   default: converted=0;
  endcase
 end
 always_ff @(posedge cam_clk) begin
  pixel_valid<=0;sof<=0;eof<=0;frame_abort<=0;
  if(reset) begin
   prev_vsync<=0;prev_href<=0;accept_frame<=0;started<=0;phase<=0;pending_last<=0;
   format_q<=0;msb_q<=1;y_first_q<=1;first_byte<=0;last_gray<=0;
   line_pixels<=0;line_y<=0;gray<=0;x<=0;y<=0;
  end else begin
   prev_vsync<=active_vsync;prev_href<=href;
   if(active_vsync) begin
    if(!prev_vsync) begin
     frame_abort<=(accept_frame && started) || pixel_format==3;
     accept_frame<=pixel_format!=3;started<=0;
     format_q<=pixel_format;msb_q<=rgb_msb_first;y_first_q<=y_first;
    end
    phase<=0;line_pixels<=0;line_y<=0;pending_last<=0;prev_href<=0;
   end else if(accept_frame) begin
    if(href) begin
     started<=1;
     if(format_q!=0) begin phase<=!phase;if(!phase) first_byte<=data;end
     if(complete_byte) begin
      if(line_pixels>=(XW+1)'(W)) begin
       frame_abort<=1;accept_frame<=0;pending_last<=0;
      end else begin
       line_pixels<=line_pixels+1'b1;
       if(line_pixels==(XW+1)'(W-1) && line_y==YW'(H-1)) begin
        pending_last<=1;last_gray<=converted;
       end else begin
        pixel_valid<=1;gray<=converted;x<=line_pixels[XW-1:0];y<=line_y;
        sof<=line_pixels==0 && line_y==0;
       end
      end
     end
    end else if(prev_href) begin
     if(line_pixels!=(XW+1)'(W) || phase) begin
      frame_abort<=1;accept_frame<=0;pending_last<=0;
     end else if(line_y==YW'(H-1)) begin
      pixel_valid<=pending_last;eof<=pending_last;gray<=last_gray;
      x<=XW'(W-1);y<=YW'(H-1);accept_frame<=0;pending_last<=0;
     end else begin line_y<=line_y+1'b1;line_pixels<=0;phase<=0;end
    end
   end
  end
 end
endmodule
