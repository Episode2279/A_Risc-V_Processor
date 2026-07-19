# Create a reproducible Vivado project without committing generated project data.
# Usage: vivado -mode batch -source create_project.tcl -tclargs <fpga-part>

set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir .. .. ..]]

if {[llength $argv] < 1 || [string trim [lindex $argv 0]] eq ""} {
    error "FPGA part is required (for example: xc7a35tcpg236-1)"
}
set fpga_part [lindex $argv 0]
set build_root [file join $project_root build vivado]
set project_dir [file join $build_root project]
set report_dir [file join $build_root reports]
set trace_dir [file join $project_root build traces]
file mkdir $project_dir $report_dir $trace_dir

proc parse_filelist {project_root filelist_path} {
    set files [list]
    set stream [open $filelist_path r]
    while {[gets $stream line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} {
            continue
        }
        if {[string match "-f *" $line]} {
            set child [string trim [string range $line 3 end]]
            set files [concat $files [parse_filelist $project_root [file join $project_root $child]]]
        } else {
            lappend files [file normalize [file join $project_root $line]]
        }
    }
    close $stream
    return $files
}

create_project -force A_RiscV_Processor $project_dir -part $fpga_part
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]

set rtl_files [parse_filelist $project_root [file join $project_root config filelists core.f]]
add_files -fileset sources_1 -norecurse $rtl_files
set_property top topCPU [get_filesets sources_1]

set tb_file [file join $project_root verification integration core topCPU_tb.sv]
add_files -fileset sim_1 -norecurse $tb_file
set_property top topCPU_tb [get_filesets sim_1]

set constraint_files [glob -nocomplain [file join $project_root fpga vivado constraints *.xdc]]
if {[llength $constraint_files] > 0} {
    add_files -fileset constrs_1 -norecurse $constraint_files
}

# XSim starts from a generated run directory, so pass absolute paths explicitly.
set insn_image [file normalize [file join $project_root build images insn.mem]]
set data_image [file normalize [file join $project_root build images data.mem]]
set debug_log [file normalize [file join $trace_dir topCPU_tb_debug.txt]]
set pipe_dump [file normalize [file join $trace_dir topCPU_tb_output.txt]]
set xsim_args "+insn-mem=$insn_image +data-mem=$data_image +debug-log=$debug_log +pipe-dump-file=$pipe_dump"
set_property xsim.simulate.xsim.more_options $xsim_args [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
set_property source_mgmt_mode All [current_project]

puts "Vivado project created: [file join $project_dir A_RiscV_Processor.xpr]"
puts "Target part: $fpga_part"
