"""Create a Quartus project with virtual pins to estimate resource use, not to program the board."""
from pathlib import Path
import argparse

parser=argparse.ArgumentParser()
parser.add_argument('--top',choices=('robot_core','robot_camera_system','video_framebuffer','robot_system','image_translation_sad'),default='robot_core')
top=parser.parse_args().top

ROOT = Path(__file__).resolve().parents[1]
q = ROOT/"quartus"
q.mkdir(exist_ok=True)
lines = ['set_global_assignment -name FAMILY "Cyclone V"',
         'set_global_assignment -name DEVICE 5CSEMA5F31C6',
         'set_global_assignment -name TOP_LEVEL_ENTITY '+top,
         'set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files',
         'set_global_assignment -name NUM_PARALLEL_PROCESSORS 2',
         'set_global_assignment -name SDC_FILE '+({'video_framebuffer':'video_framebuffer.sdc','robot_system':'robot_system.sdc','image_translation_sad':'image_translation_sad.sdc'}.get(top,'robot_core.sdc')),
         '# Data pins are virtual and clock pins are unassigned. Add real pins before board use.']
scalar_ports = 'arst pixel_valid sof eof frame_abort dark_line stop_event release_event bypass sensor_required distance_sample distance_valid inhibited stopped cdc_fault debug_feature_valid debug_frame_good'.split()
vector_ports = 'gray threshold x y distance_mm motor_left motor_right nav_state debug_row_valid debug_junction debug_centroids debug_counts debug_frame_id'.split()
if top in ('robot_camera_system','robot_system'):
    scalar_ports=[p for p in scalar_ports if p not in ('pixel_valid','sof','eof','frame_abort')]
    scalar_ports+=['href','vsync','rgb_msb_first','y_first']
    vector_ports=[p for p in vector_ports if p not in ('gray','x','y')]+['camera_data','pixel_format']
if top=='robot_system':
    scalar_ports+='vga_hsync_n vga_vsync_n vga_blank_n video_ready motion_result_valid motion_accepted motion_rejected motion_tracking_valid motion_continuity_lost motion_overflow motion_boundary motion_busy'.split()
    vector_ports+='vga_red vga_green vga_blue motion_dx motion_dy motion_total_x motion_total_y motion_reference_id motion_current_id motion_dropped_frames motion_best_sad motion_second_sad motion_contrast'.split()
if top=='video_framebuffer':
    scalar_ports='cam_reset display_reset pixel_valid sof eof frame_abort swap_boundary read_enable read_valid display_valid frame_pending'.split()
    vector_ports='gray x y read_address read_gray dropped_frames displayed_frames'.split()
if top=='image_translation_sad':
    scalar_ports='reset reference_write search_write start load_ready ready busy result_valid motion_valid at_search_boundary'.split()
    vector_ports='reference_address search_address reference_gray search_gray reference_frame_id current_frame_id dx dy best_sad second_sad reference_contrast result_reference_id result_current_id'.split()
for port in scalar_ports + [name+'[*]' for name in vector_ports]:
    lines.append('set_instance_assignment -name VIRTUAL_PIN ON -to '+port)
for p in sorted((ROOT/'rtl').rglob('*.sv')):
    lines.append('set_global_assignment -name SYSTEMVERILOG_FILE ../'+p.relative_to(ROOT).as_posix())
(q/(top+'.qsf')).write_text('\n'.join(lines)+'\n', encoding='ascii')
(q/(top+'.qpf')).write_text('QUARTUS_VERSION = "18.1"\nPROJECT_REVISION = "'+top+'"\n',encoding='ascii')
print('PASS created Quartus virtual-pin resource-estimation project:',top)
