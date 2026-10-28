#include "Vboard_adapters_top.h"
#include "verilated.h"
#include <vector>
#include <string>
#include <iostream>
#include <stdexcept>
#include <cstdint>
#include <sstream>
#include <iomanip>
Vboard_adapters_top d;
std::vector<int> serial;
int pixels=0,starts=0,ends=0,aborts=0;
bool check_camera=false;
void require(bool ok,const char* why){if(!ok)throw std::runtime_error(why);}
uint16_t rgb(int x,int y){return uint16_t(((x%32)<<11)|((y%64)<<5)|((x+y)%32));}
int grayof(uint16_t v){int r=(v>>11)&31,g=(v>>5)&63,b=v&31;return ((r<<3|r>>2)+2*(g<<2|g>>4)+(b<<3|b>>2))/4;}
void tick(){
 d.clk=0;d.eval();d.clk=1;d.eval();serial.push_back(d.tx);
 starts+=d.sof;ends+=d.eof;aborts+=d.frame_abort;
 if(d.pixel_valid){
  if(check_camera){require(d.x==pixels%320 && d.y==pixels/320,"QVGA coordinate/order");
   require(d.gray==grayof(rgb(2*d.x+1,2*d.y+1)),"RGB565 grayscale/decimation");}
  pixels++;
 }
}
void ticks(int n){while(n--)tick();}
void reset(){d.reset=1;d.inhibit=1;d.href=0;d.vsync=0;d.data=0;d.left=0;d.right=0;ticks(6);d.reset=0;serial.clear();serial.push_back(1);pixels=starts=ends=aborts=0;}
std::string decode(){
 std::string s;
 for(size_t i=1;i+39<serial.size();){
  if(serial[i-1] && !serial[i]){
   require(!serial[i+2],"UART start bit");int v=0;
   for(int b=0;b<8;b++)v|=serial[i+6+4*b]<<b;
   require(serial[i+38],"UART stop bit");s.push_back(char(v));i+=40;
  }else i++;
 }return s;
}
std::vector<std::string> lines(){auto s=decode();std::vector<std::string> a;size_t p=0,q;
 while((q=s.find('\n',p))!=std::string::npos){if(q>p)a.push_back(s.substr(p,q-p+1));p=q+1;}return a;}
const std::string zero="{\"T\":1,\"L\": 0.000,\"R\": 0.000}\n";
const std::string drive="{\"T\":1,\"L\": 0.100,\"R\":-0.050}\n";
std::string wheel(int v){if(v>255)v=255;if(v< -255)v=-255;int m=(v<0?-v:v)*100/255;
 std::ostringstream s;s<<(v<0&&m?'-':' ')<<"0."<<std::setfill('0')<<std::setw(3)<<m;return s.str();}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);try{
 reset();ticks(1500);auto a=lines();require(a.size()==1 && a[0]==zero,"boot must send zero");
 d.inhibit=0;d.left=32767;d.right=uint16_t(-128);ticks(2500);a=lines();require(a.size()>=2 && a[1]==drive,"clamp scale sign");
 // Sweep stop across the complete in-flight packet, including its boundaries.
 for(int phase=0;phase<1300;phase+=29){
  reset();ticks(1500);d.inhibit=0;d.left=255;d.right=uint16_t(-128);
  ticks(600+phase);d.inhibit=1;size_t stop_cycle=serial.size();ticks(2600);
  a=lines();bool saw_drive=false,saw_zero_after=false;
  for(size_t j=1;j<a.size();j++){
   require(a[j]==zero || a[j]==drive,"torn/invalid JSON packet");
   if(a[j]==drive){require(!saw_zero_after,"stale motion after stop");saw_drive=true;}
   if(saw_drive && a[j]==zero)saw_zero_after=true;
  }
  require(saw_drive && saw_zero_after,"stop must follow active packet with zero");
  // Limit to remaining current packet plus one complete zero packet (2520 clocks).
  auto full=serial;serial.resize(stop_cycle+2520);a=lines();require(a.back()==zero,"stop latency bound");serial=full;
 }
 reset();ticks(1500);d.inhibit=0;d.left=1;d.right=uint16_t(-2);ticks(2500);
 require(d.packet_zero,"sub-mm/s targets must report zero");
 for(int command=-300;command<=300;command++){
  reset();ticks(1500);d.inhibit=0;d.left=uint16_t(command);d.right=uint16_t(-command);ticks(2500);
  a=lines();require(a.size()>=2,"scaled packet absent");
  require(a[1]=="{\"T\":1,\"L\":"+wheel(command)+",\"R\":"+wheel(-command)+"}\n","exhaustive wheel conversion");
 }
 // Targets changing during a packet must not tear either wheel field.
 reset();ticks(1500);d.inhibit=0;d.left=255;d.right=uint16_t(-128);ticks(700);
 d.left=uint16_t(-255);d.right=255;ticks(1400);a=lines();require(a[1]==drive,"packet snapshot torn");
 // A one-cycle stop is retained even when inhibit clears before the line ends.
 reset();ticks(1500);d.inhibit=0;d.left=255;d.right=uint16_t(-128);ticks(700);
 d.inhibit=1;tick();d.inhibit=0;ticks(2600);a=lines();require(a.size()>=3&&a[2]==zero,"brief stop lost");
 // Full 640x480 raw camera frame. No sample accepted before a fresh VSYNC.
 reset();d.href=1;ticks(20);d.href=0;ticks(4);require(pixels==0,"must wait for VSYNC");
 d.vsync=1;ticks(4);d.vsync=0;ticks(4);check_camera=true;
 for(int y=0;y<480;y++){
  d.href=1;for(int x=0;x<640;x++){auto v=rgb(x,y);d.data=v>>8;tick();d.data=v&255;tick();}
  d.href=0;ticks(6);
 }
 ticks(6);check_camera=false;
 require(pixels==320*240 && starts==1 && ends==1 && aborts==0,"complete QVGA framing");
 reset();d.vsync=1;ticks(4);d.vsync=0;ticks(4);d.href=1;ticks(1279);d.href=0;ticks(6);
 require(aborts==1 && ends==0,"odd-byte malformed line must abort");
 reset();d.vsync=1;ticks(4);d.vsync=0;ticks(4);d.href=1;ticks(1282);d.href=0;ticks(6);
 require(aborts==1 && ends==0,"overlong line must abort");
 std::cout<<"PASS: boot zero, 601 signed wheel conversions, immutable packet snapshot, brief stop retention, 45 stop phases, stop latency, complete 640x480 RGB565 -> 320x240, malformed camera lines\n";
 return 0;
 }catch(const std::exception&e){std::cerr<<"FAIL: "<<e.what()<<"\n";return 1;}}
