#include "Vverification_top.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

static void check(bool condition,const std::string& label) {
 if(!condition) throw std::runtime_error("CHECK FAILED: "+label);
}
static int signed16(unsigned v) { return static_cast<int16_t>(v); }
struct Feature { unsigned good,valid,junction,centroids,counts,id; };
struct Packet { int left,right; unsigned flags; uint64_t time; };
struct Pixel { unsigned x,y,gray,sof,eof; };

struct Simulation {
 Vverification_top d;
 uint64_t time=0,cycles=0;
 bool freeze_control=false,freeze_video=false,previous_tx=true;
 int rx_count=0,rx_bit=-1;
 unsigned rx_byte=0;
 std::vector<unsigned> wire_bytes;
 std::vector<Feature> features;
 std::vector<Packet> packets;
 std::vector<Pixel> captured;
 unsigned capture_errors=0;
 void receive(bool tx) {
  if(rx_bit<0) {
   if(previous_tx && !tx) {rx_count=6;rx_bit=0;rx_byte=0;}
  } else if(--rx_count==0) {
   if(rx_bit<8) {rx_byte|=unsigned(tx)<<rx_bit;rx_bit++;rx_count=4;}
   else {
    if(tx) {
     wire_bytes.push_back(rx_byte);
     while(wire_bytes.size()>=7) {
      unsigned xor_sum=0;for(int i=0;i<6;i++) xor_sum^=wire_bytes[i];
      if(wire_bytes[0]==0xa5 && xor_sum==wire_bytes[6]) {
       packets.push_back({signed16(wire_bytes[1]|(wire_bytes[2]<<8)),signed16(wire_bytes[3]|(wire_bytes[4]<<8)),wire_bytes[5],cycles});
       wire_bytes.erase(wire_bytes.begin(),wire_bytes.begin()+7);
      } else wire_bytes.erase(wire_bytes.begin());
     }
    }
    rx_bit=-1;
   }
  }
  previous_tx=tx;
 }
 void step() {
  bool old_clk=d.clk,old_cam=d.cam_clk;
  ++time;d.clk=freeze_control ? 0 : (time%10>=5);d.cam_clk=(time%14>=7);
  d.video_clk=freeze_video ? 0 : (time%22>=11);d.eval();
  if(!old_cam && d.cam_clk) {
   if(d.cap_valid) captured.push_back({d.cap_x,d.cap_y,d.cap_gray,d.cap_sof,d.cap_eof});
   if(d.cap_abort) ++capture_errors;
  }
  if(!old_clk && d.clk) {
   ++cycles;
   if(d.arst) {rx_bit=-1;previous_tx=true;wire_bytes.clear();}
   else receive(d.mock_tx);
   if(d.debug_feature_valid) features.push_back({d.debug_frame_good,d.debug_row_valid,d.debug_junction,d.debug_centroids,d.debug_counts,d.debug_frame_id});
  }
 }
 void tick(unsigned n=1) {while(n--) {uint64_t target=cycles+1;while(cycles<target) step();}}
 void cam_sample(bool valid,unsigned x=0,unsigned y=0,unsigned v=255,bool sof=false,bool eof=false) {
  bool old=d.cam_clk;
  do {old=d.cam_clk;step();} while(!(old && !d.cam_clk));
  d.pixel_valid=valid;d.x=x;d.y=y;d.gray=v;d.sof=sof;d.eof=eof;d.eval();
  do {step();} while(!d.cam_clk);
 }
 void raw_cycle(bool href,bool vsync,unsigned byte=0) {
  bool old=d.cam_clk;
  do {old=d.cam_clk;step();} while(!(old && !d.cam_clk));
  d.cap_href=href;d.cap_vsync=vsync;d.cap_data=byte;d.eval();
  do {step();} while(!d.cam_clk);
 }
 void raw_frame(unsigned format,bool msb=true,bool y_first=true) {
  d.cap_format=format;d.cap_msb=msb;d.cap_y_first=y_first;
  raw_cycle(false,true);raw_cycle(false,true);raw_cycle(false,false);
  for(unsigned yy=0;yy<16;yy++) {
   for(unsigned xx=0;xx<32;xx++) {
    unsigned g=(xx>=17 && xx<=19) ? 0:255;
    if(format==0) raw_cycle(true,false,g);
    else if(format==1) {
     unsigned word=g ? 0xffff:0;
     raw_cycle(true,false,msb ? word>>8:word&255);raw_cycle(true,false,msb ? word&255:word>>8);
    } else {
     raw_cycle(true,false,y_first ? g:101);raw_cycle(true,false,y_first ? 101:g);
    }
   }
   raw_cycle(false,false);raw_cycle(false,false);
  }
  tick(60);
 }
 void reset() {
  freeze_control=false;freeze_video=false;d.arst=1;d.unit_reset=1;d.pixel_valid=0;d.sof=0;d.eof=0;
  d.stop_event=0;d.release_event=0;d.bypass=1;d.sensor_required=0;
  d.frame_abort=0;d.use_capture=0;d.cap_href=0;d.cap_vsync=0;d.cap_data=0;
  d.cap_format=0;d.cap_msb=1;d.cap_y_first=1;
  d.fb_swap=0;d.fb_read=0;d.fb_address=0;
  d.distance_sample=0;d.distance_valid=0;d.distance_mm=1000;d.dark_line=1;d.threshold=96;
  d.unit_inhibit=1;d.unit_steering=0;d.unit_speed=0;d.unit_centroids=0;
  d.unit_uart_valid=0;d.unit_uart_abort=0;d.unit_uart_data=0;
  d.div_start=0;d.div_n=0;d.div_d=0;d.j_present=0;d.j_request=0;d.j_key=0;d.j_available=0;
  d.d_sample=0;d.d_valid=0;d.d_mm=0;
  tick(8);d.arst=0;d.unit_reset=0;tick(10);features.clear();packets.clear();captured.clear();capture_errors=0;
 }
 void release() {d.release_event=1;tick();d.release_event=0;tick();}
 void frame(const std::vector<unsigned>& pixels,bool malformed=false,bool gaps=false) {
  for(unsigned y=0;y<16;y++) for(unsigned x=0;x<32;x++) {
   unsigned px=(malformed && x==5 && y==6) ? 4:x;
   cam_sample(true,px,y,pixels[y*32+x],x==0 && y==0,x==31 && y==15);
   if(gaps && (x+y)%7==0) cam_sample(false);
  }
  cam_sample(false);tick(50);
 }
 void line(int far_x,int mid_x,int near_x,unsigned width=3) {
  std::vector<unsigned> p(512,220);
  const std::array<int,3> centers={far_x,mid_x,near_x};
  for(int r=0;r<3;r++) for(int x=0;x<32;x++)
   if(x>=centers[r]-int(width)/2 && x<centers[r]+int(width+1)/2) p[(r+1)*4*32+x]=20;
  frame(p);
 }
 void recover(int far_x=16,int mid_x=16,int near_x=16) {for(int i=0;i<3;i++) line(far_x,mid_x,near_x);}
 void expect_stop(const std::string& why) {d.eval();check(d.inhibited && d.motor_left==0 && d.motor_right==0,why);}
};

