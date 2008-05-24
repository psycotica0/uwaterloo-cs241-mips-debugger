################
#Mips.tcl: This is a tcl library that handles running MIPS assembly code
#	It handles all virtual machining, including registers, and virtual memory.
#	It also has an instruction to parse a single line of MIPS assembly (As used in CS 241)
#	And a function for each MIPS command, that does the same thing as that command
#
#	Written by Christopher Vollick
#	I should probably pick a license
################

###
#InitializeMachine: This function sets up the registers and virtual memory. 
#	It must be called before anything else tries to run.
###
proc InitializeMachine {} {
	global Registers VirtualMemory ProgramCounter Labels Output Instructions MFLO MFHI
	foreach item [GenerateRangeList 0 31] {
		#Initialize all registers
		set Registers($item) 0 
	}
	#Then set the return register (-1 is the default exit item for me)
	set Registers(31) -1
	#And the address for stack
	set Registers(30) [expr 0x100000]
	#Output buffer emptied
	set Output ""
	#Initialize PC 
	set ProgramCounter 0
	#Initialize MFLO and MFHI
	set MFLO 0
	set MFHI 0
	#Set the regular expression for the different instructions
	set Instructions [list {(add|sub|slt|sltu)\s+\$(\d+)\s*,\s*\$(\d+)\s*,\s*\$(\d+)}]
	lappend Instructions {(mult|multu|div|divu)\s+\$(\d+)\s*,\s*\$(\d+)}
	lappend Instructions {(mfhi|mflo|lis|jr|jalr)\s+\$(\d+)}
	lappend Instructions {(lw|sw)\s+\$(\d+)\s*,\s*(\+?\d+|-\d+|0x[[:xdigit:]]+)\s*\(\$(\d+)\)}
	lappend Instructions {(bne|beq)\s+\$(\d+)\s*,\s*\&(\d+)\s*,\s*(\+?\d+|-\d+|0x[[:xdigit:]]+|[a-zA-z]\w+)}
	#.word, I've decided isn't a command. It just tells me to load that value at that point in memory
	#lappend Instructions {(\.word)\s+(\+?\d+|-\d+|0x[[:xdigit:]]+|[a-zA-Z]\w+)}
}

###
#SetRegister: This function sets the value of a register
#
#	Reg: This is the register to set
#	Val: This is the value to set it to
###
proc SetRegister {Reg Val} {
	global Registers
	if {$Reg < 0 || $Reg > 31} {
		error "Invalid Register"
	}
	if {$Reg != 0} {
		#No need to set 0, we want it to always be 0
		set Registers($Reg) $Val
	}
}

###
#GetRegister: This function gets the value of a register
#
#	Reg: This is the register to get
###
proc GetRegister {Reg} {
	global Registers
	if {$Reg < 0 || $Reg > 31} {
		error "Invalid Register"
	}
	if {$Reg == 0} {
		#Register 0 is always 0
		return 0
	}
	return $Registers($Reg)
}

###
#SetVirtualMemory: This function puts a value at a location in virtual memory
#	The value 0xffff000c is special, it's put into the output buffer
#	
#	Loc: This is the location in memory to put it
#	Val: This is the value to put in memory
###
proc SetVirtualMemory {Loc Val} {
	global Output VirtualMemory
	if {$Loc < 0 || $Loc > [expr 0x100000]} {
		error "Invalid Memory Location"
	}
	if {fmod($Loc, 4) != 0} {
		error "Unaligned Memory Access"
	}
	if {$Loc == 0xffff000c} {
		lappend Output [format %c $Val]
		return 
	}
	set VirtualMemory($Loc) $Val
}

###
#GetVirtualMemory: This function reads a value from virtual memory
#
#	Loc: This is the location to read from
###
proc GetVirtualMemory {Loc} {
	global VirtualMemory
	if {$Loc < 0 || $Loc > [expr 0x100000]} {
		error "Invalid Memory Location"
	}
	if {fmod($Loc, 4) != 0} {
		error "Unaligned Memory Access"
	}
	if {[info exists VirtualMemory($Loc)]} {
		return $VirtualMemory($Loc)
	}
	error "Uninitialized Memory Access"
}

