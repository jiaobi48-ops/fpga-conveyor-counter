# XSDB stdin/stdout bridge for camera-frame reads and control-mailbox requests.
fconfigure stdin -encoding utf-8 -translation lf
fconfigure stdout -encoding utf-8 -translation lf -buffering line
proc studio_error {id msg} {puts "STUDIO_ERROR $id [binary encode base64 -maxlen 0 [encoding convertto utf-8 $msg]]";flush stdout}
proc studio_read_allowed {a n} {
 foreach {lo hi} {0x02000000 0x02004000 0x023FFFC0 0x026A3040 0x03000000 0x03003000} {
  if {$a>=$lo && $a+$n<=$hi} {return 1}
 }
 return 0
}
if {[catch {
 namespace eval xsdb {
  connect -url tcp:127.0.0.1:3121
  set cpus [targets -target-properties -nocase -filter {name =~ "ARM*#0"}]
  if {[llength $cpus]!=1} {error "Expected one ARM core0. Check board power and JTAG connection."}
  targets -set -nocase -filter {name =~ "ARM*#0"}
 }
} msg]} {studio_error 0 $msg;exit 1}
puts "STUDIO_CONNECTED 0";flush stdout
while {[gets stdin line]>=0} {
 set items [split [string trim $line]];set id [lindex $items 0];set op [lindex $items 1]
 if {![string is integer -strict $id] || $id<1} {studio_error 0 "Invalid request id";continue}
 if {[catch {
  if {$op eq "READ"} {
   if {[llength $items]!=4} {error "READ shape"}
   set a [lindex $items 2];set n [lindex $items 3]
   if {![string is entier -strict $a] || ![string is integer -strict $n] || $a%4 || $n<4 || $n%4 || $n>65536 || ![studio_read_allowed $a $n]} {error "DDR read outside allowed range"}
   set bytes [::xsdb::mrd -bin -size w $a [expr {$n/4}]]
   if {[string length $bytes]!=$n} {error "Short DDR read"}
   puts "STUDIO_DATA $id [binary encode base64 -maxlen 0 $bytes]"
  } elseif {$op eq "WRITE"} {
   set a [lindex $items 2];set values [lrange $items 3 end]
   if {![string is entier -strict $a] || $a%4 || [llength $values]<1 || [llength $values]>9 || $a<0x03000008 || $a+4*[llength $values]>0x0300002c} {error "Only studio DDR request words are writable"}
   foreach v $values {if {![string is entier -strict $v] || $v<0 || $v>0xffffffff} {error "Invalid request word"}}
   ::xsdb::mwr -size w $a $values
   puts "STUDIO_OK $id"
  } elseif {$op eq "QUIT"} {puts "STUDIO_OK $id";flush stdout;break
  } else {error "Unknown operation"}
 } msg]} {studio_error $id $msg}
 flush stdout
}
