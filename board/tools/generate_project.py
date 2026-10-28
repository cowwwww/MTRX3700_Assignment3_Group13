"""Generate the physical project using unmodified course pin assignments."""
from pathlib import Path
import re
ROOT=Path(__file__).resolve().parents[2]
VENDOR=ROOT/'vendor/course_hwtest'
OUT=ROOT/'board/quartus'
vendor_sources=['camera/rtl/video_pll.sv','camera/rtl/clock_divider.sv',
 'camera/rtl/ov7670_config.sv','camera/rtl/i2c_master.sv',
 'sonar/rtl/sonar_pll.sv','sonar/rtl/sonar_range.sv','ir/rtl/nec_decoder.sv']
sources=sorted((ROOT/'rtl').rglob('*.sv'))+sorted((ROOT/'board/rtl').glob('*.sv'))+[VENDOR/p for p in vendor_sources]
qsf=['# Physical V2 project; original V1 virtual-pin project is historical.',
 'set_global_assignment -name FAMILY "Cyclone V"',
 'set_global_assignment -name DEVICE 5CSEMA5F31C6',
 'set_global_assignment -name TOP_LEVEL_ENTITY robot_board',
 'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files',
 'set_global_assignment -name SDC_FILE robot_board.sdc',
 'set_global_assignment -name NUM_PARALLEL_PROCESSORS 2']
for p in sources:
 qsf.append('set_global_assignment -name SYSTEMVERILOG_FILE ../../'+p.relative_to(ROOT).as_posix())
for line in (VENDOR/'hwtest/quartus/hwtest.qsf').read_text().splitlines():
 if not line.startswith(('set_location_assignment ','set_instance_assignment ')):continue
 match=re.search(r' -to (\S+)',line)
 if match and re.fullmatch(r'(CLOCK_50|KEY\[\d+\]|SW\[\d+\]|LEDR\[\d+\]|HEX[0-5]\[\d+\]|GPIO_1\[\d+\]|IRDA_RXD|VGA_\w+(\[\d+\])?)',match[1]):
  qsf.append(line)
OUT.mkdir(exist_ok=True)
(OUT/'robot_board.qsf').write_text('\n'.join(qsf)+'\n')
(OUT/'robot_board.qpf').write_text('QUARTUS_VERSION = "18.1"\nPROJECT_REVISION = "robot_board"\n')
print(f'Generated {len(sources)} sources, {sum(x.startswith("set_location_assignment") for x in qsf)} physical locations')