###
#GetLabel: This function returns the instruction a label points to.
#
#	Name: This is the name of label
###
proc GetLabel {Name} {
	global Labels
	if {[info exists Labels($Name)]} {
		return $Labels($Name)
	}
	error "Undefined Label"
}

###
#ParseInstruction: This function takes in a string representing an instruction in MIPS assembly
#	It doesn't return anything, it just run the correct command, to affect the correct results
#
#	Inp: This is the instruction to parse
###
proc ParseInstruction {Inp} {
	global Instructions
	foreach Type $Instructions {
		if {[regexp "^(?:[^;]*:)?\\s*$Type\\s*(?:;.*)?" $Inp Mat Command A1 A2 A3]} {
			#All command functions must have 3 arguments, and if it doesn't need them, it can ignore them
			eval [list MIPS_$Command $A1 $A2 $A3]
			return
		}
	}
	error "Unknown Instruction"
}

###
#MIPS_add: This command adds the values of two registers, and puts the value in a third
#
#	A1: This is the destination
#	A2: This is the first thing to add
#	A3: This is the second thing to add
###
proc MIPS_add {A1 A2 A3} {
	SetRegister $A1 [expr {[GetRegister $A2] + [GetRegister $A3]}]
}

###
#MIPS_sub: This command subtractions the values of two registers, and puts the value in a third
#
#	A1: This is the destination
#	A2: This is the first thing
#	A3: This is the second thing
###
proc MIPS_sub {A1 A2 A3} {
	SetRegister $A1 [expr {[GetRegister $A2] + [GetRegister $A3]}]
}

###
#MIPS_slt: This command checks if one register is less than another, and puts a 1 or 0 in another register about it
#
#	A1: This is the destination of the answer
#	A2: This is the first number
#	A3: This is the second number
###
proc MIPS_slt {A1 A2 A3} {
	SetRegister $A1 [expr {[GetRegister $A2] < [GetRegister $A3]}]
}

###
#MIPS_sltu: This command does the same as MIPS_slt, except numbers are considered unsigned
#
#	A1: This is the destination of the answer
#	A2: This is the first number
#	A3: This is the second number
###
proc MIPS_sltu {A1 A2 A3} {
	SetRegister $A1 [expr {[format %u [GetRegister $A2]] < [format %u [GetRegister $A2]]}]
}

###
#MIPS_mult: This command multiplies two values and puts the result in MFLO, with any overflow in MFHI
#
#	A1: This is the first number
#	A2: This is the second number
#	A3: This isn't used
###
proc MIPS_mult {A1 A2 A3} {
	global MFHI MFLO
	set V1 [format %08x [GetRegister $A1]]
	set V2 [format %08x [GetRegister $A2]]
	set a [string range $V1 0 3]
	set b [string range $V1 4 end]
	set c [string range $V2  0 3]
	set d [string range $V2 4 end]
}

###
#MIPS_multu: This command multiplies two unsigned values and puts the results in MFLO and any overflow in MFHI
#
#	A1: This is the first number
#	A2: This is the second number
#	A3: This isn't used
###
proc MIPS_multu {A1 A2 A3} {
	global MFHI MFLO
}

###
#MIPS_div: This command divides two signed numbers and put the quotient in MFLO and remainder in MFHI
#
#	A1: This is the first item
#	A2: This is the second number
#	A3: This is not used
###
proc MIPS_div {A1 A2 A3} {
	global MFHI MFLO
	set MFLO [expr {int([GetRegister $A1]/[GetRegister $A2])}]
	set MFHI [expr {[GetRegister $A1] % [GetRegister $A2]}]
}

###
#MIPS_divu: This command divides two unsigned numbers
#
#	A1: This is the first item
#	A2: This is the second number
#	A3: This is not used
###
proc MIPS_div {A1 A2 A3} {
	global MFHI MFLO
	set MFLO [expr {int([format %u [GetRegister $A1]]/[format %u [GetRegister $A2]])}]
	set MFHI [expr {[format %u [GetRegister $A1]] % [format %u [GetRegister $A2]]}]
}

