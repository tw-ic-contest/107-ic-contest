#Read All Files
read_file -format sverilog  GPSDC.v
#read_file -format sverilog  geofence.v
current_design GPSDC
link

#Setting Clock Constraints
source -echo -verbose GPSDC.sdc
check_design
set high_fanout_net_threshold 0
uniquify
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

#Synthesis all design
#compile -map_effort high -area_effort high
#compile -map_effort high -area_effort high -inc
compile

write -format ddc     -hierarchy -output "GPSDC_syn.ddc"
write_sdf -version 1.0  geofence_syn.sdf
write -format verilog -hierarchy -output GPSDC_syn.v
report_area > area.log
report_timing > timing.log
report_qor   >  GPSDC_syn.qor