void test_safety(Simulation& s) {
 s.reset();check(s.d.unit_stopped,"reset must latch stop");
 bool expected=true;std::mt19937 rng(3700);
 for(int i=0;i<600;i++) {
  bool stop=(rng()%5)==0,release=(rng()%4)==0;
  s.d.stop_event=stop;s.d.release_event=release;s.tick();
  if(stop) expected=true;else if(release) expected=false;
  check(s.d.unit_stopped==expected,"stop priority / latched release");
 }
 std::cout<<"PASS safety latch: 600 sequences, reset and simultaneous keys\n";
}
void test_motor_curve(Simulation& s) {
 s.reset();
 for(int v : {0,1,96,200,255}) for(int e : {-32768,-1000,-200,-1,0,1,200,1000,32767}) {
  s.d.unit_speed=v;s.d.unit_steering=uint16_t(e);s.d.unit_inhibit=0;s.d.eval();
  check(signed16(s.d.unit_left)==std::clamp(v+2*e,-255,255),"left saturation/sign");
  check(signed16(s.d.unit_right)==std::clamp(v-2*e,-255,255),"right saturation/sign");
  s.d.unit_inhibit=1;s.d.eval();check(s.d.unit_left==0 && s.d.unit_right==0,"motor inhibit zero");
 }
 for(int f=0;f<32;f++) for(int m=0;m<32;m++) for(int n=0;n<32;n++) {
  s.d.unit_centroids=f|(m<<5)|(n<<10);s.d.eval();
  // Check the curve formula using a separate Lagrange calculation; round toward zero.
  double target=-0.125*n+0.75*m+0.375*f;
  check(signed16(s.d.unit_advanced)==std::clamp(int(target),0,31)-16,"quadratic target");
  check(signed16(s.d.unit_basic)==n-16,"basic target");
  check(signed16(s.d.unit_heading)==f-n,"heading");
  check(signed16(s.d.unit_curvature)==n-2*m+f,"curvature");
 }
 std::cout<<"PASS motor saturation/stop + exhaustive 32768 curve inputs\n";
}
void test_divider(Simulation& s) {
 s.reset();std::mt19937 rng(42);
 for(int i=0;i<220;i++) {
  unsigned n=rng()%262144,d=i%19==0 ? 0:rng()%262144;
  s.d.div_n=n;s.d.div_d=d;s.d.div_start=1;s.tick();s.d.div_start=0;
  unsigned ticks=0;while(!s.d.div_done && ticks<20) {s.tick();ticks++;}
  check(ticks==18 && !s.d.div_busy,"divider exact latency");
  check(s.d.div_q==(d ? n/d:0) && bool(s.d.div_zero)==(d==0),"divider arithmetic");s.tick();
 }
 std::cout<<"PASS restoring divider: 220 cases incl zero denominator\n";
}
void test_uart(Simulation& s) {
 s.reset();
 for(unsigned b=0;b<256;b++) {
  check(s.d.unit_uart_ready,"UART idle ready");
  s.d.unit_uart_data=b;s.d.unit_uart_valid=1;s.tick();s.d.unit_uart_valid=0;
  unsigned bits=(1<<9)|(b<<1);
  for(int i=0;i<40;i++) {
   check(s.d.unit_uart_busy && !s.d.unit_uart_ready,"UART busy during byte");
   check(s.d.unit_uart_tx==((bits>>(i/4))&1),"UART exact 8N1 wire bits");s.tick();
  }
  check(s.d.unit_uart_ready && s.d.unit_uart_tx,"UART final idle");
 }
 for(unsigned phase=0;phase<40;phase++) {
  s.d.unit_uart_valid=1;s.d.unit_uart_data=0;s.tick();s.d.unit_uart_valid=0;s.tick(phase);
  s.d.unit_uart_abort=1;s.tick();check(s.d.unit_uart_tx && !s.d.unit_uart_busy,"UART abort every phase");
  s.d.unit_uart_abort=0;s.tick();
 }
 std::cout<<"PASS UART: all 256 bytes, bit timing, abort at 40 phases\n";
}
void test_distance_junction(Simulation& s) {
 s.reset();
 auto sample=[&](bool valid,unsigned mm) {s.d.d_valid=valid;s.d.d_mm=mm;s.d.d_sample=1;s.tick();s.d.d_sample=0;s.tick();};
 check(s.d.d_fault && s.d.d_blocked,"sensor reset unsafe");
 sample(true,300);sample(true,300);check(s.d.d_blocked,"distance debounce");sample(true,300);check(!s.d.d_fault && !s.d.d_blocked,"distance clear");
 sample(true,180);check(s.d.d_blocked,"distance inclusive stop threshold");
 sample(true,240);sample(true,210);sample(true,240);sample(true,240);check(s.d.d_blocked,"distance hysteresis resets sequence");
 sample(true,240);check(!s.d.d_blocked,"distance release threshold");
 s.tick(45);check(s.d.d_fault && s.d.d_blocked,"distance timeout");
 sample(true,300);check(s.d.d_blocked,"timeout requires full clear sequence");sample(true,300);sample(true,300);check(!s.d.d_blocked,"distance fresh recovery");
 sample(false,1000);check(s.d.d_fault && s.d.d_blocked,"invalid reading stops");
 auto visit=[&](unsigned key,unsigned avail) {
  s.d.j_present=0;s.d.j_request=0;s.tick();s.d.j_key=key;s.d.j_available=avail;s.d.j_present=1;s.d.j_request=1;s.tick();
 };
 visit(12,7);check(s.d.j_valid && s.d.j_choice==1 && !s.d.j_revisited,"new junction prefers straight");
 s.tick();check(!s.d.j_valid,"one choice per junction episode");
 visit(12,7);check(s.d.j_choice==0 && s.d.j_revisited,"remember earlier branch");
 visit(12,7);check(s.d.j_choice==2,"third branch");visit(12,7);check(s.d.j_choice==1,"new exploration round");
 visit(18,0);check(!s.d.j_valid,"no available branch");
 for(unsigned key=20;key<24;key++) visit(key,1);
 visit(12,7);check(!s.d.j_revisited && s.d.j_choice==1,"bounded memory eviction");
 std::cout<<"PASS distance validity/hysteresis/timeout + junction history/eviction\n";
}
void test_vision(Simulation& s,const char* vectors) {
 s.reset();std::ifstream in(vectors);check(bool(in),"open golden vectors");unsigned count;in>>count;
 for(unsigned c=0;c<count;c++) {
  unsigned dark,threshold,good,valid,junction,centroids,counts;
  in>>dark>>threshold>>good>>valid>>junction>>centroids>>counts;
  std::vector<unsigned> p(512);for(auto& v:p) in>>v;check(bool(in),"read golden vector");
  s.d.dark_line=dark;s.d.threshold=threshold;auto before=s.features.size();s.frame(p,false,true);
  check(s.features.size()==before+1,"one atomic feature per frame");auto f=s.features.back();
  check(f.good==good && f.valid==valid && f.junction==junction && f.centroids==centroids && f.counts==counts,
        "Python golden raster case "+std::to_string(c));
  check(f.id==c+1,"frame ID ordering across CDC");
 }
 std::vector<unsigned> p(512,20);s.frame(p,true);check(!s.features.back().good && s.features.back().valid==0,"malformed coordinate rejects frame");
 std::cout<<"PASS line detector: "<<count<<" Python reference frames, gaps, polarity, threshold, split lines + malformed raster\n";
}
void test_system(Simulation& s) {
 s.reset();s.expect_stop("reset motion stop");s.recover();s.expect_stop("frames cannot release latched safety");
 s.release();s.line(16,16,16);s.expect_stop("release requires 3 new frames");s.line(16,16,16);s.expect_stop("2 frames insufficient");s.line(16,16,16);
 check(!s.d.inhibited && signed16(s.d.motor_left)==96 && signed16(s.d.motor_right)==96,"camera drives centered basic command");
 s.line(22,20,18);check(signed16(s.d.motor_left)==100 && signed16(s.d.motor_right)==92,"right image steers right");
 s.line(10,12,14);check(signed16(s.d.motor_left)==92 && signed16(s.d.motor_right)==100,"left image steers left");
 s.line(24,20,16);check(signed16(s.d.motor_left)==96,"basic near centroid");s.d.bypass=0;s.d.eval();
 check(s.d.nav_state==2 && signed16(s.d.motor_left)>signed16(s.d.motor_right),"SW0 changes actual curve steering");
 s.tick(1800);check(!s.packets.empty(),"UART decoded packets exist");auto p=s.packets.back();
 check(p.left==signed16(s.d.motor_left) && p.right==signed16(s.d.motor_right) && p.flags==0,"camera to mock UART end-to-end");
 s.d.stop_event=1;s.d.release_event=1;s.d.eval();s.expect_stop("same-cycle stop overrides release");s.tick();s.d.stop_event=0;s.d.release_event=0;s.tick();
 s.expect_stop("latched stop remains");auto stop_cycle=s.cycles;s.tick(1100);
 check(s.packets.back().time>stop_cycle && s.packets.back().left==0 && s.packets.back().right==0 && s.packets.back().flags==1,"aborted UART replaced by zero packet");
 s.release();s.expect_stop("old features cannot restart after release");s.recover();check(!s.d.inhibited,"fresh frames recover after release");
 s.frame(std::vector<unsigned>(512,255));s.expect_stop("line lost stops");check(s.d.nav_state==3,"line-lost status");
 s.recover();check(!s.d.inhibited,"stationary visual reacquisition");s.tick(30010);s.expect_stop("camera watchdog stops stale image");
 s.line(16,16,16);s.expect_stop("watchdog reset requires new 3-frame sequence");s.line(16,16,16);s.line(16,16,16);check(!s.d.inhibited,"watchdog recovers");
 s.d.sensor_required=1;s.d.eval();s.expect_stop("missing distance stops");check(s.d.nav_state==4,"sensor fault status");
 for(int i=0;i<3;i++) {s.d.distance_sample=1;s.d.distance_valid=1;s.d.distance_mm=400;s.tick();s.d.distance_sample=0;s.tick();}
 s.recover();check(!s.d.inhibited,"valid distance and images enable movement");
 s.d.distance_sample=1;s.d.distance_mm=100;s.tick();s.d.distance_sample=0;s.tick();s.expect_stop("obstacle priority");check(s.d.nav_state==5,"obstacle state");
 s.d.stop_event=1;s.tick();s.d.stop_event=0;s.tick();check(s.d.nav_state==6,"e-stop wins obstacle state");
 s.reset();s.release();s.recover();s.tick(20);s.freeze_control=true;s.step();
 for(int frame=0;frame<2;frame++) {
  for(unsigned y=0;y<16;y++) for(unsigned x=0;x<32;x++)
   s.cam_sample(true,x,y,(x>=15 && x<=17) ? 20:220,x==0 && y==0,x==31 && y==15);
  for(int i=0;i<30;i++) s.cam_sample(false);
 }
 s.freeze_control=false;s.tick(20);check(s.d.cdc_fault,"CDC overrun becomes sticky fault");s.expect_stop("CDC overrun inhibits movement");
 s.release();s.recover();s.expect_stop("CDC fault needs reset");s.reset();check(!s.d.cdc_fault,"reset clears CDC fault");
 std::cout<<"PASS system: camera/CDC/control/UART, bypass, faults, release and recovery\n";
}