###
#MIPS_sw: This command puts a value from a register and puts it into virtual memory
#
#	A1: This is the register that holds the value
#	A2: This is the offset from the place in memory
#	A3: This is the register that holds the memory location
###
proc MIPS_sw {A1 A2 A3} {
	SetVirtualMemory [expr {[GetRegister $A3] + $A2}] [GetRegister $A1]
}

###
#MIPS_lw: This command loads a value from memory and puts it into a register
#
#	A1: This is the register that will hold the value
#	A2: This is the offset from the place in memory
#	A3: This is the register that holds the memory location
###
proc MIPS_lw {A1 A2 A3} {
	SetRegister $A1 [GetVirtualMemory [expr {[GetRegister $A3] + $A2}]]
}

###
#MIPS_lis: This function loads the next item into the given register
#
#	A1: This is the destination
#	A2: Unused
#	A3: Unused
##
proc MIPS_lis {A1 A2 A3} {
	global ProgramCounter
	SetRegister $A1 [GetVirtualMemory $ProgramCounter]
	incr ProgramCounter
}

###
#MIPS_mflo: This command puts a result from MFLO into a register
#
#	A1: This is the destination
#	A2: Unused
#	A3: Unused
###
proc MIPS_mflo {A1 A2 A3} {
	global MFLO
	SetRegister $A1 $MFLO
}

###
#MIPS_mfhi: This command puts a result from MFHI to a register
#
#	A1: This is the destination
#	A2: Unused
#	A3: Unused
###
proc MIPS_mfhi {A1 A2 A3} {
	global MFHI
	SetRegister $A1 $MFHI
}

###
#MIPS_beq: This command changes the program counter if two registers are equal
#
#	A1: This is the first thing to test
#	A2: This is the second
#	A3: This is where to go
#		It could be a number to add to the PC, or a label
###
proc MIPS_beq {A1 A2 A3} {
	global ProgramCounter
	if {[GetRegister $A1] == [GetRegister $A2]} {
		if {[regexp {\w+} $A3]} {
			#This is a label
			set ProgramCounter [GetLabel $A3]
		} else {
			#Given an integer
			set ProgramCounter [expr {$ProgramCounter + $A2}]
		}
	}
}

###
#MIPS_bne: This command changes the program counter if two registers aren't equal
#
#	A1: This is the first thing to test
#	A2: This is the second
#	A3: This is where to go
#		It could be a number to add to the PC, or a label
###
proc MIPS_bne {A1 A2 A3} {
	global ProgramCounter
	if {[GetRegister $A1] != [GetRegister $A2]} {
		if {[regexp {\w+} $A3]} {
			#This is a label
			set ProgramCounter [GetLabel $A3]
		} else {
			#Given an integer
			set ProgramCounter [expr {$ProgramCounter + $A2}]
		}
	}
}

###
#MIPS_jr: This command changes the PC to an absolute value
#	If it's a -1, this means exit
#
#	A1: This is the register to get the value from
#	A2: No Use
#	A3: No Use
###
proc MIPS_jr {A1 A2 A3} {
	global ProgramCounter
	set ProgramCounter [GetRegister $A1]
	if {$ProgramCounter == -1} {
		error "Complete"
	}
}

###
#MIPS_jalr: This command sets register 31 to the PC before jumping
#	If it's -1, this also means exit
#
#	A1: This is the register to get the value from
#	A2: No
#	A3: No
###
proc MIPS_jalr {A1 A2 A3} {
	global ProgramCounter
	SetRegister 31 $ProgramCounter
	MIPS_jr $A1 $A2 $A3
}

###
#GenerateRangeList: This function takes in a starting and ending integer and returns a list containing every item in that range, including the end points
#
#	Start: This is the integer to start at
#	End: This is the integer to end at
###
proc GenerateRangeList {Start End} {
	set Result ""
	for {set i $Start} {$i <= $End} {incr i} {
		lappend Result $i
	}
	return $Result
}

InitializeMachine
