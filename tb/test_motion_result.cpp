// Use a small total width to test saturation without millions of updates.
#include "Vmotion_result.h"
#include "verilated.h"
#include <iostream>
#include <stdexcept>
static void check(bool ok,const char* text) {if(!ok) throw std::runtime_error(text);}
struct Sim {
 Vmotion_result d;
 void tick(unsigned n=1) {while(n--) {d.clk=0;d.eval();d.clk=1;d.eval();}}
 void reset() {
  d.reset=1;d.result_valid=0;d.match_valid=0;d.at_search_boundary=0;d.frame_dropped=0;
  d.dx=0;d.dy=0;d.reference_id=0;d.current_id=0;tick();d.reset=0;tick();
 }
 void result(unsigned from,unsigned to,int dx,int dy,bool good=true,bool edge=false) {
  d.reference_id=from;d.current_id=to;d.dx=dx&31;d.dy=dy&31;
  d.match_valid=good;d.at_search_boundary=edge;d.result_valid=1;tick();d.result_valid=0;
 }
};
int main(int argc,char** argv) {
 Verilated::commandArgs(argc,argv);
 try {
  Sim s;s.reset();s.result(65535,0,2,-1);
  check(s.d.accepted && s.d.total_x==2 && s.d.total_y==255 && !s.d.continuity_lost,"signed sum or ID wrap");
  s.tick();check(!s.d.accepted && !s.d.rejected,"status pulses must last one clock");
  s.result(0,1,-1,2);check(s.d.total_x==1 && s.d.total_y==1,"signed accumulation");
  for(int reason=0;reason<3;reason++) {
   s.reset();s.result(0,reason==2 ? 2:1,3,2,reason!=0,reason==1);
   check(s.d.rejected && !s.d.accepted && !s.d.tracking_valid && s.d.continuity_lost &&
    s.d.total_x==0 && s.d.total_y==0,"rejected match changed totals");
  }
  s.reset();s.result(0,1,1,1);s.result(3,4,1,1);
  check(s.d.accepted && s.d.continuity_lost,"gap between result pairs not flagged");
  s.reset();for(unsigned i=0;i<12;i++) s.result(i,i+1,15,-16);
  check(s.d.total_x==127 && s.d.total_y==128 && s.d.overflow && s.d.continuity_lost,"sum did not saturate");
  s.reset();s.result(0,1,1,1);s.tick(16);
  check(!s.d.tracking_valid && s.d.continuity_lost,"stale result stayed valid");
  s.result(1,2,1,1);check(s.d.tracking_valid && s.d.continuity_lost,"recovery hid earlier gap");
  s.d.frame_dropped=1;s.result(2,3,1,1);
  check(!s.d.tracking_valid && s.d.continuity_lost,"capture fault must win");
  s.reset();check(!s.d.overflow && !s.d.continuity_lost && !s.d.tracking_valid && !s.d.total_x,"reset");
  std::cout<<"MOTION RESULT TESTS PASSED: signed sums, quality rejection, frame gaps, ID wrap, saturation, stale data and reset\n";
  return 0;
 } catch(const std::exception& e) {std::cerr<<"CHECK FAILED: "<<e.what()<<'\n';return 1;}
}