void test_stop_states(Simulation& s) {
 for(unsigned state=0;state<6;state++) {
  s.reset();s.release();
  if(state==1 || state==2 || state==3 || state==5) s.recover();
  if(state==2) s.d.bypass=0;
  if(state==3) s.frame(std::vector<unsigned>(512,255));
  if(state==4) s.d.sensor_required=1;
  if(state==5) {
   s.d.distance_sample=1;s.d.distance_valid=1;s.d.distance_mm=50;s.tick();
   s.d.distance_sample=0;s.d.sensor_required=1;s.tick();
  }
  s.d.eval();check(s.d.nav_state==state,"prepare navigation state "+std::to_string(state));
  s.d.stop_event=1;s.d.eval();s.expect_stop("direct stop from state "+std::to_string(state));
  check(s.d.nav_state==6,"stop state priority");s.tick();s.d.stop_event=0;s.tick(5);s.expect_stop("stop stays latched");
 }
 std::cout<<"PASS emergency stop from all six non-stop navigation states\n";
}

void test_capture(Simulation& s) {
 s.reset();s.d.use_capture=1;s.release();
 // Ignore HREF until the first VSYNC starts a frame.
 for(int i=0;i<12;i++) s.raw_cycle(true,false,0);
 check(s.captured.empty(),"capture waits for VSYNC");s.raw_cycle(false,false);
 for(unsigned format=0;format<3;format++) for(unsigned order=0;order<2;order++) {
  s.captured.clear();unsigned errors=s.capture_errors;
  s.raw_frame(format,order,order);
  check(s.captured.size()==512 && s.capture_errors==errors,"capture complete raster for each format/order");
  for(unsigned i=0;i<512;i++) {
   auto p=s.captured[i];
   check(p.x==i%32 && p.y==i/32 && p.sof==(i==0) && p.eof==(i==511),"capture coordinates and first/last alignment");
   check(p.gray==((p.x>=17 && p.x<=19) ? 0:255),"capture gray/RGB/YUV luminance");
  }
 }
 check(!s.d.inhibited && signed16(s.d.motor_left)==100 && signed16(s.d.motor_right)==92,"raw camera bytes to wheel command");
 check(!s.d.integrated_inhibited && signed16(s.d.integrated_left)==100 && signed16(s.d.integrated_right)==92,"integrated top shares one capture with motion");
 check(s.d.integrated_video_ready,"integrated top live display receives frames");
 // Reject a short line before the frame timeout is reached.
 unsigned errors=s.capture_errors;
 s.d.cap_format=0;s.raw_cycle(false,true);s.raw_cycle(false,false);
 for(int i=0;i<31;i++) s.raw_cycle(true,false,0);
 s.raw_cycle(false,false);s.tick(30);
 check(s.capture_errors==errors+1,"short camera line rejected");s.expect_stop("capture abort promptly invalidates controller");
 check(s.d.integrated_inhibited && s.d.integrated_left==0 && s.d.integrated_right==0,"integrated top rejects bad camera frame");
 check(!s.features.back().good,"capture abort crosses as invalid packet");
 for(int i=0;i<3;i++) s.raw_frame(0);check(!s.d.inhibited,"capture recovers after valid frame sequence");
 // An extra pixel in the final row must make the frame result invalid.
 s.captured.clear();errors=s.capture_errors;s.d.cap_format=0;s.raw_cycle(false,true);s.raw_cycle(false,false);
 for(unsigned y=0;y<16;y++) {
  for(unsigned x=0;x<(y==15 ? 33u:32u);x++) s.raw_cycle(true,false,0);
  s.raw_cycle(false,false);
 }
 s.tick(30);check(s.capture_errors==errors+1,"overlong final line rejected");
 check(std::none_of(s.captured.begin(),s.captured.end(),[](Pixel p){return p.eof;}),"EOF withheld until validated last HREF");
 s.expect_stop("overlong frame cannot drive");
 // Test an incomplete RGB/YUV byte pair and VSYNC arriving halfway through a line.
 for(unsigned format : {1u,2u}) {
  errors=s.capture_errors;s.d.cap_format=format;s.raw_cycle(false,true);s.raw_cycle(false,false);
  for(int i=0;i<63;i++) s.raw_cycle(true,false,i);
  s.raw_cycle(false,false);s.tick(30);check(s.capture_errors==errors+1,"half pixel rejected");
 }
 errors=s.capture_errors;s.d.cap_format=0;s.raw_cycle(false,true);s.raw_cycle(false,false);
 s.raw_cycle(true,false,10);s.raw_cycle(false,true);s.raw_cycle(false,true);s.tick(20);
 check(s.capture_errors==errors+1,"one abort for premature VSYNC");
 s.raw_cycle(false,false);s.d.cap_format=3;s.raw_cycle(false,true);s.raw_cycle(false,true);s.raw_cycle(false,false);
 errors=s.capture_errors;for(int i=0;i<40;i++) s.raw_cycle(true,false,10);
 check(s.capture_errors==errors,"unsupported format discards bytes without error flood");
 // Check colour conversion separately and change settings halfway through a frame.
 s.reset();s.d.cap_format=1;s.d.cap_msb=1;s.raw_cycle(false,true);s.raw_cycle(false,false);
 const std::array<unsigned,6> colors={0xf800,0x07e0,0x001f,0x7bef,0xffff,0};
 for(unsigned word:colors) {s.raw_cycle(true,false,word>>8);s.raw_cycle(true,false,word&255);}
 check(s.captured.size()==colors.size(),"RGB pairs produce one pixel");
 for(unsigned i=0;i<colors.size();i++) {
  unsigned w=colors[i],r=((w>>11)&31),g=((w>>5)&63),b=(w&31);
  r=(r*8)+(r/4);g=(g*4)+(g/16);b=(b*8)+(b/4);
  check(s.captured[i].gray==(r+2*g+b)/4,"RGB channel expansion and weighted luminance");
 }
 s.d.cap_format=0;s.raw_cycle(true,false,0xf8);s.raw_cycle(true,false,0);
 check(s.captured.back().gray==63,"format remains latched until VSYNC");
 s.reset();s.d.cap_format=1;s.d.cap_msb=0;s.raw_cycle(false,true);s.raw_cycle(false,false);
 s.raw_cycle(true,false,0);s.raw_cycle(true,false,0xf8);
 check(s.captured.size()==1 && s.captured[0].gray==63,"asymmetric RGB little-byte-first conversion");
 std::cout<<"PASS camera bytes: gray/RGB565/YUV422, byte order, coordinate alignment, aborts and raw-camera control loop\n";
}

