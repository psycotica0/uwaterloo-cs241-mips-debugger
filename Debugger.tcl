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
	global FileOpen
	set FileOpen 0
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
	global Contents Program Labels FileOpen ProgramCounter CurrentItem FileView
	set Contents [split $Inp "\n"]
	set Program ""
	set ProgramCounter 0
	if {[info exists CurrentItem]} {
		$FileView itemconfigure $CurrentItem -background ""
		unset CurrentItem
	}

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
		if {[regexp {^(?:[^;]*:)?\s*([A-Za-z.][^:;]*)(;.*)?$} $Item Mat Command]} {
			#This is a line with more than Labels or comments on it
			if {[regexp {\.word\s+([+-]?\d+|0x[[:xdigit:]]+|[a-zA-Z]\w+)} $Item M Num]} {
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
					SetVirtualMemory [expr {4*[llength $Program]}] [format %i [expr {$Num}]]
				}
			}
			lappend Program $i
		}
	}
	foreach Lost [array names LabelNeeded] {
		error "The following label was never matched: $Lost"
	}
	UpdateLine
	set FileOpen 1
}

###
#NextInstruction: This command runs the next instruction
###
proc NextInstruction {} {
	global ProgramCounter Contents Program FileOpen
	if {$FileOpen == 0} {
		tk_messageBox -message "No Open File"
		return
	}
	set Com [lindex $Contents [lindex $Program $ProgramCounter]]
	incr ProgramCounter
	if {[catch {ParseInstruction $Com} ErrorMsg]} {
		#Here, there was an error in this file
		if {[string equal $ErrorMsg "Complete"]} {
			tk_messageBox -message "Complete"
			set ProgramCounter 0
		} else {
			tk_messageBox -message "Error: $ErrorMsg
			Line [expr 1+[lindex $Program [expr {$ProgramCounter-1}]]]"
		}
	}
	UpdateLine
}

###
#UpdateLine: This function updates the highlighted line of the FileView to represent the next command to be executed
###
proc UpdateLine {} {
	global ProgramCounter Program FileView CurrentItem
	if {$ProgramCounter >= [llength $Program]} {
		#There's a big problem here.
		#Either the code has made a jump to a register that isn't supposed to be jumped to
		#Or the code didn't have a jr $31 at the end
		tk_messageBox -message "Error: The code has started executing arbitrary areas in memory. 
		This is probably due to an invalid jump, or not exiting to the OS properly."
		set ProgramCounter 0
		return
	}
	#$FileView selection clear 0 end
	if {[info exists CurrentItem]} {
		$FileView itemconfigure $CurrentItem -background ""
	}
	set CurrentItem [lindex $Program $ProgramCounter]
	$FileView see $CurrentItem
	$FileView itemconfigure $CurrentItem  -background "red"
	#$FileView selection set [lindex $Program $ProgramCounter]
}

###
#CleanExit: This function is here, incase something needs to be done before exit
###
proc CleanExit {} {
	exit
}

###
#OpenMenu: This function runs the Open box from the menu
###
proc OpenMenu {} {
	set File [tk_getOpenFile -defaultextension ".asm" -filetypes [list [list "Assembler Files" ".asm"] [list "All Files" "*"]]]
	if {![regexp {^\s*$} $File]} {
		#This is a file
		InitializeMachine
		LoadFile $File
	}
}

###
#ToLine: This function will continue executing the file until the line that is given is the one the PC points to
#	Or the file exits, whichever comes first
#
#	Line: This is the line to go to
###
proc ToLine {Line} {
	global ProgramCounter Contents Program FileOpen
	if {$FileOpen == 0} {
		tk_messageBox -message "No Open File"
		return
	}
	while {$Line != $ProgramCounter} {
		set Com [lindex $Contents [lindex $Program $ProgramCounter]]
		incr ProgramCounter
		if {[catch {ParseInstruction $Com} ErrorMsg]} {
			#Here, there was an error in this file
			if {[string equal $ErrorMsg "Complete"]} {
				tk_messageBox -message "Complete"
				set ProgramCounter 0
				break
			} else {
				tk_messageBox -message "Error: $ErrorMsg
				Line [expr 1+[lindex $Program [expr {$ProgramCounter-1}]]]"
				break
			}
		}
	}
	UpdateLine
}

###
#ToCurrentLine: This function is a kind of front end for ToLine
#	This one finds the line that has selection in the FileView and goes to that
###
proc ToCurrentLine {} {
	global FileView Program
	set C [$FileView curselection]
	if {[llength $C] >0 } {
		#There is a selected line
		for {set i 0} {$i < [llength $Program]} {incr i} {
			set Item [lindex $Program $i]
			if {$C <= $Item} {
				#This is the first item that is an actual instruction after the current pointer
				ToLine $i
				return
			}
		}
		#If we're here, then there is no instruction after this line
		#Just do until the last instruction
		ToLine $Item
	} else {
		tk_messageBox -message "No currently selected line"
	}
}

