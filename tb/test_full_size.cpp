// Test the connected system at its default frame size using generated pixels.
// These tests do not use real hardware recordings.
#include "Vrobot_system.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool ok,const std::string& name) {
 if(!ok) throw std::runtime_error("CHECK FAILED: "+name);
}
struct Feature { unsigned good,valid,junction,centroids,counts,id; };
struct FullSimulation {
 Vrobot_system d;
 uint64_t time=0,control_cycles=0,video_cycles=0;
 std::vector<Feature> features;
 struct Motion {int dx,dy;unsigned previous,current;};
 std::vector<Motion> motions;
 unsigned accepted_motion=0;
 std::ofstream motion_pixels,motion_results;
 void step() {
  bool old_control=d.clk,old_video=d.video_clk,old_camera=d.cam_clk;
  ++time;d.clk=time%10>=5;d.cam_clk=time%14>=7;d.video_clk=time%22>=11;d.eval();
  if(!old_control && d.clk) {
   ++control_cycles;
   if(d.debug_feature_valid) features.push_back({d.debug_frame_good,d.debug_row_valid,
    d.debug_junction,d.debug_centroids,d.debug_counts,d.debug_frame_id});
  }
  if(!old_video && d.video_clk) ++video_cycles;
  if(!old_camera && d.cam_clk) {
   if(d.motion_result_valid) motions.push_back({int16_t(d.motion_dx),int16_t(d.motion_dy),
    d.motion_reference_id,d.motion_current_id});
   if(d.motion_accepted) ++accepted_motion;
   if(motion_results.is_open() && (d.motion_accepted || d.motion_rejected)) {
    motion_results<<d.motion_reference_id<<','<<d.motion_current_id<<','
     <<int16_t(d.motion_dx)<<','<<int16_t(d.motion_dy)<<','<<d.motion_best_sad<<','
     <<d.motion_second_sad<<','<<unsigned(d.motion_contrast)<<','
     <<unsigned(d.motion_boundary)<<','<<unsigned(d.motion_accepted)<<'\n';
   }
  }
 }
 void tick(unsigned n=1) {uint64_t end=control_cycles+n;while(control_cycles<end) step();}
 void video_tick(unsigned n=1) {uint64_t end=video_cycles+n;while(video_cycles<end) step();}
 void byte(bool href,bool vsync,unsigned data=0) {
  bool old=d.cam_clk;
  do {old=d.cam_clk;step();} while(!(old && !d.cam_clk));
  d.href=href;d.vsync=vsync;d.camera_data=data;d.eval();
  do {step();} while(!d.cam_clk);
 }
 static unsigned pixel(unsigned x,unsigned y,unsigned pattern) {
  if(pattern>=10) {
   uint32_t v=(x+256-(pattern-10))*0x9e3779b9U ^ (y+256)*0x85ebca6bU;
   v^=v>>16;v*=0x7feb352dU;v^=v>>15;return v&255;
  }
  unsigned row=y<100 ? 0 : (y<160 ? 1:2);
  const std::array<unsigned,3> start=pattern ? std::array<unsigned,3>{1,81,160}
                                                   :std::array<unsigned,3>{200,215,230};
  unsigned width=pattern ? 159:81;
  return x>=start[row] && x<start[row]+width ? 20 : 120+(x*17+y*13)%120;
 }
 void frame(unsigned pattern) {
  byte(false,true);byte(false,true);byte(false,false);
  for(unsigned y=0;y<240;y++) {
   for(unsigned x=0;x<320;x++) {
    unsigned gray=pixel(x,y,pattern);
    if(motion_pixels.is_open()) motion_pixels<<pattern-9<<','<<x<<','<<y<<','<<gray<<'\n';
    byte(true,false,gray);
   }
   byte(false,false);byte(false,false);
  }
  tick(100);
 }
 void check_features(unsigned pattern) {
  require(!features.empty(),"default-size feature published");
  const auto& f=features.back();
  require(f.good && f.valid==7 && f.junction==0,"default-size valid rows");
  // Calculate expected sums from the input rows without using the RTL sums.
  std::array<unsigned,3> center{};
  for(unsigned row=0;row<3;row++) {
   unsigned sum=0,count=0;
   for(unsigned x=0;x<320;x++) if(pixel(x,(row+1)*60,pattern)<=96) {sum+=x;++count;}
   center[row]=sum/count;
   require(((f.centroids>>(9*row))&511)==center[row],"9-bit full-size centroid");
   require(((f.counts>>(9*row))&511)==count,"9-bit full-size count");
  }
  int error=int(center[2])-160,speed=96;
  if(!d.bypass) {
   int target=int(-0.125*center[2]+0.75*center[1]+0.375*center[0]);
   error=std::clamp(target,0,319)-160;
   speed-=std::min(40,std::abs(int(center[0])-int(center[2]))/2);
  }
  require(!d.inhibited && !d.cdc_fault,"full-size controller enabled after recovery");
  require(static_cast<int16_t>(d.motor_left)==std::clamp(speed+2*error,-255,255),"full-size left wheel");
  require(static_cast<int16_t>(d.motor_right)==std::clamp(speed-2*error,-255,255),"full-size right wheel");
 }
 void verify_video() {
  // VSYNC rises at scan position (0,492). Skip the 33 lines of the
  // back porch to reach the first visible pixel. Only use the module outputs.
  unsigned guard=0;
  while(d.vga_vsync_n && ++guard<800*525*2) video_tick();
  require(guard<800*525*2,"find full-size VSYNC pulse");
  guard=0;while(!d.vga_vsync_n && ++guard<800*3) video_tick();
  require(guard<800*3,"VSYNC pulse ends");
  video_tick(33*800);
  require(d.video_ready,"complete frame adopted before scanout");
  unsigned active=0,hs_low=0,vs_low=0;
  for(unsigned i=0;i<800*525;i++) {
   unsigned x=i%800,y=i/800;
   bool visible=x<640 && y<480;
   require(bool(d.vga_blank_n)==visible,"full-size VGA active extent");
   require(bool(d.vga_hsync_n)==!(x>=656 && x<752),"full-size VGA HSYNC");
   require(bool(d.vga_vsync_n)==!(y>=490 && y<492),"full-size VGA VSYNC");
   // Keep the first complete frame in the buffer until the display takes it.
   // Drop later frames that arrive before vertical blanking without overwriting it.
   unsigned expected=visible ? pixel(x/2,y/2,0):0;
   require(d.vga_red==expected && d.vga_green==expected && d.vga_blue==expected,
           "full-size VGA coherent image, scaling and RAM latency");
   active+=visible;hs_low+=!d.vga_hsync_n;vs_low+=!d.vga_vsync_n;video_tick();
  }
  require(active==307200 && hs_low==50400 && vs_low==1600,"full-size VGA totals");
 }
};
int main(int argc,char** argv) {
 Verilated::commandArgs(argc,argv);
 try {
  FullSimulation s;
  s.d.arst=1;s.d.href=0;s.d.vsync=0;s.d.camera_data=0;s.d.pixel_format=0;
  s.d.rgb_msb_first=1;s.d.y_first=1;s.d.threshold=96;s.d.dark_line=1;
  s.d.stop_event=0;s.d.release_event=0;s.d.bypass=1;s.d.sensor_required=0;
  s.d.distance_sample=0;s.d.distance_valid=0;s.d.distance_mm=0;
  s.tick(20);s.d.arst=0;s.tick(20);
  require(s.d.inhibited && s.d.motor_left==0 && s.d.motor_right==0,"default-size reset stopped");
  s.d.release_event=1;s.tick();s.d.release_event=0;s.tick();
  for(unsigned i=0;i<3;i++) s.frame(0);
  require(s.features.size()==3,"exactly one feature per complete QVGA frame");
  s.check_features(0);s.d.bypass=0;s.tick();s.check_features(0);
  s.frame(1);s.check_features(1);
  require(s.features.size()==4 && s.features[3].id==s.features[0].id+3,"full-size frame sequence");
  s.verify_video();
  s.d.stop_event=1;s.d.eval();
  require(s.d.inhibited && s.d.motor_left==0 && s.d.motor_right==0,"full-size immediate stop");
  s.tick();s.d.stop_event=0;s.tick(20);require(s.d.stopped,"full-size stop remains latched");
  // Run fresh raw-camera frames through capture, patch storage and SAD.
  s.d.arst=1;s.tick(20);s.d.arst=0;s.tick(20);s.motions.clear();s.accepted_motion=0;
  if(argc>1) {
   s.motion_pixels.open(std::string(argv[1])+"/synthetic_pixels.csv");
   s.motion_results.open(std::string(argv[1])+"/synthetic_motion.csv");
   require(s.motion_pixels.is_open() && s.motion_results.is_open(),"open replay output files");
   s.motion_pixels<<"frame,x,y,gray\n";
   s.motion_results<<"reference_id,current_id,dx,dy,best_sad,second_sad,contrast,boundary,accepted\n";
  }
  s.frame(10);s.frame(11);s.frame(12);s.tick(70000);
  require(s.motions.size()==2 && s.accepted_motion==2,"raw-camera motion result count");
  for(unsigned i=0;i<2;i++) {
   const auto& m=s.motions[i];
   require(m.dx==1 && m.dy==0 && m.previous==i+1 && m.current==i+2,"raw-camera motion values and frame IDs");
  }
  require(s.d.motion_total_x==2 && s.d.motion_total_y==0 && !s.d.motion_continuity_lost,
          "raw-camera pixel total");
  require(s.d.stopped && !s.d.motor_left && !s.d.motor_right,"motion processing cannot release stop");
  std::cout<<"PASS raw-camera motion: consecutive textured QVGA frames, signed shifts, pixel totals and stop isolation\n";
  std::cout<<"PASS QVGA: four 320x240 raw frames, 9-bit statistics, bypass, wheel control and stop\n";
  std::cout<<"PASS VGA: all 420000 scan positions, 307200 active pixels, exact sync/blanking and bank coherence\n";
  std::cout<<"FULL SIZE TESTS PASSED\n";return 0;
 } catch(const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}
}
