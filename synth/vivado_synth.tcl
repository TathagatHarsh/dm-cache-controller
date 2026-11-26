# Vivado (Windows/Linux lab machine): exact utilisation + timing for both caches.
#   vivado -mode batch -source synth/vivado_synth.tcl
# Target: Artix-7 xc7a35tcpg236-1 (Basys 3). Reports land in synth/reports/vivado_*.
set root [file normalize [file dirname [info script]]/..]
foreach top {dm_cache sa2_cache} {
    create_project -in_memory -part xc7a35tcpg236-1
    read_verilog [glob $root/rtl/*.v]
    synth_design -top $top -mode out_of_context
    create_clock -name clk -period 5.000 [get_ports clk]
    opt_design; place_design; route_design
    report_utilization    -file $root/synth/reports/vivado_${top}_util.txt
    report_timing_summary -file $root/synth/reports/vivado_${top}_timing.txt
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    puts "$top: WNS = $wns ns at 5.000 ns  ->  Fmax ~ [format %.1f [expr {1000.0 / (5.0 - $wns)}]] MHz"
    close_project
}
