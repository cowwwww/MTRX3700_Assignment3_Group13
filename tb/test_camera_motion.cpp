// Feed complete pixel streams to the motion module, including damaged frames.
// The scene is generated from fixed coordinates so its movement is known.
#include "Vcamera_motion.h"
#include "verilated.h"
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <vector>

static void check(bool ok,const char* text) {
 if(!ok) throw std::runtime_error(text);
}
struct Result {int dx,dy;unsigned previous,current;bool valid,boundary;};
struct Sim {
 Vcamera_motion d;
 std::vector<Result> results;
 unsigned drops=0;
 static int signed4(unsigned v) {return v&8 ? int(v)-16:int(v);}
 void tick(unsigned n=1) {
  while(n--) {
   d.clk=0;d.eval();d.clk=1;d.eval();
   if(d.result_valid) results.push_back({signed4(d.dx),signed4(d.dy),
    d.reference_id,d.current_id,bool(d.match_valid),bool(d.at_search_boundary)});
   drops+=d.frame_dropped;
  }
 }
 void reset() {
  d.reset=1;d.pixel_valid=0;d.sof=0;d.eof=0;d.frame_abort=0;d.gray=0;d.x=0;d.y=0;
  tick(2);d.reset=0;tick();results.clear();drops=0;
 }
 static unsigned pixel(int x,int y) {
  uint32_t v=uint32_t(x+256)*0x9e3779b9U ^ uint32_t(y+256)*0x85ebca6bU;
  v^=v>>16;v*=0x7feb352dU;v^=v>>15;return v&255;
 }
 // fault: 1=wrong coordinate, 2=missing EOF, 3=early EOF, 4=camera abort.
 void frame(int dx=0,int dy=0,int fault=0,bool flat=false,bool gaps=false) {
  for(int y=0;y<64;y++) for(int x=0;x<96;x++) {
   if(fault==4 && y==32 && x==0) {
    d.pixel_valid=0;d.frame_abort=1;tick();d.frame_abort=0;return;
   }
   d.pixel_valid=1;d.sof=x==0 && y==0;
   d.eof=(x==95 && y==63 && fault!=2) || (fault==3 && y==32 && x==95);
   d.x=(fault==1 && y==40 && x==47) ? 46:x;d.y=y;
   d.gray=flat ? 100:pixel(x-dx,y-dy);tick();
   if(fault==3 && y==32 && x==95) {d.pixel_valid=0;d.eof=0;return;}
   if(gaps && x%17==0) {d.pixel_valid=0;d.sof=0;d.eof=0;tick();}
  }
  d.pixel_valid=0;d.sof=0;d.eof=0;
 }
 void finish() {d.pixel_valid=0;d.sof=0;d.eof=0;tick(3600);}
 void last(int dx,int dy,unsigned previous,unsigned current) {
  check(!results.empty(),"missing motion result");auto r=results.back();
  check(r.valid && r.dx==dx && r.dy==dy,"incorrect streaming image shift");
  check(r.previous==previous && r.current==current,"incorrect frame IDs");
 }
};
int main(int argc,char** argv) {
 Verilated::commandArgs(argc,argv);
 try {
  Sim s;
  if(argc>1) {
   // This build uses a larger patch at (0,0), so capture overlaps RAM copying.
   s.reset();s.frame();s.frame(1);s.frame(2);s.tick(15000);
   s.last(1,0,1,2);check(s.drops>0 && s.results.size()==1,"overload not dropped cleanly");
   s.frame(3);s.frame(4);s.tick(15000);s.last(1,0,4,5);
   check(s.results.size()==2,"overload reused a partial frame");
   std::cout<<"CAMERA OVERLOAD TESTS PASSED: copy collision, busy matcher, intact pending result and clean restart\n";
   return 0;
  }
  // Include search boundaries and both signs. The first frame only seeds memory.
  for(int dy=-2;dy<=2;dy++) for(int dx=-2;dx<=2;dx++) {
   s.reset();s.frame();check(s.results.empty(),"first frame must not give motion");
   s.frame(dx,dy,0,false,true);s.finish();s.last(dx,dy,1,2);
   check(s.results.size()==1,"duplicate result");
   check(s.results.back().boundary==(dx==-2 || dx==2 || dy==-2 || dy==2),"boundary flag");
  }
  // Start each frame immediately after the previous one, while SAD is running.
  s.reset();for(int f=0;f<6;f++) s.frame(f,-f);
  s.finish();check(s.results.size()==5 && s.drops==0,"continuous capture lost a frame");
  for(unsigned i=0;i<5;i++) {
   auto r=s.results[i];check(r.valid && r.dx==1 && r.dy==-1 &&
    r.previous==i+1 && r.current==i+2,"wrong pair during overlapping capture");
  }
  for(int fault=1;fault<=4;fault++) {
   s.reset();s.frame();s.frame(1,0,fault);s.finish();
   check(s.results.empty() && s.drops>0,"damaged frame accepted");
   s.frame(2);s.frame(3);s.finish();s.last(1,0,3,4);
   check(s.results.size()==1,"paired across a damaged frame");
  }
  s.reset();s.frame(0,0,0,true);s.frame(0,0,0,true);s.finish();
  check(s.results.size()==1 && !s.results.back().valid,"flat scene accepted");
  s.reset();s.frame();s.tick(21000);check(s.drops==1,"timeout must report once");
  s.frame(1);s.frame(2);s.finish();s.last(1,0,2,3);
  s.reset();s.frame();s.frame(1);s.tick(100);s.reset();s.finish();
  check(s.results.empty() && !s.d.busy,"reset left a stale result");
  // Restart while the old frame is incomplete.
  s.reset();s.d.pixel_valid=1;s.d.sof=1;s.d.x=0;s.d.y=0;s.tick();
  s.frame();s.frame(1);s.finish();s.last(1,0,2,3);check(s.drops>0,"restart not reported");
  std::cout<<"CAMERA MOTION TESTS PASSED: 25 shifts, continuous capture, gaps, bad frames, timeout, flat scene and reset\n";
  return 0;
 } catch(const std::exception& e) {std::cerr<<"CHECK FAILED: "<<e.what()<<'\n';return 1;}
}
