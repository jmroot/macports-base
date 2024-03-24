# Utilities for managing threads and subinterpreters in MacPorts

package provide macports_threadutil 1.0

namespace eval macports_threadutil {
    variable varcache
    variable aliases [list]
    variable traced_vars [dict create]
    variable proccache [dict create]

    # Record all namespaces, scalar variables, variable traces and
    # arrays that exist in the current interpreter.
    proc cache_vars {} {
        variable varcache
        variable aliases
        variable traced_vars
        set arrays [list]
        set namespaces [list ::]
        set variables [list]
        set ignore [list ::oo ::safe ::tcl ::zlib]
        for {set i 0} {$i < [llength $namespaces]} {incr i} {
            set ns [lindex $namespaces $i]
            if {$ns ni $ignore} {
                lappend namespaces {*}[namespace children $ns]
                foreach var [info vars ${ns}::*] {
                    # don't trigger traces now by reading the variable
                    if {[trace info variable $var] eq ""} {
                        if {[array exists $var]} {
                            lappend arrays $var [array get $var]
                        } elseif {[info exists $var]} {
                            lappend variables $var [set $var]
                        }
                    }
                }
            }
        }
        set traces [list]
        foreach varname [dict keys $traced_vars] {
            lappend traces $varname [trace info variable $varname]
        }
        set varcache [dict create aliases $aliases arrays $arrays namespaces $namespaces traces $traces variables $variables]
    }

    proc getvars {} {
        variable varcache
        return $varcache
    }

    # Set vars from info returned by getvars.
    proc setvars {vars} {
        foreach ns [dict get $vars namespaces] {
            namespace eval :: [list namespace eval $ns {}]
        }
        foreach {var val} [dict get $vars variables] {
            set $var $val
        }
        foreach {var val} [dict get $vars arrays] {
            array set $var $val
        }
        foreach aliasinfo [dict get $vars aliases] {
            interp alias {*}${aliasinfo}
        }
        foreach {var traceinfo} [dict get $vars traces] {
            foreach infopair $traceinfo {
                trace add variable $var {*}$infopair
            }
        }
    }

    # Trace option creation (and any other aliases that may exist)
    proc init_capture {} {
        trace add execution interp enter macports_threadutil::trace_alias
        trace add execution trace enter macports_threadutil::trace_trace
    }

    proc trace_alias {cmdstring op} {
        variable aliases
        # an interp alias call looks like: interp alias {} name1 {} name2 ...
        if {[llength $cmdstring] >= 6 && [lindex $cmdstring 1] eq "alias"} {
            lappend aliases [lrange $cmdstring 2 end]
        }
    }

    proc trace_trace {cmdstring op} {
        variable traced_vars
        # a trace add variable call looks like: trace add variable varname ops cmd
        if {[llength $cmdstring] == 6 && [lindex $cmdstring 2] eq "variable" && [lindex $cmdstring 1] eq "add"} {
            dict set traced_vars [uplevel 1 [list namespace which -variable [lindex $cmdstring 3]]] 1
        }
    }

    proc getproc {procname} {
        variable proccache
        # Use fully-qualified name for proc
        set procname [namespace eval :: [list namespace which -command $procname]]
        if {$procname eq {}} {
            return {}
        }
        if {[dict exists $proccache $procname]} {
            return [dict get $proccache $procname]
        }
        set ret {}
        catch {
            set arglist [lmap arg [info args $procname] {
                expr {[info default $procname $arg thedefault] ?
                        [list $arg $thedefault] : $arg}
            }]
            dict set proccache $procname [list $arglist [info body $procname]]
            set ret [dict get $proccache $procname]
        }
        return $ret
    }
}
