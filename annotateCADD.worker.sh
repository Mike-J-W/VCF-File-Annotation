#!/bin/bash
#
#  annotateCADD.worker.sh
#  The script performs CADD annoatation on a VCF segment
#  INPUTS:  VCF segment, output name, CADD databases
#  OUTPUTS: annotated VCF segment
#
#  Last modified on: 09/23/15
#  Last modified by: Mike Warburton


# Check the number of arguments
if [ $# -lt 12 ] || [ $# -gt 14 ]; then
	echo -e "\nERROR: Incorrect number of arguments\n"
	exit 1
fi

# Collect the arguments
clearInfo=false
outputAll=false
while getopts "i:o:f:s:d:e:ca" OPTION; do
	case "$OPTION" in
		i)
			inputFile="$OPTARG";;
		o)
			outputFile="$OPTARG";;
		f)
			failedFile="$OPTARG";;
		s)
			caddSNVs="$OPTARG";;
		d)
			caddInDels="$OPTARG";;
		e)
			caddExtras="$OPTARG";;
		c)
			clearInfo=true;;
		a)
			outputAll=true;;
		\?)
			echo -e "\nERROR: Unrecognized option\n"
			exit 1;;
	esac
done

# Read the input file and delimit by tab to access each field individually
while read chrName pos id ref alt qual filter info format samples; do

	if [[ "$chrName" == "#"* ]]; then
		continue
	fi

	# Set up the pattern to match the variable to store the result
	chr=${chrName#chr}
	stringToMatch=`echo -e "$chr\t$pos\t$ref\t$alt"`
	caddString=""

	# If the reference and alt sequences hav the same length, use the SNV databse
	if [ ${#ref} -eq ${#alt} ]; then
		caddString=`tabix $caddSNVs $chr:$pos-$pos | grep "$stringToMatch"`

	# If they differ, use the InDel database
	else
		caddString=`tabix $caddInDels $chr:$pos-$pos | grep "$stringToMatch"`
	fi

	# If the standard database returns no result, check the locally-compiled web-scored database
	if [ "$caddString" == "" ]; then
		caddString=`tabix $caddExtras $chr:$pos-$pos | grep "$stringToMatch"`
	fi

	# If the 'clear INFO' flag was set, erase all prior annotations
	if $clearInfo || [ "$info" == "." ]; then
		info=""
	else
		info="$info;"
	fi

	# If no match was found, print the VCF line to the NoCADD output VCF file
	if [ "$caddString" == "" ]; then

		info="${info}cadd_raw=-99;cadd_phred=-100"

		# Print the line to the failed file
		echo -e "$chrName\t$pos\t$id\t$ref\t$alt\t$qual\t$filter\t$info\t$format\t$samples" >> $failedFile
		# If the flag is true, also print the line to the output file
		if $outputAll; then
			echo -e "$chrName\t$pos\t$id\t$ref\t$alt\t$qual\t$filter\t$info\t$format\t$samples" >> $outputFile
		fi

	# If a match was found, print the VCF line to the annotated VCF file
	else

		# Grab the CADD scores from the result
		caddRaw=`echo $caddString | cut -d' ' -f5`
		caddPhred=`echo $caddString | cut -d' ' -f6`

		# Create the new annotation and print the line
		info="${info}cadd_raw=$caddRaw;cadd_phred=$caddPhred"
		echo -e "$chrName\t$pos\t$id\t$ref\t$alt\t$qual\t$filter\t$info\t$format\t$samples" >> $outputFile

	fi

done < $inputFile