void test_abort_pending(Simulation& s) {
 s.reset();s.release();
 for(unsigned y=0;y<16;y++) for(unsigned x=0;x<32;x++)
  s.cam_sample(true,x,y,(x>=15 && x<=17) ? 20:220,x==0 && y==0,x==31 && y==15);
 s.d.frame_abort=1;s.cam_sample(false);s.d.frame_abort=0;s.tick(70);
 check(s.features.size()==1 && !s.features[0].good && s.features[0].valid==0,"abort cancels in-progress centroid publication");
 s.expect_stop("aborted pending frame cannot enable motion");s.recover();check(!s.d.inhibited,"fresh frames after pending abort recover");
 std::cout<<"PASS pending-divider abort: no stale good feature published\n";
}

void test_display_independence(Simulation& s) {
 s.reset();s.d.use_capture=1;s.freeze_video=true;s.release();
 for(int i=0;i<6;i++) s.raw_frame(0);
 check(!s.d.integrated_video_ready,"stalled display has not accepted a bank");
 check(!s.d.integrated_inhibited && signed16(s.d.integrated_left)==100 && signed16(s.d.integrated_right)==92,
       "camera control continues while display ownership acknowledgement is stalled");
 s.d.stop_event=1;s.d.eval();
 check(s.d.integrated_inhibited && s.d.integrated_left==0 && s.d.integrated_right==0,
       "emergency stop remains independent of video clock");
 s.tick();s.d.stop_event=0;s.tick(3);
 s.freeze_video=false;s.tick(6000);
 check(s.d.integrated_video_ready,"display resumes and accepts complete waiting frame");
 check(s.d.integrated_inhibited,"display resume cannot release emergency stop");
 s.release();for(int i=0;i<3;i++) s.raw_frame(0);
 check(!s.d.integrated_inhibited,"fresh camera frames recover after separate release");
 std::cout<<"PASS three-clock integration: stalled VGA cannot block camera control or emergency stop\n";
}