###
#RegisterWindow: This function makes the window with all registers on it
#
#	Loc: This is where to draw it
###
proc RegisterWindow {Loc} {
	if {[winfo exists $Loc]} {
		destroy $Loc
		return
	} 
	toplevel $Loc 
	wm title $Loc "Registers"
	bind $Loc <F6> {RegisterWindow .reg}
	bind $Loc <F7> {NextInstruction}
	#This makes an N by M array of boxes with the correct label
	set N 4
	set M 8
	for {set m 0} {$m < $M} {incr m} {
		set ListOfStuff ""
		for {set n 0} {$n < $N} {incr n} {
			#Draw
			set Number [expr {$m*$N+$n}]
			set La [label $Loc.l$Number -text $Number]
			set Box [entry $Loc.e$Number -textvariable Registers($Number)]
			append ListOfStuff "$La $Box "
		}
		eval grid $ListOfStuff
	}
	#For standard output
	entry $Loc.stdout -textvariable Output -state disabled
	label $Loc.lout -text "Output:"
	grid $Loc.lout $Loc.stdout
	$Loc.e0 configure -state disabled
}

###
#ArrayEditor: This function creates a window that allows for editing and creating of an array
#	It will be, for now at least, just a comma separated list of items to write into memory just after the commands and a button to write them, and a button to write the address into register 1
#
#	Loc: This is the location to draw it at
###
proc ArrayEditor {Loc} {
	if {[winfo exists $Loc]} {
		destroy $Loc
		return
	} else {
		#Draw the thing
		toplevel $Loc
		wm title $Loc "Array Editor"
		set La [label $Loc.label -text "Comma Separated List:"]
		set CSV [entry $Loc.csv -textvariable ArrayCSV]
		bind $CSV <Return> "WriteArray $Loc"
		set Write [button $Loc.write -text "Write to Memory" -command "WriteArray $Loc"]
		grid $La $CSV 
		grid x $Write
		grid $CSV -sticky news
	}
}

###
#WriteArray: This function takes the csv from ArrayCSV and puts them into an array after the current program
#
#	Loc: This is the address of the window to close
###
proc WriteArray {Loc } {
	global ArrayCSV Program
	set Items [split $ArrayCSV ","]
	set Start [expr {4*[llength $Program]}]
	SetRegister 1 $Start
	set Count 0
	foreach Item $Items {
		if {![regexp {^\s*[+-]?\d+\s*$} $Item]} {
			#Skip items that aren't numbers
			continue
		}
		SetVirtualMemory $Start $Item
		incr Count
		incr Start 4
	}
	SetRegister 2 $Count
	#Close the window
	ArrayEditor $Loc
}


#Draw the window
set FileView [listbox .view -width 50 -height 20 -listvariable Contents -xscrollcommand ".vx set" -yscrollcommand ".vy set"]
set FxScroll [scrollbar .vx -orient horizontal -command "$FileView xview"]
set FyScroll [scrollbar .vy -orient vertical -command "$FileView yview"]
grid $FileView $FyScroll
grid $FxScroll
grid $FileView -sticky news 
grid $FyScroll -sticky ns
grid $FxScroll -sticky ew
grid rowconfig . 0 -weight 1
grid columnconfig . 0 -weight 1

#Set up the menu
menu .menubar
.menubar add cascade -label "File" -menu .menubar.file
menu .menubar.file
.menubar.file add command -label "Open File" -command OpenMenu
.menubar.file add command -label "Exit" -command CleanExit
.menubar add cascade -label "Debug" -menu .menubar.debug
menu .menubar.debug
.menubar.debug add command -label "Next Line" -command NextInstruction -accelerator "F7"
.menubar.debug add command -label "To Current Line" -command ToCurrentLine -accelerator "F8"
.menubar.debug add separator
.menubar.debug add command -label "Display Registers" -command {RegisterWindow .reg} -accelerator "F6"
.menubar.debug add command -label "Array Editor" -command {ArrayEditor .ary}
. configure -menu .menubar

bind . <F7> NextInstruction
bind . <F6> {RegisterWindow .reg}
bind . <F8> {ToCurrentLine}
wm title . "MIPS Debugger"

#Initialize the file open to 0
set FileOpen 0
#If there's an input file, open it
if {$argc > 0} {
	if {[string equal [lindex $argv 0] "-"]} {
		#Read from stdin
		if {[catch {
			ParseFile [read stdin]
			} ErrorMsg]} {
			tk_messageBox -message "Error loading from stdin: 
			$ErrorMsg"
		}
	} else {
		if {[catch {
			LoadFile [lindex $argv 0]
			} ErrorMsg]} {
			tk_messageBox -message "Error loading file:
			$ErrorMsg"
		}
	}
}
