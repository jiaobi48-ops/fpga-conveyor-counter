"""Run the actual download entry in Tcl with all hardware actions intercepted."""
from pathlib import Path
import subprocess,json,hashlib
R=Path(__file__).resolve().parent
out=R/'validation/launcher_mock';out.mkdir(exist_ok=True)
tcl=r'''
set root [file normalize [lindex $argv 0]]
set calls {};set fail_verify 1;set target_count 1;set queries 0
rename exec actual_exec
proc exec {args} {
 if {$::fail_verify} {error "mock input verification rejection"}
 return [actual_exec {*}$args]
}
rename source actual_source
proc source {path} {
 if {[file tail $path] eq "ps7_init.tcl"} {
  if {![file isfile $path]} {error "PS init missing"}
  lappend ::calls psinit_source;return
 }
 return [uplevel 1 [list actual_source $path]]
}
rename after actual_after
proc after {args} {return}
namespace eval xsdb {
 proc connect {args} {lappend ::calls connect}
 proc targets {args} {
  if {[lsearch -exact $args -set]>=0} {lappend ::calls select;return}
  incr ::queries
  if {$::queries==1} {return {}}
  if {[string match {*ARM*} [lindex $args end]]} {
   set r {};for {set i 0} {$i<$::target_count} {incr i} {lappend r [dict create name "ARM#$i"]};return $r
  }
  return [list [dict create name xc7z015]]
 }
 proc rst {args} {if {$args ne "-system"} {error "unexpected reset"};lappend ::calls rst}
 proc fpga {args} {
  set p [lindex $args 1]
  if {[file tail $p] ne "camera_cup_follow_v1.bit" || ![file isfile $p]} {error "wrong bit"}
  lappend ::calls fpga
 }
 proc ps7_init {} {lappend ::calls ps7_init}
 proc ps7_post_config {} {lappend ::calls ps7_post_config}
 proc dow {p} {
  if {[file tail $p] ne "camera_control_console.elf" || ![file isfile $p]} {error "wrong ELF"}
  lappend ::calls dow
 }
 proc con {} {lappend ::calls con}
}
if {![catch {source [file join $root run_control.tcl]}]} {error "verification rejection ignored"}
if {[llength $calls]!=0} {error "hardware touched before verification"}
set fail_verify 0;set target_count 2;set queries 0
if {![catch {source [file join $root run_control.tcl]}]} {error "ambiguous board accepted"}
if {$calls ne "connect"} {error "reset/programming before unique-board selection"}
set calls {};set target_count 1;set queries 0
source [file join $root run_control.tcl]
if {$calls ne "connect select rst select fpga select psinit_source ps7_init ps7_post_config dow con"} {
 error "wrong sequence: $calls"
}
puts "PASS actual Tcl entry: input rejection before any board action, ambiguous-target rejection before reset, matched FOLLOW V1 bit/ELF sequence; hardware mocked"
'''
(out/'test.tcl').write_text(tcl,encoding='utf-8')
exe=Path('D:/vivado/2025.2/tps/win64/git-2.50.0/mingw64/bin/tclsh86.exe')
p=subprocess.run([str(exe),str(out/'test.tcl'),str(R)],capture_output=True,text=True)
(out/'run.log').write_text(p.stdout+p.stderr,encoding='utf-8')
assert p.returncode==0 and 'PASS actual Tcl entry:' in p.stdout,p.stdout+p.stderr
(R/'validation/launcher_mock_receipt.json').write_text(json.dumps(dict(status='PASS mocked hardware; no board access',source_sha256=hashlib.sha256((R/'run_control.tcl').read_bytes()).hexdigest(),terminal=p.stdout.strip()),indent=2))
print(p.stdout.strip())
