################
#Debugger.tcl: This file has all the code that runs the debugger, it runs the code using the Mips.tcl library
#
#	Written by Christopher Vollick
#	Also, license
################

source Mips.tcl

###
#LoadFile: This command takes in a filename and loads it
#
#	Filename: Guess
###
proc LoadFile {Filename} {
	set F [open $Filename r]
	ParseFile [read $F]
	close $F
}

###
#ParseFile: This command takes in a the contents of a file and breaks it up
#	It seperates it into lines, and stores these in "Contents"
#	It makes the Program list, which is the indecies of Contents that are actually commands, and the order they're run in
#		This is the actual part that is run using the PC, the Contents are just for display
#	It finds all labels, and puts them in the Labels array, and points them to the proper point in the Program list
#	It replaces .word instructions with their values, and puts these in the proper place in virtual memory
#
#	Inp: This is the contents of a MIPS asm file.
###
proc ParseFile {Inp} {
	global Contents Program Labels
	set Contents [split $Inp "\n"]

	#If a .word is reached that needs a label that has yet to be defined, add it to the array LabelNeeded for jump back
	#Each item in the array is a named the name of the label, and it's value is a list of all positions in memory to add its value to

	for {set i 0} {$i < [llength $Contents]} {incr i} {
		set Item [lindex $Contents $i]
		if {[regexp {^[^;]*:} $Item Label]} {
			#Split up mutliple labels
			set Label [split $Label ":"]
			foreach L $Label {
				#Ignore blank labels
				if {[regexp {^\s*$} $L]} continue

				if {[info exists Labels($L)]} {
					error "Duplicate Label: $L"
				}
				if {[info exists LabelNeeded($L)]} {
					#This label has been used already, but is only being defined now.
					foreach Pos $LabelNeeded($L) {
						SetVirtualMemory [expr {4*$Pos}] [llength $Program]
					}
					unset LabelNeeded($L)
				}
				set Labels($L) [llength $Program]
			}
		}
		if {[regexp {^(?:[^;]*:)?([^;:]+)(;.*)?$} $Item Mat Command]} {
			#This is a line with more than Labels or comments on it
			if {[regexp {\.word\s+([+-]?\d|0x[[:xdigit:]]+|[a-zA-Z]\w+)} $Mat M Num]} {
				#This line must be added to the virtual memory for lis to work
				if {[regexp {^[a-zA-Z]} $Num]} {
					#This is a label
					if {[info exists Labels($Num)]} {
						#The label's already been found and added to the list
						SetVirtualMemory [expr {4*[llength $Program]}] [GetLabel $Num]
					} else {
						#The label doesn't exist yet
						if {[info exists LabelNeeded($Num)]} {
							#This isn't the first time the label's been needed
							lappend LabelNeeded($Num) [llength $Program]
						} else {
							#This is the first time the label's been needed
							set LabelNeeded($Num) [llength $Program]
						}
					}
				} else {
					#This is not a label, but a single value
					SetVirtualMemory [expr {4*[llength $Program]}] [expr {$Num}]
				}
			}
			puts $Item
			lappend Program $i
		}
	}
	foreach Lost [array names LabelNeeded] {
		error "The following label was never matched: $Lost"
	}
}
