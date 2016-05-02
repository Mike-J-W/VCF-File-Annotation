#!/bin/bash
#
#  annotateExAC.worker.sh
#  This script performs ExAC homozygote annotation on a VCF segment
#  INPUTS:  VCF segment, output file, ExAC database
#  OUTPUTS: annotated VCF segment
#
#  Last modified on: 09/21/15
#  Last modified by: Mike Warburton


# Check the number of arguments
if [ $# -lt 6 ] || [ $# -gt 7 ]; then
	echo -e "\nERROR: Incorrect number of arguments\n"
	exit 1
fi

# Collect the arguments
clearInfo=false
while getopts "i:o:d:c" OPTION; do
	case "$OPTION" in
		i)
			inputFile="$OPTARG";;
		o)
			outputFile="$OPTARG";;
		d)
			exacDb="$OPTARG";;
		c)
			clearInfo=true;;
		\?)
			echo -e "\nERROR: Unrecognized option\n"
			exit 1;;
	esac
done

# Set 2 of the main variables
outputDir=`dirname $outputFile`
inputBase=`basename $inputFile`

lastExacClean="foo"
# Read the input file and delimit by tab to access each field individually
while read chrName pos id ref alt qual filter info format samples; do

	# Skip any header line
	if [[ $chrName == "#"* ]]; then
		continue
	fi

	homozygScore=""

	# Add the 'chr' prefix to the chr number
	chrNum=${chrName#chr}
	chr="chr$chrNum"

	# Set up the file to hold the gene info from the gene table
	exacRaw=$outputDir/${inputBase}.${chr}.${pos}.exacRaw.temp
	exacClean=$outputDir/${inputBase}.${chr}.${pos}.exacClean.temp
	if [ "$exacClean" != "$lastExacClean" ]; then
		if [ -e "$lastExacClean" ]; then
			rm $lastExacClean
		fi
		lastExacClean="$exacClean"
	fi

	# Retrieve the ExAC data that matches the chromosome and position
	if [ ! -e "$exacClean" ]; then
		tabix $exacDb ${chrNum}:${pos}-${pos} | grep "\b$pos\b" > $exacRaw
		if [ -s $exacRaw ]; then
			
			exacRef=`cut -f 4 $exacRaw`
			exacAlt=`cut -f 5 $exacRaw`
			exacAnno=`cut -f 8 $exacRaw`
			python /data/Udpwork/usr/Common/Git/VCF_scripts/Annotation/annotateExAC.extracter.py "$exacClean" "$exacRef" "$exacAlt" "$exacAnno"
			if [ $? == 1 ]; then
				echo "There was an error in annotateExAC.extracter.py for $chrNum, $pos, $ref,$alt"
			fi
		fi		
		if [ -e $exacRaw ]; then
			rm $exacRaw
		fi
	fi

	if [ -e "$exacClean" ]; then
		homozygScore=`awk -v r="$ref" -v a="$alt" '($1 == r) && ($2 == a)' $exacClean | cut -f 3`
	fi
	if [ "$homozygScore" == "" ]; then
		homozygScore=-1
	fi

	newInfo="exac_AC_hom=$homozygScore"
	if $clearInfo || [ $info == "." ]; then
		info=$newInfo
	else
		info+=";$newInfo"
	fi

	# Print the fields to the output file
	echo -e "$chrName\t$pos\t$id\t$ref\t$alt\t$qual\t$filter\t$info\t$format\t$samples" >> $outputFile


done < $inputFile
