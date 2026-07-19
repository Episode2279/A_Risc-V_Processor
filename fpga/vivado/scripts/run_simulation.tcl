# Recreate the project and run the shared SystemVerilog integration testbench.

set script_dir [file dirname [file normalize [info script]]]
source [file join $script_dir create_project.tcl]

set project_root [file normalize [file join $script_dir .. .. ..]]
set insn_image [file join $project_root build images insn.mem]
set data_image [file join $project_root build images data.mem]
if {![file exists $insn_image] || ![file exists $data_image]} {
    error "Memory images are missing; run 'make coremark' before XSim"
}

launch_simulation
run all
close_sim
puts "XSim completed; logs and the pipeline dump are under [file join $project_root build traces]"
