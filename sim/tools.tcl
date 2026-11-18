# Shared discovery for Questa installations and Python 3.
# Optional overrides: QUESTA_HOME, UVM_HOME, PYTHON.
namespace eval cache_tools {
    proc questa_home {} {
        set candidates {}
        if {[info exists ::env(QUESTA_HOME)]} {
            lappend candidates $::env(QUESTA_HOME)
        }
        if {[info exists ::env(MODEL_TECH)]} {
            lappend candidates [file dirname $::env(MODEL_TECH)]
        }
        lappend candidates [file dirname [file dirname [info nameofexecutable]]]
        foreach candidate $candidates {
            if {[file isfile [file join $candidate modelsim.ini]]} {
                return [file normalize $candidate]
            }
        }
        error "Cannot find Questa modelsim.ini; set QUESTA_HOME to the installation directory"
    }

    proc python {} {
        if {[info exists ::env(PYTHON)] && $::env(PYTHON) ne ""} {
            return [list $::env(PYTHON)]
        }
        foreach command {python3 python} {
            set executable [auto_execok $command]
            if {$executable ne "" &&
                ![catch {exec {*}$executable -c {import sys; assert sys.version_info >= (3, 9)}}]} {
                return $executable
            }
        }
        error "Python 3.9+ is required; put it on PATH or set PYTHON to its executable"
    }

    proc uvm_home {} {
        if {[info exists ::env(UVM_HOME)]} {
            return $::env(UVM_HOME)
        }
        set directory [file join [questa_home] verilog_src uvm-1.1d src]
        if {![file isfile [file join $directory uvm_macros.svh]]} {
            error "Matching UVM 1.1d headers not found; set UVM_HOME to their src directory"
        }
        return $directory
    }

    proc vcover {} {
        set executable [file join [file dirname [info nameofexecutable]] vcover]
        if {[file isfile $executable.exe]} {
            return $executable.exe
        }
        if {[file isfile $executable]} {
            return $executable
        }
        error "vcover was not found beside the running Questa executable"
    }
}