void test_overlay(Simulation& s) {
 s.reset();s.d.unit_centroids=10|(16<<5)|(22<<10);s.d.pixel_valid=1;s.d.unit_inhibit=0;s.d.gray=73;
 s.d.x=0;s.d.y=3;s.d.eval();check(s.d.overlay_red==73 && s.d.overlay_green==73,"overlay preserves background");
 s.d.x=10;s.d.y=4;s.d.eval();check(s.d.overlay_red==255 && s.d.overlay_green==0,"centroid marker");
 s.d.x=0;s.d.y=8;s.d.eval();check(s.d.overlay_red==0 && s.d.overlay_green==180,"sample row marker");
 s.d.unit_inhibit=1;s.d.y=0;s.d.eval();check(s.d.overlay_red==255 && s.d.overlay_green==0,"stop stripe");
 s.d.pixel_valid=0;s.d.eval();check(s.d.overlay_red==0 && s.d.overlay_green==0 && s.d.overlay_blue==0,"blanking wins overlay");
 std::cout<<"PASS stream debug overlay: centroid, sampled row, stop stripe and blanking\n";
}

void test_frame_configuration(Simulation& s) {
 s.reset();s.d.threshold=96;s.d.dark_line=1;
 std::vector<unsigned> p(512,150);
 for(unsigned y=0;y<16;y++) for(unsigned x=0;x<32;x++) {
  unsigned gray=(x>=17 && x<=19) ? 80:150;p[y*32+x]=gray;
  if(y==2 && x==0) {s.d.threshold=20;s.d.dark_line=0;}
  s.cam_sample(true,x,y,gray,x==0 && y==0,x==31 && y==15);
 }
 s.cam_sample(false);s.tick(50);
 check(s.features.back().valid==7 && s.features.back().centroids==(18u|(18u<<5)|(18u<<10)),"detector configuration stays fixed for whole frame");
 s.frame(p);check(s.features.back().valid==0 && s.features.back().junction==7,"new threshold/polarity applied only at next SOF");
 std::cout<<"PASS frame-consistent threshold and polarity updates\n";
}

