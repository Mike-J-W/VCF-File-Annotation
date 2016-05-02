#!/usr/local/Python/2.7.8/bin
#
#  remove_PGT_PID_annotations.py
#  This script removes the PGT and PID, physical phasing info, from the format fields of samples in a VCF file
#  INPUTS:  VCF file
#  OUTPUTS: VCF file without PGT and PID
#
#  last modified on: 09/23/15
#  last modified by: Mike Warburton



import csv, sys, os

def usage():

	print("\nThis script removes the PGT and PID, physical phasing info, from the format fields of samples in a VCF file")
	print("\nINPUTS:")
	print("\tVCF file to be edited")
	print("\tName of output file")
	print("\nOUTPUT:")
	print("\tVCF file with PGT and PID removed\n")



def main():
	# Check the number of arguments to the script
	if len(sys.argv) != 3:
		print("\nERROR: Wrong number of arguments")
		usage()
		sys.exit(1)
	
	inputFileName = sys.argv[1]	# The VCF file from which to remove PGT and PID
	outputFileName = sys.argv[2]	# The name to which the output should be saved
	
	# Check that the input VCF file exists
	if not os.path.isfile(inputFileName):
		print("\nERROR: Input file, {0}, does not exist".format(inputFileName))
		usage()
		sys.exit(1)
	
	# Open the input VCF file for reading
	with open(inputFileName, 'r') as inputFile:
		# Open the output VCF file for writing
		with open(outputFileName, 'w') as outputFile:
		
			# Loop through each line of the input VCF file
			for line in inputFile:
			
				# If the line is part of the header, ignore it
				if line[0] == "#":
					outputFile.write(line)
				# If not, act
				else:
	
					splitLine = line.strip().split()	# Split the columns of the VCF line into list elements
					newLine = splitLine[:8]			# The first 7 columns of the line written to the output will be the same
	
					formatDef = splitLine[8]		# Get the content of the FORMAT field
					splitFormatDef = formatDef.split(':')	# Split the FORMAT field by ':' to get the tags inside it

					# The script starts with the assumption that it needs to remove the PGT tag
					removePGT = True			
					# Try to get the index of the PGT tag in the FORMAT field
					try:
						pgtIndex = splitFormatDef.index('PGT')
					# If the tag doesn't exist, change the removal flag
					except ValueError:
						removePGT = False

					# The script starts with the assumption that it needs to remove the PID tag
					removePID = True
					# Try to get the index of the PID in the FORMAT field
					try:
						pidIndex = splitFormatDef.index('PID')
					# If the tag doesn't exist, change the removal flag
					except ValueError:
						removePID = False
	
					# For whichever tags are present, remove them from the FORMAT field and the sample fields
					# In whichever case is appropriate, loop through the fields in the line, deleting positions from the list holding the field
					#   Then append the new field to the new line for the output file
					if removePGT and removePID:
						if pgtIndex > pidIndex:
							for field in splitLine[8:]:
								splitField = field.split(':')
								del splitField[pgtIndex]
								del splitField[pidIndex]
								newLine.append(":".join(splitField))
						else:
							for field in splitLine[8:]:
								splitField = field.split(':')
								del splitField[pidIndex]
								del splitField[pgtIndex]
								newLine.append(":".join(splitField))
	
					elif removePGT:
						for field in splitLine[8:]:
							splitField = field.split(':')
							del splitField[pgtIndex]
							newLine.append(":".join(splitField))
	
					elif removePID:
						for field in splitLine[8:]:
							splitField = field.split(':')
							del splitField[pidIndex]
							newLine.append(":".join(splitField))
					
					# If neither tag is present, no work is required
					else:
						newLine += splitLine[8:]
	
					# Write the new line to the output VCF file
					outputFile.write("\t".join(newLine))


if __name__ == "__main__":
	main()
