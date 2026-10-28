// Check image shifts using generated scenes and a separate SAD calculation.
// SAD is the sum of absolute pixel differences. This does not test real robot travel.
#include "Vimage_translation_sad.h"
#include "verilated.h"
#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

static void require(bool ok,const std::string& why) {
 if(!ok) throw std::runtime_error("CHECK FAILED: "+why);
}
struct Oracle {unsigned best,second,contrast;int dx,dy;bool valid,boundary;};
static Oracle oracle(const std::vector<unsigned>& ref,const std::vector<unsigned>& cur,bool distinct=true) {
 std::vector<std::array<unsigned,3>> scores;
 for(unsigned y=0;y<9;y++) for(unsigned x=0;x<9;x++) {
  unsigned sad=0;
  for(unsigned j=0;j<16;j++) for(unsigned i=0;i<16;i++)
   sad+=std::abs(int(ref[j*16+i])-int(cur[(y+j)*24+x+i]));
  scores.push_back({sad,x,y});
 }
 std::stable_sort(scores.begin(),scores.end(),[](auto a,auto b){return a[0]<b[0];});
 auto mm=std::minmax_element(ref.begin(),ref.end());unsigned contrast=*mm.second-*mm.first;
 int dx=int(scores[0][1])-4,dy=int(scores[0][2])-4;
 return {scores[0][0],scores[1][0],contrast,dx,dy,
         scores[0][0]<=20*256 && scores[1][0]-scores[0][0]>=512 && contrast>=32 && distinct,
         std::abs(dx)==4 || std::abs(dy)==4};
}
struct Sim {
 Vimage_translation_sad d;
 unsigned results=0;
 void tick() {d.clk=0;d.eval();d.clk=1;d.eval();if(d.result_valid) ++results;}
 void reset() {
  d.reset=1;d.reference_write=0;d.search_write=0;d.start=0;
  d.reference_address=0;d.search_address=0;d.reference_gray=0;d.search_gray=0;
  d.reference_frame_id=65535;d.current_frame_id=0;tick();d.reset=0;tick();
  require(d.load_ready && !d.ready && !d.busy,"reset masks unloaded RAM");
 }
 void load(const std::vector<unsigned>& ref,const std::vector<unsigned>& cur) {
  require(d.load_ready,"idle can load");
  for(unsigned i=0;i<cur.size();i++) {
   d.reference_write=i<ref.size();d.reference_address=i<ref.size() ? i:0;
   d.reference_gray=i<ref.size() ? ref[i]:0;
   d.search_write=1;d.search_address=i;d.search_gray=cur[i];tick();
  }
  d.reference_write=0;d.search_write=0;d.eval();require(d.ready,"complete ordered arrays ready");
 }
 void run(const Oracle& expected,bool inject_write=false) {
  unsigned before=results,reference_id=d.reference_frame_id,current_id=d.current_frame_id;
  d.start=1;tick();d.start=0;
  require(d.busy && !d.load_ready,"start acquires arrays");
  if(inject_write) {d.reference_frame_id=9;d.current_frame_id=9;}
  unsigned count=0;
  while(!d.result_valid && count<41474) {
   // Ignore writes while calculating so neither stored image changes.
   d.reference_write=inject_write;d.search_write=inject_write;
   d.reference_address=0;d.search_address=0;d.reference_gray=255;d.search_gray=0;
   tick();++count;
  }
  d.reference_write=0;d.search_write=0;
  d.reference_frame_id=reference_id;d.current_frame_id=current_id;d.eval();
  require(count==41473 && results==before+1,"bounded 2*81*256+1 clock completion");
  auto signed5=[](unsigned v){return (v&16) ? int(v)-32:int(v);};
  require(d.best_sad==expected.best && d.second_sad==expected.second,"best and second SAD vs batch oracle");
  require(signed5(d.dx)==expected.dx && signed5(d.dy)==expected.dy,"signed shift and deterministic tie order");
  require(d.reference_contrast==expected.contrast,"reference texture range");
  require(bool(d.motion_valid)==expected.valid && bool(d.at_search_boundary)==expected.boundary,"quality gates and search boundary");
  require(d.result_reference_id==d.reference_frame_id && d.result_current_id==d.current_frame_id,"frame-pair identity including wrap");
  tick();require(!d.result_valid,"single-cycle result event");
 }
};
int main(int argc,char** argv) {
 Verilated::commandArgs(argc,argv);
 try {
  Sim s;s.reset();s.d.start=1;s.tick();s.d.start=0;require(!s.d.busy,"unloaded start ignored");
  std::mt19937 rng(37003700);std::vector<unsigned> ref(256),cur(576);
  for(auto& v:ref) v=rng()%256;
  for(int dy=-4;dy<=4;dy++) for(int dx=-4;dx<=4;dx++) {
   for(auto& v:cur) v=rng()%256;
   for(int y=0;y<16;y++) for(int x=0;x<16;x++) cur[(y+4+dy)*24+x+4+dx]=ref[y*16+x];
   auto expected=oracle(ref,cur);require(expected.valid && expected.dx==dx && expected.dy==dy,"synthetic translated block construction");
   s.load(ref,cur);s.run(expected,dx==0 && dy==0);
  }
  // Reject flat or repeating images because several shifts can look like a match.
  std::fill(ref.begin(),ref.end(),100);std::fill(cur.begin(),cur.end(),100);
  s.load(ref,cur);s.run(oracle(ref,cur));require(!s.d.motion_valid,"flat scene invalid");
  for(unsigned y=0;y<16;y++) for(unsigned x=0;x<16;x++) ref[y*16+x]=((x+y)%2)*255;
  for(unsigned y=0;y<24;y++) for(unsigned x=0;x<24;x++) cur[y*24+x]=((x+y)%2)*255;
  s.load(ref,cur);s.run(oracle(ref,cur));require(!s.d.motion_valid,"ambiguous texture invalid");
  for(auto& v:ref) v=rng()%256;for(auto& v:cur) v=rng()%256;
  s.load(ref,cur);s.run(oracle(ref,cur));require(!s.d.motion_valid,"unrelated frames fail photometric gate");
  for(unsigned y=0;y<16;y++) for(unsigned x=0;x<16;x++) cur[(y+4)*24+x+4]=ref[y*16+x];
  s.d.current_frame_id=s.d.reference_frame_id;s.load(ref,cur);s.run(oracle(ref,cur,false));
  require(!s.d.motion_valid,"same frame ID cannot claim temporal motion");
  // An out-of-order write makes the stored block invalid. Reload from address zero.
  s.d.reference_write=1;s.d.reference_address=0;s.tick();s.d.reference_address=2;s.tick();
  s.d.reference_write=0;s.d.eval();require(!s.d.ready,"out-of-order load rejected");
  s.d.current_frame_id=0;s.load(ref,cur);s.d.start=1;s.tick();s.d.start=0;
  for(int i=0;i<27;i++) s.tick();s.reset();unsigned before_reset_wait=s.results;
  for(int i=0;i<41480;i++) s.tick();require(s.results==before_reset_wait && !s.d.ready,"reset cancels in-flight match without any stale result pulse");
  // Use large pixel differences to test sums near the 16-bit limit.
  std::fill(ref.begin(),ref.end(),0);std::fill(cur.begin(),cur.end(),255);
  s.load(ref,cur);s.run(oracle(ref,cur));require(s.d.best_sad==65280,"maximum SAD has no overflow");
  std::cout<<"PASS image translation: all 81 shifts, independent SAD/runner-up oracle, quality gates, frame IDs, ordered loads, busy isolation and reset\n";
  std::cout<<"IMAGE TRANSLATION TESTS PASSED\n";return 0;
 } catch(const std::exception& e) {std::cerr<<e.what()<<'\n';return 1;}
}