void test_framebuffer(Simulation& s) {
 s.reset();s.d.fb_read=1;s.tick();check(!s.d.fb_valid && !s.d.fb_display_valid,"uninitialized display masked");
 auto pattern=[](unsigned seed){std::vector<unsigned> p(512);for(unsigned i=0;i<p.size();i++)p[i]=(i*17+seed)&255;return p;};
 auto a=pattern(7),b=pattern(83),c=pattern(201);
 auto verify=[&](const std::vector<unsigned>& p){
  s.d.fb_read=1;
  for(unsigned i=0;i<512;i++) {s.d.fb_address=i;s.tick();check(s.d.fb_valid && s.d.fb_gray==p[i],"coherent framebuffer pixel "+std::to_string(i));}
 };
 s.frame(a);check(s.d.fb_pending && !s.d.fb_display_valid,"completed frame waits for display boundary");
 s.frame(b);check(s.d.fb_dropped==1,"incoming frame dropped while bank pending");
 s.d.fb_swap=1;s.tick();s.d.fb_swap=0;s.tick(10);verify(a);
 check(s.d.fb_displayed==1 && !s.d.fb_pending,"ack frees old display bank");
 // Keep displaying the old frame while writing the next frame to the other buffer.
 for(unsigned y=0;y<16;y++) for(unsigned x=0;x<32;x++) {
  unsigned index=y*32+x;s.d.fb_address=index;
  s.cam_sample(true,x,y,b[index],x==0 && y==0,x==31 && y==15);
  // This camera cycle already includes a display clock edge. Waiting again here
  // would keep pixel_valid high for another camera edge and count the pixel twice.
  check(s.d.fb_valid && s.d.fb_gray==a[index],"no tearing during concurrent bank writes");
 }
 s.cam_sample(false);s.tick(30);verify(a);check(s.d.fb_pending,"second bank waits without auto-swap");
 s.d.fb_swap=1;s.tick();s.d.fb_swap=0;s.tick(10);verify(b);
 s.frame(c,true);check(!s.d.fb_pending,"malformed raster not published to display");verify(b);
 s.d.frame_abort=1;s.cam_sample(false);s.d.frame_abort=0;s.tick(20);verify(b);
 s.frame(c);s.d.fb_swap=1;s.tick();s.d.fb_swap=0;s.tick(10);verify(c);
 s.d.fb_read=0;s.tick();check(!s.d.fb_valid,"display read valid follows enable");
 s.reset();check(!s.d.fb_display_valid && !s.d.fb_pending,"coordinated reset invalidates stale RAM banks");
 std::cout<<"PASS dual-clock framebuffer: full-bank pixels, whole-frame drops, explicit swap, concurrent reads/writes, malformed frames and reset\n";
}

