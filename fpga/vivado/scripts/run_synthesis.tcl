# Recreate the project, run synthesis, and write machine-independent reports.

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir create_project.tcl]

set project_root [file normalize [file join $script_dir .. .. ..]]
set report_dir [file join $project_root build vivado reports]
file mkdir $report_dir

launch_runs synth_1 -jobs 4
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
if {![string match "*Complete*" $synth_status]} {
    error "Vivado synthesis failed: $synth_status"
}

open_run synth_1
report_utilization -hierarchical -file [file join $report_dir utilization.rpt]
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
    -file [file join $report_dir timing_summary.rpt]
report_clock_utilization -file [file join $report_dir clock_utilization.rpt]
puts "Synthesis reports written to $report_dir"