void test_video(Simulation& s) {
 s.reset();std::vector<unsigned> p(512);
 for(unsigned i=0;i<512;i++) p[i]=(i*13+29)&255;
 s.frame(p);s.tick(5400);check(s.d.video_valid,"video receives completed camera frame");
 auto verify=[&](){
  unsigned guard=0;
  while((s.d.video_x!=0 || s.d.video_y!=0) && guard++<2600) s.tick();
  check(guard<2600,"VGA frame begins within period");
  unsigned active=0,hs_low=0,vs_low=0;
  for(unsigned i=0;i<72*36;i++) {
   unsigned x=i%72,y=i/72;
   check(s.d.video_x==x && s.d.video_y==y,"VGA raster alignment");
   check(bool(s.d.video_active)==(x<64 && y<32),"VGA active extent");
   check(bool(s.d.video_hs)==!(x>=66 && x<70),"VGA horizontal sync interval");
   check(bool(s.d.video_vs)==!(y>=33 && y<35),"VGA vertical sync interval");
   if(s.d.video_active) {
    ++active;unsigned value=p[(y/2)*32+x/2];
    check(s.d.video_red==value && s.d.video_green==value && s.d.video_blue==value,"VGA RAM latency and 2x pixel replication");
   } else check(s.d.video_red==0 && s.d.video_green==0 && s.d.video_blue==0,"VGA blanking black");
   hs_low+=!s.d.video_hs;vs_low+=!s.d.video_vs;s.tick();
  }
  check(active==2048 && hs_low==144 && vs_low==144,"VGA frame counts");
 };
 verify();
 for(auto& value:p) value=255-value;
 s.frame(p);s.tick(5400);verify();
 s.d.arst=1;s.d.eval();check(s.d.video_red==0 && s.d.video_green==0,"video reset masks RAM immediately");
 std::cout<<"PASS live grayscale VGA: exact sync/blanking, 2x pixels, complete frame replacement and reset\n";
}

int main(int argc,char** argv) {
 Verilated::commandArgs(argc,argv);
 try {
  Simulation s;
  test_motor_curve(s);test_safety(s);test_divider(s);test_uart(s);test_distance_junction(s);
  test_vision(s,argc>1 ? argv[1]:"build/vision_vectors.txt");test_system(s);test_stop_states(s);test_capture(s);test_abort_pending(s);test_overlay(s);test_frame_configuration(s);test_framebuffer(s);test_video(s);test_display_independence(s);
  std::cout<<"ALL TESTS PASSED\n";return 0;
 } catch(const std::exception& e) {std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}
}
